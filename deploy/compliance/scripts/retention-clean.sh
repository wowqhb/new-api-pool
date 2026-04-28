#!/usr/bin/env bash
# 数据保留期清理 cron
# 用法：bash retention-clean.sh <task>
#   task: logs | ip-anonymize | backups | deleted-users | all
set -euo pipefail
cd "$(dirname "$0")/../.."
if [[ -f .env ]]; then set -a; source .env; set +a; fi
: "${PG_USER:?}" "${PG_DB:?}" "${PG_PASSWORD:?}" "${PG_LOG_DB:?}"
PG_CONTAINER="new-api-postgres"

run() { docker exec -e PGPASSWORD="$PG_PASSWORD" "$PG_CONTAINER" psql -U "$PG_USER" "$@"; }

clean_logs() {
	echo "[*] 清理 90 天前的 API 调用日志..."
	run -d "$PG_LOG_DB" -c "DELETE FROM logs WHERE created_at < NOW() - INTERVAL '90 days';"
}

anonymize_ip() {
	echo "[*] 90 天前的 IP 模糊化为 /24..."
	run -d "$PG_LOG_DB" -c "
	UPDATE logs SET ip = regexp_replace(ip, '\.\d+$', '.0/24')
	WHERE created_at < NOW() - INTERVAL '90 days' AND ip IS NOT NULL AND ip NOT LIKE '%/%';
	"
}

clean_backups() {
	echo "[*] 清理 30 天前的每日备份（月度归档保留）..."
	BACKUP_DIR="${BACKUP_DIR:-/var/backups/new-api}"
	if [[ -d "$BACKUP_DIR" ]]; then
		find "$BACKUP_DIR" -name "daily-*.tar.gz.enc" -mtime +30 -delete -print
		# 月度归档保留 5 年
		find "$BACKUP_DIR" -name "monthly-*.tar.gz.enc" -mtime +1830 -delete -print
	else
		echo "[!] $BACKUP_DIR 不存在，跳过"
	fi
}

clean_deleted_users() {
	echo "[*] 软删除满 30 天的用户硬删除（保留财务关联）..."
	run -d "$PG_DB" -c "
	UPDATE users SET
		username = 'deleted_' || id,
		email = 'deleted_' || id || '@example.invalid',
		display_name = '已注销',
		github_id = NULL,
		wechat_id = NULL
	WHERE status = 99
	  AND (deleted_at IS NULL OR deleted_at < NOW() - INTERVAL '30 days')
	  AND username NOT LIKE 'deleted_%';
	DELETE FROM tokens WHERE user_id IN (
		SELECT id FROM users WHERE status = 99 AND username LIKE 'deleted_%'
	);
	"
}

case "${1:-all}" in
	logs)             clean_logs ;;
	ip-anonymize)     anonymize_ip ;;
	backups)          clean_backups ;;
	deleted-users)    clean_deleted_users ;;
	all)
		clean_logs
		anonymize_ip
		clean_backups
		clean_deleted_users
		;;
	*) echo "用法: $0 {logs|ip-anonymize|backups|deleted-users|all}"; exit 1 ;;
esac

echo "[+] 完成"
