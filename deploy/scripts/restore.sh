#!/usr/bin/env bash
# 数据库恢复脚本（演练 + 应急共用）
# 用法：
#   bash scripts/restore.sh                    # 列出所有备份
#   bash scripts/restore.sh <文件> verify      # 解密+恢复到一个临时库验证（默认动作，安全）
#   bash scripts/restore.sh <文件> overwrite   # ⚠️ 覆盖正式库（高危！需要再次确认）

set -euo pipefail

cd "$(dirname "$0")/.."

if [[ -f .env ]]; then
	set -a
	# shellcheck disable=SC1091
	source .env
	set +a
fi

: "${PG_USER:?PG_USER 未设置}"
: "${PG_DB:?PG_DB 未设置}"
: "${PG_PASSWORD:?PG_PASSWORD 未设置}"
: "${BACKUP_ENCRYPTION_PASSWORD:?BACKUP_ENCRYPTION_PASSWORD 未设置}"

BACKUP_DIR="./backups"
PG_CONTAINER="new-api-postgres"

list_backups() {
	echo "可用备份："
	ls -lh "$BACKUP_DIR"/*.enc 2>/dev/null | awk '{print "  ", $9, "(", $5, ",", $6, $7, $8, ")"}'
}

if [[ $# -eq 0 ]]; then
	list_backups
	echo ""
	echo "用法："
	echo "  bash scripts/restore.sh <文件路径> [verify|overwrite]"
	exit 0
fi

FILE="$1"
ACTION="${2:-verify}"

if [[ ! -f "$FILE" ]]; then
	echo "[!] 文件不存在: $FILE" >&2
	exit 1
fi

decrypt() {
	openssl enc -d -aes-256-cbc -pbkdf2 -pass "pass:${BACKUP_ENCRYPTION_PASSWORD}" -in "$FILE" \
		| gunzip
}

case "$ACTION" in
	verify)
		# 创建临时验证库 → 恢复 → 跑几条 SELECT → 删除
		VERIFY_DB="restore_verify_$(date +%s)"
		echo "[*] 在临时库 ${VERIFY_DB} 中验证恢复..."

		docker exec -e PGPASSWORD="$PG_PASSWORD" "$PG_CONTAINER" \
			psql -U "$PG_USER" -d postgres -c "CREATE DATABASE ${VERIFY_DB};"

		decrypt | docker exec -i -e PGPASSWORD="$PG_PASSWORD" "$PG_CONTAINER" \
			psql -U "$PG_USER" -d "$VERIFY_DB" -q

		echo ""
		echo "[*] 恢复完成，跑校验查询："
		docker exec -e PGPASSWORD="$PG_PASSWORD" "$PG_CONTAINER" \
			psql -U "$PG_USER" -d "$VERIFY_DB" -c "
			  SELECT 'channels' AS tbl, count(*) FROM channels
			  UNION ALL SELECT 'users', count(*) FROM users
			  UNION ALL SELECT 'tokens', count(*) FROM tokens;
			" || echo "[!] 校验查询失败，可能是日志库或结构不匹配"

		echo ""
		read -p "[?] 验证库是否保留 (y 保留 / 其它删除): " -n 1 -r KEEP
		echo
		if [[ ! $KEEP =~ ^[Yy]$ ]]; then
			docker exec -e PGPASSWORD="$PG_PASSWORD" "$PG_CONTAINER" \
				psql -U "$PG_USER" -d postgres -c "DROP DATABASE ${VERIFY_DB};"
			echo "[+] 已删除验证库"
		else
			echo "[+] 保留验证库 ${VERIFY_DB}，记得用完手动 drop"
		fi
		;;

	overwrite)
		echo ""
		echo "════════════════════════════════════"
		echo " ⚠️  危险操作：覆盖正式数据库 ${PG_DB}"
		echo "════════════════════════════════════"
		echo " 文件: $FILE"
		echo " 容器: $PG_CONTAINER"
		echo ""
		read -p "请输入数据库名 '${PG_DB}' 确认: " CONFIRM
		if [[ "$CONFIRM" != "$PG_DB" ]]; then
			echo "[!] 取消"
			exit 1
		fi

		echo "[*] 停止 new-api 实例（避免写冲突）..."
		docker stop new-api-1 new-api-2 || true

		echo "[*] 重建数据库..."
		docker exec -e PGPASSWORD="$PG_PASSWORD" "$PG_CONTAINER" \
			psql -U "$PG_USER" -d postgres -c "DROP DATABASE IF EXISTS ${PG_DB};"
		docker exec -e PGPASSWORD="$PG_PASSWORD" "$PG_CONTAINER" \
			psql -U "$PG_USER" -d postgres -c "CREATE DATABASE ${PG_DB};"

		echo "[*] 解密+恢复中..."
		decrypt | docker exec -i -e PGPASSWORD="$PG_PASSWORD" "$PG_CONTAINER" \
			psql -U "$PG_USER" -d "$PG_DB" -q

		echo "[*] 启动 new-api..."
		docker start new-api-1 new-api-2

		echo "[+] 恢复完成"
		;;

	*)
		echo "[!] 未知动作: $ACTION (用 verify 或 overwrite)" >&2
		exit 1
		;;
esac
