#!/usr/bin/env bash
# 容量预警检查（每周跑一次或日 cron）
set -euo pipefail
cd "$(dirname "$0")/../.."
if [[ -f .env ]]; then set -a; source .env; set +a; fi
: "${PG_USER:?}" "${PG_DB:?}" "${PG_PASSWORD:?}" "${PG_LOG_DB:?}"
PG_CONTAINER="new-api-postgres"

run() {
	docker exec -e PGPASSWORD="$PG_PASSWORD" "$PG_CONTAINER" \
		psql -U "$PG_USER" "$@"
}

echo "=================================="
echo " 号池容量报告  $(date '+%Y-%m-%d %H:%M')"
echo "=================================="

echo ""
echo "## 各分组渠道状态"
run -d "$PG_DB" -c '
SELECT
  "group" AS channel_group,
  COUNT(*) FILTER (WHERE status = 1) AS active,
  COUNT(*) FILTER (WHERE status = 2) AS auto_disabled,
  COUNT(*) FILTER (WHERE status = 3) AS manual_disabled,
  COUNT(*) AS total,
  ROUND(100.0 * COUNT(*) FILTER (WHERE status = 1) / NULLIF(COUNT(*), 0), 1) AS active_pct
FROM channels
WHERE "group" IS NOT NULL
GROUP BY "group"
ORDER BY active DESC;
'

echo ""
echo "## 7 天峰值 QPS"
run -d "$PG_LOG_DB" -c "
SELECT
  date_trunc('hour', created_at) AS hour,
  COUNT(*) AS reqs,
  ROUND(COUNT(*)::numeric / 3600, 1) AS qps
FROM logs
WHERE created_at > NOW() - INTERVAL '7 days' AND type = 2
GROUP BY 1
ORDER BY reqs DESC
LIMIT 5;
"

echo ""
echo "## 各分组本周失败率"
run -d "$PG_LOG_DB" -c "
SELECT
  \"group\",
  COUNT(*) AS total,
  COUNT(*) FILTER (WHERE type = 5) AS errors,
  ROUND(100.0 * COUNT(*) FILTER (WHERE type = 5) / NULLIF(COUNT(*), 0), 2) AS err_pct
FROM logs
WHERE created_at > NOW() - INTERVAL '7 days'
GROUP BY \"group\"
ORDER BY err_pct DESC;
"

echo ""
echo "## 红黄绿信号"
RESULT=$(run -d "$PG_DB" -A -t -c '
SELECT
  CASE
    WHEN MIN(active_count) < 5 THEN '"'"'🔴 RED'"'"'
    WHEN MIN(active_count) < 15 THEN '"'"'🟡 YELLOW'"'"'
    ELSE '"'"'🟢 GREEN'"'"'
  END
FROM (
  SELECT "group", COUNT(*) FILTER (WHERE status = 1) AS active_count
  FROM channels WHERE "group" IS NOT NULL GROUP BY "group"
) t;
' | tr -d ' ')
echo "  状态: $RESULT"
echo ""
echo "  补号建议（按半衰期）："
echo "   - Gemini Free: 周补 60% 当前在用量"
echo "   - Claude OAuth: 月补 25%"
echo "   - 第三方: 月补 40%"
