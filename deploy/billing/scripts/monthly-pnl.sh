#!/usr/bin/env bash
# 月度毛利报表：用户消耗 - 上游成本估算 = 毛利
# 用法：bash monthly-pnl.sh 2026-04
set -euo pipefail
cd "$(dirname "$0")/../.."
if [[ -f .env ]]; then set -a; source .env; set +a; fi
: "${PG_USER:?}" "${PG_DB:?}" "${PG_PASSWORD:?}" "${PG_LOG_DB:?}"
PG_CONTAINER="new-api-postgres"

MONTH="${1:-$(date +%Y-%m)}"
START="${MONTH}-01"
END=$(date -d "${START} +1 month" +%Y-%m-%d 2>/dev/null || gdate -d "${START} +1 month" +%Y-%m-%d)
OUT="billing/reports/pnl-${MONTH}.csv"
mkdir -p "$(dirname "$OUT")"

echo "[*] 拉取 ${START} 到 ${END} 的消耗数据..."

docker exec -e PGPASSWORD="$PG_PASSWORD" "$PG_CONTAINER" \
	psql -U "$PG_USER" -d "$PG_LOG_DB" -A -F, --csv -c "
WITH monthly AS (
  SELECT
    model_name,
    \"group\" AS user_group,
    SUM(prompt_tokens) AS prompt_tk,
    SUM(completion_tokens) AS completion_tk,
    SUM(quota) AS revenue_quota,
    COUNT(*) AS req_count
  FROM logs
  WHERE created_at >= '${START}' AND created_at < '${END}' AND type = 2
  GROUP BY model_name, \"group\"
)
SELECT
  model_name,
  user_group,
  req_count,
  prompt_tk,
  completion_tk,
  ROUND(revenue_quota / 500000.0, 2) AS revenue_usd,
  ROUND(revenue_quota / 500000.0 / NULLIF(req_count, 0), 4) AS arpu_per_req
FROM monthly
ORDER BY revenue_quota DESC;
" > "$OUT"

echo "[+] 输出: $OUT"
echo ""
echo "汇总："
docker exec -e PGPASSWORD="$PG_PASSWORD" "$PG_CONTAINER" \
	psql -U "$PG_USER" -d "$PG_LOG_DB" -c "
SELECT
  COUNT(*) AS total_requests,
  SUM(prompt_tokens + completion_tokens) AS total_tokens,
  ROUND(SUM(quota) / 500000.0, 2) AS revenue_usd
FROM logs
WHERE created_at >= '${START}' AND created_at < '${END}' AND type = 2;
"

echo ""
echo "⚠️  毛利 = 这个 revenue_usd - 上游真实成本（要从各上游账单导出）"
echo "   official 分组：从 OpenAI/Anthropic/Google 后台导账单"
echo "   claude-oauth：按订阅费 / 月活号数估算"
echo "   gemini-free / 第三方：自行估算"
