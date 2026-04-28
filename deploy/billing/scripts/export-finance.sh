#!/usr/bin/env bash
# 财务/审计导出包：充值流水 + 消耗流水 + 兑换码使用 + 用户余额
# 按月归档，输出加密 ZIP（密码用 BACKUP_ENCRYPTION_PASSWORD）
set -euo pipefail
cd "$(dirname "$0")/../.."
if [[ -f .env ]]; then set -a; source .env; set +a; fi
: "${PG_USER:?}" "${PG_DB:?}" "${PG_PASSWORD:?}" "${PG_LOG_DB:?}"
: "${BACKUP_ENCRYPTION_PASSWORD:?}"
PG_CONTAINER="new-api-postgres"

MONTH="${1:-$(date -d 'last month' +%Y-%m 2>/dev/null || gdate -d 'last month' +%Y-%m)}"
START="${MONTH}-01"
END=$(date -d "${START} +1 month" +%Y-%m-%d 2>/dev/null || gdate -d "${START} +1 month" +%Y-%m-%d)

WORKDIR="billing/reports/finance-${MONTH}"
mkdir -p "$WORKDIR"

run() {
	docker exec -e PGPASSWORD="$PG_PASSWORD" "$PG_CONTAINER" \
		psql -U "$PG_USER" -d "$1" -A -F, --csv -c "$2"
}

# 1. 用户消耗（含模型/渠道维度）
run "$PG_LOG_DB" "
SELECT created_at, user_id, username, channel_id, model_name, prompt_tokens, completion_tokens, quota, ip
FROM logs
WHERE type = 2 AND created_at >= '${START}' AND created_at < '${END}'
ORDER BY created_at;
" > "$WORKDIR/consumption.csv"

# 2. 充值流水
run "$PG_DB" "
SELECT created_time, user_id, payment_method, amount, quota, status, trade_no
FROM topups
WHERE created_time >= EXTRACT(EPOCH FROM TIMESTAMP '${START}')
  AND created_time < EXTRACT(EPOCH FROM TIMESTAMP '${END}')
ORDER BY created_time;
" > "$WORKDIR/topups.csv" 2>/dev/null || echo "[skip] topups 表不存在"

# 3. 兑换码使用
run "$PG_DB" "
SELECT created_time, redeemed_time, user_id, name, key, quota, status
FROM redemptions
WHERE redeemed_time >= EXTRACT(EPOCH FROM TIMESTAMP '${START}')
  AND redeemed_time < EXTRACT(EPOCH FROM TIMESTAMP '${END}')
ORDER BY redeemed_time;
" > "$WORKDIR/redemptions.csv" 2>/dev/null || echo "[skip] redemptions 表不存在"

# 4. 期末用户余额快照
run "$PG_DB" "
SELECT id, username, email, \"group\", quota, used_quota, request_count
FROM users
WHERE quota > 0 OR used_quota > 0
ORDER BY used_quota DESC;
" > "$WORKDIR/users-snapshot.csv"

# 5. 打包 + 加密
ARCHIVE="billing/reports/finance-${MONTH}.tar.gz.enc"
tar -czf - -C billing/reports "finance-${MONTH}" \
	| openssl enc -aes-256-cbc -salt -pbkdf2 -pass "pass:${BACKUP_ENCRYPTION_PASSWORD}" \
	> "$ARCHIVE"

rm -rf "$WORKDIR"
echo "[+] 输出: $ARCHIVE"
echo "[*] 解密: openssl enc -d -aes-256-cbc -pbkdf2 -pass pass:\$PWD -in $ARCHIVE | tar -xz"
