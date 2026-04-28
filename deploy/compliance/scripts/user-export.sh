#!/usr/bin/env bash
# 导出用户全部数据（GDPR access right）
# 用法：bash user-export.sh <username|email|userid>
set -euo pipefail
cd "$(dirname "$0")/../.."
if [[ -f .env ]]; then set -a; source .env; set +a; fi
: "${PG_USER:?}" "${PG_DB:?}" "${PG_PASSWORD:?}" "${PG_LOG_DB:?}" "${BACKUP_ENCRYPTION_PASSWORD:?}"
PG_CONTAINER="new-api-postgres"

[[ $# -ne 1 ]] && { echo "用法: $0 <username|email|userid>"; exit 1; }
TARGET="$1"

run() { docker exec -e PGPASSWORD="$PG_PASSWORD" "$PG_CONTAINER" psql -U "$PG_USER" "$@"; }

USER_ID=$(run -d "$PG_DB" -A -t -c "
SELECT id FROM users WHERE id::text = '${TARGET}' OR username = '${TARGET}' OR email = '${TARGET}' LIMIT 1;
" | tr -d ' ')

[[ -z "$USER_ID" ]] && { echo "[!] 没找到用户"; exit 1; }

WORKDIR=$(mktemp -d)
echo "[*] 导出用户 #${USER_ID}..."

run -d "$PG_DB" -c "\COPY (SELECT * FROM users WHERE id = ${USER_ID}) TO STDOUT WITH CSV HEADER" > "$WORKDIR/profile.csv"
run -d "$PG_DB" -c "\COPY (SELECT id,name,group_id,created_time,expired_time,used_quota,remain_quota FROM tokens WHERE user_id = ${USER_ID}) TO STDOUT WITH CSV HEADER" > "$WORKDIR/tokens.csv"
run -d "$PG_DB" -c "\COPY (SELECT * FROM topups WHERE user_id = ${USER_ID}) TO STDOUT WITH CSV HEADER" > "$WORKDIR/topups.csv" 2>/dev/null || true
run -d "$PG_DB" -c "\COPY (SELECT * FROM redemptions WHERE used_user_id = ${USER_ID}) TO STDOUT WITH CSV HEADER" > "$WORKDIR/redemptions.csv" 2>/dev/null || true
run -d "$PG_LOG_DB" -c "\COPY (SELECT created_at,model_name,channel_id,prompt_tokens,completion_tokens,quota,ip FROM logs WHERE user_id = ${USER_ID} ORDER BY created_at DESC LIMIT 100000) TO STDOUT WITH CSV HEADER" > "$WORKDIR/api-logs.csv"

cat > "$WORKDIR/README.txt" <<EOF
您的数据导出包
导出时间: $(date -u +%Y-%m-%dT%H:%M:%SZ)
用户 ID: ${USER_ID}

包含：
- profile.csv：账号信息
- tokens.csv：API Token 列表（不含密钥本身）
- topups.csv：充值记录
- redemptions.csv：兑换码使用
- api-logs.csv：API 调用记录（仅元数据，不含 prompt/response 内容）

我们不存储您的 prompt / response 内容（ChatGPT 兼容接口的请求体）。
EOF

OUT="compliance/cases/user-${USER_ID}-export-$(date +%Y%m%d-%H%M%S).tar.gz.enc"
mkdir -p "$(dirname "$OUT")"
tar -czf - -C "$WORKDIR" . \
	| openssl enc -aes-256-cbc -salt -pbkdf2 -pass "pass:${BACKUP_ENCRYPTION_PASSWORD}" \
	> "$OUT"
rm -rf "$WORKDIR"

echo "[+] 导出完成: $OUT"
echo "[*] 解密：openssl enc -d -aes-256-cbc -pbkdf2 -pass pass:\$PWD -in $OUT | tar -xz"
echo "[*] 通过受信任的渠道发给用户（邮件附密码 hint，或加密通道）"
