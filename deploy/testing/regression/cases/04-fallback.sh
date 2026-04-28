#!/usr/bin/env bash
# 阶梯回退：禁用一个分组，请求应自动落到下一个分组
set -euo pipefail

BASE="${TEST_BASE_URL}"
KEY="${TEST_API_KEY}"
ADMIN="${ADMIN_TOKEN}"

# 1. 临时禁用 official 分组里所有渠道（模拟全挂）
CHANNELS=$(curl -fsS -H "Authorization: Bearer ${ADMIN}" "${BASE}/api/channel/?p=0&pagesize=200" \
    | jq -r '.data[] | select(.group | contains("official")) | .id')

for id in $CHANNELS; do
    curl -fsS -X POST -H "Authorization: Bearer ${ADMIN}" "${BASE}/api/channel/disabled/${id}" >/dev/null
done

# 2. 请求 gpt-4o（应该回退到下一分组的等效模型）
RESP=$(curl -fsS -D /tmp/h.txt "${BASE}/v1/chat/completions" \
    -H "Authorization: Bearer ${KEY}" \
    -H "Content-Type: application/json" \
    -d '{"model":"gpt-4o-mini","messages":[{"role":"user","content":"hi"}]}')

GROUP=$(grep -i "x-channel-group" /tmp/h.txt | awk '{print $2}' | tr -d '\r')
echo "fallback group: $GROUP"

# 3. 验证不是 official
[[ "$GROUP" != "official" ]] || { echo "FAIL: 没有回退"; exit 1; }

# 4. 恢复
for id in $CHANNELS; do
    curl -fsS -X POST -H "Authorization: Bearer ${ADMIN}" "${BASE}/api/channel/enable/${id}" >/dev/null
done

echo "PASS (fallback to $GROUP)"
