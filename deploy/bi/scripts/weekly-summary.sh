#!/usr/bin/env bash
# 周报：本周与上周对比、Top 用户、Top 模型、号池消耗
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SQL_DIR="${SCRIPT_DIR}/../sql"

PG_DSN="${BI_PG_DSN:?需要 BI_PG_DSN}"
TG_TOKEN="${TELEGRAM_BOT_TOKEN}"
TG_CHAT="${TELEGRAM_BIZ_CHAT_ID}"

WEEK_END=$(date -d 'sunday' +%Y-%m-%d 2>/dev/null || date -v-Sun +%Y-%m-%d)
WEEK_START=$(date -d "$WEEK_END - 7 days" +%Y-%m-%d 2>/dev/null || date -v-7d +%Y-%m-%d)

# Top 5 用户
TOP_USERS=$(psql "$PG_DSN" -At -F'|' -f "${SQL_DIR}/top-users.sql" | head -5)

# Top 5 模型（按毛利）
TOP_MODELS=$(psql "$PG_DSN" -At -F'|' -f "${SQL_DIR}/profit-by-model.sql" | head -5)

# 渠道分组成本
GROUP_COST=$(psql "$PG_DSN" -At -F'|' -f "${SQL_DIR}/upstream-cost.sql")

# 留存
RETENTION=$(psql "$PG_DSN" -At -F'|' -f "${SQL_DIR}/cohort-retention.sql" | head -3)

# 缓存节省
CACHE=$(psql "$PG_DSN" -At -F'|' -f "${SQL_DIR}/cache-savings.sql" | tail -7)
CACHE_SAVED=$(echo "$CACHE" | awk -F'|' 'BEGIN{s=0}{s+=$NF}END{printf "%.2f", s}')

REPORT=$(cat <<EOF
📈 *AITransfer 周报 ${WEEK_START} ~ ${WEEK_END}*
━━━━━━━━━━━━━━━━━━━━━━

🏆 *Top 5 用户*
$(echo "$TOP_USERS" | awk -F'|' '{printf "   %d. %s  $%.2f\n", NR, $2, $7}')

💎 *Top 5 模型*（按毛利）
$(echo "$TOP_MODELS" | awk -F'|' '{printf "   %d. %s  毛利 $%.2f (%.1f%%)\n", NR, $1, $7, $8}')

🏊 *号池成本*
$(echo "$GROUP_COST" | awk -F'|' '{printf "   %s  营收 $%.2f / 成本 $%.2f / 毛利 %.1f%%\n", $1, $4, $5, $7}')

🎯 *用户留存*
$(echo "$RETENTION" | awk -F'|' '{printf "   %s 注册 %s 人  W1=%s%% W4=%s%%\n", $1, $2, $9, $10}')

💾 *缓存节省*  本周节省 \$${CACHE_SAVED}
EOF
)

curl -fsS "https://api.telegram.org/bot${TG_TOKEN}/sendMessage" \
    -d "chat_id=${TG_CHAT}" \
    -d "text=${REPORT}" \
    -d "parse_mode=Markdown" >/dev/null

echo "[+] 周报已推送"
