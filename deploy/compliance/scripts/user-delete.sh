#!/usr/bin/env bash
# 删除用户（GDPR right to erasure）
# 默认软删除（30天后由 retention-clean.sh hard-delete）
# 用法：bash user-delete.sh <user> [--soft|--hard]
set -euo pipefail
cd "$(dirname "$0")/../.."
if [[ -f .env ]]; then set -a; source .env; set +a; fi
: "${PG_USER:?}" "${PG_DB:?}" "${PG_PASSWORD:?}"
PG_CONTAINER="new-api-postgres"

[[ $# -lt 1 ]] && { echo "用法: $0 <user> [--soft|--hard]"; exit 1; }
TARGET="$1"
MODE="${2:---soft}"

run() { docker exec -e PGPASSWORD="$PG_PASSWORD" "$PG_CONTAINER" psql -U "$PG_USER" -d "$PG_DB" -v ON_ERROR_STOP=1 "$@"; }

USER_ID=$(run -A -t -c "
SELECT id FROM users WHERE id::text = '${TARGET}' OR username = '${TARGET}' OR email = '${TARGET}' LIMIT 1;
" | tr -d ' ')
[[ -z "$USER_ID" ]] && { echo "[!] 没找到用户"; exit 1; }

CURRENT=$(run -A -t -c "SELECT username, email, status FROM users WHERE id = ${USER_ID};")
echo "找到用户: ${CURRENT}"
echo ""

if [[ "$MODE" == "--soft" ]]; then
	echo "[*] 软删除（30 天后自动 hard-delete）..."
	run -c "
	UPDATE users SET status = 99, deleted_at = NOW() WHERE id = ${USER_ID};
	UPDATE tokens SET status = 3 WHERE user_id = ${USER_ID};
	" 2>/dev/null || run -c "
	UPDATE users SET status = 99 WHERE id = ${USER_ID};
	UPDATE tokens SET status = 3 WHERE user_id = ${USER_ID};
	"
	echo "[+] 用户 #${USER_ID} 已软删除，30 天后由 cron 硬删"
elif [[ "$MODE" == "--hard" ]]; then
	echo "[!] 硬删除：把个人信息匿名化，财务记录保留（合规要求）"
	read -p "确认？(yes 继续) " C
	[[ "$C" == "yes" ]] || exit 0
	run -c "
	UPDATE users SET
		username = 'deleted_${USER_ID}',
		email = 'deleted_${USER_ID}@example.invalid',
		display_name = '已注销',
		github_id = NULL,
		wechat_id = NULL,
		status = 99
	WHERE id = ${USER_ID};
	DELETE FROM tokens WHERE user_id = ${USER_ID};
	"
	echo "[+] 用户 #${USER_ID} 已硬删除（财务记录保留并匿名化关联）"
else
	echo "[!] 未知模式 $MODE"
	exit 1
fi
