#!/usr/bin/env bash
# 渠道巡检脚本：cron 每 10 分钟跑一次
# 1. 调 /api/channel/test/{id} 测活全部启用渠道
# 2. 把"已禁用 > 24h"的告警出来
# 3. 把"持续失败"的渠道发 Telegram 告警
#
# 加进 crontab：
#   */10 * * * * cd /path/to/deploy && bash scripts/channel-healthcheck.sh >> logs/healthcheck.log 2>&1

set -euo pipefail

cd "$(dirname "$0")/.."

if [[ -f .env ]]; then
	set -a
	# shellcheck disable=SC1091
	source .env
	set +a
fi

: "${ADMIN_API_TOKEN:?需要 ADMIN_API_TOKEN}"
API_BASE="${API_BASE:-http://127.0.0.1:3000}"

log() { echo "[$(date '+%F %T')] $*"; }

notify() {
	local msg="$1"
	if [[ -n "${TG_BOT_TOKEN:-}" ]] && [[ -n "${TG_CHAT_ID:-}" ]]; then
		curl -fsS --max-time 10 -o /dev/null \
			-d "chat_id=${TG_CHAT_ID}" \
			-d "text=[健康巡检] ${msg}" \
			"https://api.telegram.org/bot${TG_BOT_TOKEN}/sendMessage" || true
	fi
}

# ─── 1. 拿启用中的渠道列表 ───
log "拉取渠道列表"
CHANNELS=$(curl -fsS "${API_BASE}/api/channel/?p=0&page_size=500" \
	-H "Authorization: Bearer ${ADMIN_API_TOKEN}" \
	| jq -c '.data[]? | select(.status == 1)')

if [[ -z "$CHANNELS" ]]; then
	log "没拿到启用渠道，退出"
	exit 0
fi

# ─── 2. 逐个测试 ───
FAILED_LIST=""
TESTED=0

while IFS= read -r ch; do
	CHID=$(echo "$ch" | jq -r '.id')
	CHNAME=$(echo "$ch" | jq -r '.name')
	CHGROUP=$(echo "$ch" | jq -r '."group" // "default"')

	TEST=$(curl -fsS --max-time 30 "${API_BASE}/api/channel/test/${CHID}" \
		-H "Authorization: Bearer ${ADMIN_API_TOKEN}" 2>/dev/null || echo '{"success":false,"message":"timeout"}')
	OK=$(echo "$TEST" | jq -r '.success')

	if [[ "$OK" != "true" ]]; then
		MSG=$(echo "$TEST" | jq -r '.message // "unknown"')
		log "  ✗ [${CHGROUP}] #${CHID} ${CHNAME}: ${MSG}"
		FAILED_LIST="${FAILED_LIST}\n• [${CHGROUP}] #${CHID} ${CHNAME}: ${MSG}"
	fi
	TESTED=$((TESTED + 1))
done <<< "$CHANNELS"

log "测试完成：${TESTED} 个，失败 $(echo -e "$FAILED_LIST" | grep -c '•' || true)"

# ─── 3. 大批失败告警 ───
FAIL_COUNT=$(echo -e "$FAILED_LIST" | grep -c '•' || true)
if [[ "$FAIL_COUNT" -ge 3 ]]; then
	notify "⚠️ 多渠道异常 (${FAIL_COUNT}/${TESTED})$(echo -e "$FAILED_LIST" | head -10)"
fi

# ─── 4. 长期禁用渠道告警 ───
DISABLED_LONG=$(curl -fsS "${API_BASE}/api/channel/?p=0&page_size=500" \
	-H "Authorization: Bearer ${ADMIN_API_TOKEN}" \
	| jq -c '.data[]? | select(.status == 2 and (.created_time // 0) < (now - 86400))' \
	| wc -l)

if [[ "$DISABLED_LONG" -gt 0 ]]; then
	log "⚠️ 已禁用 > 24h 的渠道: ${DISABLED_LONG} 个，请人工复核"
	# 频率低，每天提醒一次足够，不用通知
fi

log "全部完成"
