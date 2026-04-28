#!/usr/bin/env bash
# 每日早报：跑 daily-report.sql 后推送到 Telegram + 邮件
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SQL_DIR="${SCRIPT_DIR}/../sql"

PG_DSN="${BI_PG_DSN:?需要 BI_PG_DSN（只读副本）}"
TG_TOKEN="${TELEGRAM_BOT_TOKEN}"
TG_CHAT="${TELEGRAM_BIZ_CHAT_ID}"

YESTERDAY=$(date -d 'yesterday' +%Y-%m-%d 2>/dev/null || date -v-1d +%Y-%m-%d)

# 跑 SQL 拿数据（CSV）
DATA=$(psql "$PG_DSN" -At -F'|' -f "${SQL_DIR}/daily-report.sql")

IFS='|' read -ra F <<< "$DATA"

GMV="${F[0]}"
COST="${F[1]}"
PROFIT="${F[2]}"
MARGIN="${F[3]}"
REFUND="${F[4]}"
DAU="${F[5]}"
NEW_USERS="${F[6]}"
PAYING="${F[7]}"
DAU_GROWTH="${F[8]}"
API_REQ="${F[9]}"
SUCCESS_RATE="${F[10]}"
ACTIVE_CH="${F[11]}"
TOTAL_CH="${F[12]}"
NEW_CH="${F[13]}"
DISABLED_CH="${F[14]}"
GMV_GROWTH="${F[15]}"

# 取异常用户
ANOM=$(psql "$PG_DSN" -At -f "${SQL_DIR}/anomaly-users.sql" | head -3)

# 渠道劣化
SICK=$(psql "$PG_DSN" -At -f "${SQL_DIR}/channel-health.sql" | head -3)

REPORT=$(cat <<EOF
📊 *AITransfer 早报 - ${YESTERDAY}*
━━━━━━━━━━━━━━━━━━━━━━

💰 *财务*
   GMV         \$$(printf '%.2f' "$GMV") (${GMV_GROWTH}%)
   毛利        \$$(printf '%.2f' "$PROFIT")
   毛利率      $(printf '%.1f' "$MARGIN")%
   退款        \$$(printf '%.2f' "$REFUND")

👥 *用户*
   DAU         ${DAU} (${DAU_GROWTH}%)
   新增        ${NEW_USERS}
   付费        ${PAYING}

🔌 *API*
   请求量      ${API_REQ}
   成功率      $(printf '%.1f' "$SUCCESS_RATE")%

🏊 *号池*
   活跃        ${ACTIVE_CH} / ${TOTAL_CH}
   今日新增    ${NEW_CH}
   今日离池    ${DISABLED_CH}

⚠️ *关注*
$([[ -n "$ANOM" ]] && echo "$ANOM" | head -3 | awk -F'|' '{print "   • 异常用户 " $2 " 1h消耗 $" $4}' || echo "   • 无异常用户")
$([[ -n "$SICK" ]] && echo "$SICK" | head -3 | awk -F'|' '{print "   • 渠道劣化 " $2 " 健康分 " $14 " (" $15 ")"}' || echo "")

EOF
)

# 推送 Telegram
curl -fsS "https://api.telegram.org/bot${TG_TOKEN}/sendMessage" \
    -d "chat_id=${TG_CHAT}" \
    -d "text=${REPORT}" \
    -d "parse_mode=Markdown" >/dev/null

# 邮件（可选）
if [[ -n "${SMTP_HOST:-}" ]]; then
    echo "$REPORT" | mail -s "AITransfer 早报 ${YESTERDAY}" "${REPORT_EMAIL:-ops@example.com}"
fi

echo "[+] 早报已推送"
