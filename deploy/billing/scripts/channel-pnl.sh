#!/usr/bin/env bash
# 渠道亏本榜：按渠道分组按模型聚合，看哪个渠道在亏
set -euo pipefail
cd "$(dirname "$0")/../.."
if [[ -f .env ]]; then set -a; source .env; set +a; fi
: "${PG_USER:?}" "${PG_DB:?}" "${PG_PASSWORD:?}" "${PG_LOG_DB:?}"
PG_CONTAINER="new-api-postgres"

DAYS="${1:-30}"
OUT="billing/reports/channel-pnl-$(date +%Y%m%d).csv"
mkdir -p "$(dirname "$OUT")"

docker exec -e PGPASSWORD="$PG_PASSWORD" "$PG_CONTAINER" \
	psql -U "$PG_USER" -d "$PG_LOG_DB" -A -F, --csv -c "
SELECT
  channel_id,
  c.name AS channel_name,
  c.\"group\" AS channel_group,
  l.model_name,
  COUNT(*) AS req_count,
  SUM(l.prompt_tokens) AS prompt_tk,
  SUM(l.completion_tokens) AS completion_tk,
  ROUND(SUM(l.quota) / 500000.0, 2) AS revenue_usd
FROM ${PG_LOG_DB}.public.logs l
LEFT JOIN ${PG_DB}.public.channels c ON c.id = l.channel_id
WHERE l.created_at >= NOW() - INTERVAL '${DAYS} days' AND l.type = 2
GROUP BY channel_id, c.name, c.\"group\", l.model_name
ORDER BY revenue_usd DESC;
" > "$OUT" || {
	echo "[!] 跨库 JOIN 不支持，回退到分两次查"
	docker exec -e PGPASSWORD="$PG_PASSWORD" "$PG_CONTAINER" \
		psql -U "$PG_USER" -d "$PG_LOG_DB" -A -F, --csv -c "
	SELECT
	  channel_id,
	  model_name,
	  COUNT(*) AS req_count,
	  ROUND(SUM(quota) / 500000.0, 2) AS revenue_usd
	FROM logs
	WHERE created_at >= NOW() - INTERVAL '${DAYS} days' AND type = 2
	GROUP BY channel_id, model_name
	ORDER BY revenue_usd DESC;
	" > "$OUT"
}

echo "[+] 输出: $OUT (近 ${DAYS} 天)"
echo "⚠️  对照各渠道实际成本（从上游账单/消耗后台导）→ 标红亏损渠道 → 调整 weight 或下架"
