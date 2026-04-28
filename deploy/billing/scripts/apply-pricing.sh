#!/usr/bin/env bash
# 把 pricing.json 推到 new-api 系统设置（model_ratio / completion_ratio / group_ratio）
# 直接写 options 表（new-api 没有完整 ratio CRUD API）
set -euo pipefail
cd "$(dirname "$0")/../.."

if [[ -f .env ]]; then set -a; source .env; set +a; fi
: "${PG_USER:?}" "${PG_DB:?}" "${PG_PASSWORD:?}"
PG_CONTAINER="new-api-postgres"

SRC="${1:-billing/pricing.json}"
[[ -f "$SRC" ]] || { echo "[!] $SRC 不存在"; exit 1; }

# 剥离 _comment 字段
JQ=$(command -v jq) || { echo "[!] 需要 jq"; exit 1; }
CLEAN=$($JQ 'walk(if type=="object" then with_entries(select(.key | startswith("_") | not)) else . end)' "$SRC")

run_sql() {
	docker exec -e PGPASSWORD="$PG_PASSWORD" "$PG_CONTAINER" \
		psql -U "$PG_USER" -d "$PG_DB" -v ON_ERROR_STOP=1 "$@"
}

upsert_option() {
	local key="$1"
	local value="$2"
	# 转义单引号
	value=${value//\'/\'\'}
	run_sql -c "
	INSERT INTO options (key, value) VALUES ('${key}', '${value}')
	ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value;
	"
}

echo "[*] 推送 ModelRatio / CompletionRatio / GroupRatio"

MODEL=$(echo "$CLEAN" | jq -c '.model_ratios')
COMPLETION=$(echo "$CLEAN" | jq -c '.completion_ratios')
GROUP=$(echo "$CLEAN" | jq -c '.group_ratios')

upsert_option ModelRatio "$MODEL"
upsert_option CompletionRatio "$COMPLETION"
upsert_option GroupRatio "$GROUP"

echo "[+] 完成。new-api 自动同步周期最长 60s（CHANNEL_UPDATE_FREQUENCY），或手动重启实例立即生效。"
