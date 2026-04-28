#!/usr/bin/env bash
# 异常用户实时告警（每 15 分钟跑一次）
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SQL_DIR="${SCRIPT_DIR}/../sql"

PG_DSN="${BI_PG_DSN:?需要 BI_PG_DSN}"
TG_TOKEN="${TELEGRAM_BOT_TOKEN}"
TG_CHAT="${TELEGRAM_OPS_CHAT_ID}"

# 已经告警过的，避免重复（用 redis SET 记 30 分钟）
REDIS="${REDIS_URL:-redis://localhost:6379}"

ANOM=$(psql "$PG_DSN" -At -F'|' -f "${SQL_DIR}/anomaly-users.sql")

[[ -z "$ANOM" ]] && { echo "no anomaly"; exit 0; }

while IFS='|' read -r uid uname email spent_1h calls_1h models_1h spent_24h avg_hour spike reasons; do
    [[ -z "$uid" ]] && continue

    # 去重
    KEY="anom:${uid}:$(date +%H | awk '{print int($1/0.5)}')"  # 30 分钟窗口
    if redis-cli -u "$REDIS" SET "$KEY" 1 EX 1800 NX | grep -q OK; then
        MSG=$(cat <<EOF
🚨 *用户异常*

用户：${uname} (#${uid})
邮箱：${email}

1h 消耗：\$${spent_1h}
1h 调用：${calls_1h}
1h 模型：${models_1h}
24h 消耗：\$${spent_24h}
30天小时均值：\$${avg_hour}
突增倍数：${spike}x

原因：${reasons}

🔧 [封停](https://admin.example.com/user/${uid}/disable)
🔍 [查日志](https://admin.example.com/log?user_id=${uid})
EOF
)
        curl -fsS "https://api.telegram.org/bot${TG_TOKEN}/sendMessage" \
            -d "chat_id=${TG_CHAT}" \
            -d "text=${MSG}" \
            -d "parse_mode=Markdown" \
            -d "disable_web_page_preview=true" >/dev/null
    fi
done <<< "$ANOM"
