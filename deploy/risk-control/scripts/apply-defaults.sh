#!/usr/bin/env bash
# 把 limits.json 推到 new-api options 表
set -euo pipefail
cd "$(dirname "$0")/../.."
if [[ -f .env ]]; then set -a; source .env; set +a; fi
: "${PG_USER:?}" "${PG_DB:?}" "${PG_PASSWORD:?}"
PG_CONTAINER="new-api-postgres"

SRC="${1:-risk-control/limits.json}"
[[ -f "$SRC" ]] || { echo "[!] $SRC 不存在"; exit 1; }
command -v jq >/dev/null || { echo "[!] 需要 jq"; exit 1; }

run_sql() {
	docker exec -e PGPASSWORD="$PG_PASSWORD" "$PG_CONTAINER" \
		psql -U "$PG_USER" -d "$PG_DB" -v ON_ERROR_STOP=1 "$@"
}

upsert() {
	local k="$1" v="$2"
	v=${v//\'/\'\'}
	run_sql -c "INSERT INTO options(key,value) VALUES('${k}','${v}') ON CONFLICT(key) DO UPDATE SET value=EXCLUDED.value;"
	echo "[+] $k = $v"
}

echo "[*] 应用全局风控配置..."
jq -r '.global | to_entries[] | select(.key | startswith("_") | not) | "\(.key)\t\(.value)"' "$SRC" \
	| while IFS=$'\t' read -r k v; do
		upsert "$k" "$v"
	done

echo ""
echo "[+] 完成。其它项（用户分组日上限、模型白名单）需要在 channel/token 创建时单独应用，"
echo "    或在 admin 后台批量改。new-api 大部分按 token/user 维度设置，没有全局默认 API。"
