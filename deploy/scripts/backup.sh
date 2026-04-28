#!/usr/bin/env bash
# 数据库每日备份脚本
# 推荐放进 crontab：
#   0 3 * * * /path/to/deploy/scripts/backup.sh >> /path/to/deploy/logs/backup.log 2>&1
#
# 流程：pg_dump → gzip → openssl AES256 加密 → 保存 ./backups/ → 远程同步 → 清理过期 → 告警
#
# 恢复用 scripts/restore.sh

set -euo pipefail

cd "$(dirname "$0")/.."

# 加载 .env
if [[ -f .env ]]; then
	set -a
	# shellcheck disable=SC1091
	source .env
	set +a
else
	echo "[!] .env 不存在，无法备份" >&2
	exit 1
fi

: "${PG_USER:?PG_USER 未设置}"
: "${PG_DB:?PG_DB 未设置}"
: "${PG_LOG_DB:?PG_LOG_DB 未设置}"
: "${BACKUP_ENCRYPTION_PASSWORD:?BACKUP_ENCRYPTION_PASSWORD 未设置}"

RETENTION_DAYS=${BACKUP_RETENTION_DAYS:-30}
BACKUP_DIR="./backups"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
PG_CONTAINER="new-api-postgres"

mkdir -p "$BACKUP_DIR"

log() { echo "[$(date '+%F %T')] $*"; }

notify() {
	local msg="$1"
	if [[ -n "${TG_BOT_TOKEN:-}" ]] && [[ -n "${TG_CHAT_ID:-}" ]]; then
		curl -fsS --max-time 10 -o /dev/null \
			-d "chat_id=${TG_CHAT_ID}" \
			-d "text=[backup] ${msg}" \
			"https://api.telegram.org/bot${TG_BOT_TOKEN}/sendMessage" || true
	fi
}

backup_db() {
	local db="$1"
	local out="${BACKUP_DIR}/${db}-${TIMESTAMP}.sql.gz.enc"
	log "备份 ${db} -> ${out}"

	# pg_dump 通过容器，避免本机要装 postgres-client
	docker exec -e PGPASSWORD="$PG_PASSWORD" "$PG_CONTAINER" \
		pg_dump -U "$PG_USER" -d "$db" --no-owner --no-privileges \
		| gzip -9 \
		| openssl enc -aes-256-cbc -salt -pbkdf2 -pass "pass:${BACKUP_ENCRYPTION_PASSWORD}" \
		> "$out"

	local size
	size=$(du -h "$out" | cut -f1)
	log "  完成 (${size})"
}

# ─── 1. 备份主库 + 日志库 ───
backup_db "$PG_DB"
backup_db "$PG_LOG_DB"

# ─── 2. 同时备份 new-api data/ 目录（含 SQLite 模式时的 db、上传文件等）───
DATA_BACKUP="${BACKUP_DIR}/data-${TIMESTAMP}.tar.gz.enc"
log "备份 data/ -> ${DATA_BACKUP}"
tar -czf - -C . data 2>/dev/null \
	| openssl enc -aes-256-cbc -salt -pbkdf2 -pass "pass:${BACKUP_ENCRYPTION_PASSWORD}" \
	> "$DATA_BACKUP"
log "  完成 ($(du -h "$DATA_BACKUP" | cut -f1))"

# ─── 3. 远程同步（可选）───
if [[ -n "${RCLONE_REMOTE:-}" ]] && command -v rclone >/dev/null 2>&1; then
	log "rclone 同步到 ${RCLONE_REMOTE}:${RCLONE_PATH}"
	rclone copy "$BACKUP_DIR" "${RCLONE_REMOTE}:${RCLONE_PATH}" \
		--include "*-${TIMESTAMP}.*" \
		--transfers 4 --checkers 8
	log "  rclone 完成"
fi

# ─── 4. 清理过期备份 ───
log "清理 ${RETENTION_DAYS} 天前的本地备份"
find "$BACKUP_DIR" -name "*.enc" -mtime +"${RETENTION_DAYS}" -delete

# ─── 5. 通知 ───
TOTAL_SIZE=$(du -sh "$BACKUP_DIR" | cut -f1)
log "本地备份目录占用: ${TOTAL_SIZE}"
notify "✅ 备份成功 ${TIMESTAMP}, 总大小 ${TOTAL_SIZE}"
log "全部完成"
