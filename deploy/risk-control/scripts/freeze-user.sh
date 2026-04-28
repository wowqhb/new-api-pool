#!/usr/bin/env bash
# 紧急冻结用户：禁用账号 + 禁用所有 token
# 用法：bash freeze-user.sh <username|email|userid>
set -euo pipefail
cd "$(dirname "$0")/../.."
if [[ -f .env ]]; then set -a; source .env; set +a; fi
: "${PG_USER:?}" "${PG_DB:?}" "${PG_PASSWORD:?}"
PG_CONTAINER="new-api-postgres"

[[ $# -ne 1 ]] && { echo "用法: $0 <username|email|userid>"; exit 1; }
TARGET="$1"

run_sql() {
	docker exec -e PGPASSWORD="$PG_PASSWORD" "$PG_CONTAINER" \
		psql -U "$PG_USER" -d "$PG_DB" "$@"
}

# 找用户
USER=$(run_sql -A -F, --csv -c "
SELECT id, username, email, \"group\", quota, used_quota
FROM users
WHERE id::text = '${TARGET}' OR username = '${TARGET}' OR email = '${TARGET}'
LIMIT 5;
")

if [[ -z "$USER" ]] || [[ $(echo "$USER" | wc -l) -le 1 ]]; then
	echo "[!] 没找到用户 ${TARGET}"
	exit 1
fi

echo "$USER"
echo ""
read -p "确认冻结？(yes 继续) " CONFIRM
[[ "$CONFIRM" == "yes" ]] || { echo "取消"; exit 0; }

UID=$(echo "$USER" | tail -1 | cut -d, -f1)

run_sql -c "
UPDATE users SET status = 2 WHERE id = ${UID};
UPDATE tokens SET status = 3 WHERE user_id = ${UID} AND status = 1;
"

echo "[+] 用户 #${UID} 已冻结，所有 token 已禁用"
echo "[*] 解冻：UPDATE users SET status=1 WHERE id=${UID};"
