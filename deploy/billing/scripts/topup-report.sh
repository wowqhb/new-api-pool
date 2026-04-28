#!/usr/bin/env bash
# 充值流水报表
set -euo pipefail
cd "$(dirname "$0")/../.."
if [[ -f .env ]]; then set -a; source .env; set +a; fi
: "${PG_USER:?}" "${PG_DB:?}" "${PG_PASSWORD:?}"
PG_CONTAINER="new-api-postgres"

MONTH="${1:-$(date +%Y-%m)}"
START="${MONTH}-01"
END=$(date -d "${START} +1 month" +%Y-%m-%d 2>/dev/null || gdate -d "${START} +1 month" +%Y-%m-%d)
OUT="billing/reports/topup-${MONTH}.csv"
mkdir -p "$(dirname "$OUT")"

docker exec -e PGPASSWORD="$PG_PASSWORD" "$PG_CONTAINER" \
	psql -U "$PG_USER" -d "$PG_DB" -A -F, --csv -c "
SELECT
  date_trunc('day', to_timestamp(created_time)) AS day,
  payment_method,
  status,
  COUNT(*) AS orders,
  SUM(amount) AS amount_total,
  SUM(quota) AS quota_total
FROM topups
WHERE created_time >= EXTRACT(EPOCH FROM TIMESTAMP '${START}')
  AND created_time < EXTRACT(EPOCH FROM TIMESTAMP '${END}')
GROUP BY 1, 2, 3
ORDER BY 1, 2;
" > "$OUT" 2>/dev/null || {
	echo "[!] 充值表名可能是 redemptions 或 topup，请检查 schema"
	docker exec -e PGPASSWORD="$PG_PASSWORD" "$PG_CONTAINER" \
		psql -U "$PG_USER" -d "$PG_DB" -c "\dt" | head -30
}

echo "[+] 输出: $OUT"
