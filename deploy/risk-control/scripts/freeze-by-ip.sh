#!/usr/bin/env bash
# 按 IP 段冻结所有相关用户/token
# 用法：bash freeze-by-ip.sh 1.2.3.0/24
set -euo pipefail
cd "$(dirname "$0")/../.."
if [[ -f .env ]]; then set -a; source .env; set +a; fi
: "${PG_USER:?}" "${PG_DB:?}" "${PG_PASSWORD:?}" "${PG_LOG_DB:?}"
PG_CONTAINER="new-api-postgres"

[[ $# -ne 1 ]] && { echo "用法: $0 <CIDR>"; exit 1; }
CIDR="$1"

run() {
	docker exec -e PGPASSWORD="$PG_PASSWORD" "$PG_CONTAINER" \
		psql -U "$PG_USER" "$@"
}

echo "[*] 查找在 ${CIDR} 内有过请求的用户..."

USERS=$(run -d "$PG_LOG_DB" -A -F, --csv -c "
SELECT DISTINCT user_id FROM logs
WHERE ip::inet <<= '${CIDR}'::inet
AND created_at > NOW() - INTERVAL '7 days';
")

USER_IDS=$(echo "$USERS" | tail -n +2 | tr '\n' ',' | sed 's/,$//')
[[ -z "$USER_IDS" ]] && { echo "没找到匹配用户"; exit 0; }

echo "受影响用户 ID: $USER_IDS"
echo ""

read -p "确认冻结？(yes 继续) " CONFIRM
[[ "$CONFIRM" == "yes" ]] || { echo "取消"; exit 0; }

run -d "$PG_DB" -c "
UPDATE users SET status = 2 WHERE id IN (${USER_IDS});
UPDATE tokens SET status = 3 WHERE user_id IN (${USER_IDS}) AND status = 1;
"

echo "[+] 已冻结 ${USER_IDS}"
echo "[*] 同时建议在 Cloudflare WAF 加 IP 黑名单 ${CIDR}"
