#!/usr/bin/env bash
# 计费正确性：调用一次后查日志，token_count 与 quota 是否一致
set -euo pipefail

BASE="${TEST_BASE_URL}"
KEY="${TEST_API_KEY}"
ADMIN="${ADMIN_TOKEN:?需要 admin token 查日志}"

# 1. 调一次 chat
RESP=$(curl -fsS "${BASE}/v1/chat/completions" \
    -H "Authorization: Bearer ${KEY}" \
    -H "Content-Type: application/json" \
    -d '{"model":"gpt-4o-mini","messages":[{"role":"user","content":"reply with one word ok"}]}')

REQ_ID=$(echo "$RESP" | jq -r '.id')
PROMPT=$(echo "$RESP" | jq -r '.usage.prompt_tokens')
COMPLETION=$(echo "$RESP" | jq -r '.usage.completion_tokens')

echo "request_id=$REQ_ID prompt=$PROMPT completion=$COMPLETION"

# 2. 在 new-api logs API 查这条
sleep 2
LOG=$(curl -fsS -H "Authorization: Bearer ${ADMIN}" \
    "${BASE}/api/log/?p=0&pagesize=1&type=2")
LOG_PROMPT=$(echo "$LOG" | jq -r '.data[0].prompt_tokens')
LOG_COMPLETION=$(echo "$LOG" | jq -r '.data[0].completion_tokens')
LOG_QUOTA=$(echo "$LOG" | jq -r '.data[0].quota')

echo "log: prompt=$LOG_PROMPT completion=$LOG_COMPLETION quota=$LOG_QUOTA"

# 3. 校验
[[ "$LOG_PROMPT" == "$PROMPT" ]] || { echo "FAIL: prompt mismatch"; exit 1; }
[[ "$LOG_COMPLETION" == "$COMPLETION" ]] || { echo "FAIL: completion mismatch"; exit 1; }

# 4. 校验 quota 计算
# 预期 = (prompt * model_ratio + completion * model_ratio * completion_ratio) * group_ratio
# 这里只校验 quota > 0
[[ $LOG_QUOTA -gt 0 ]] || { echo "FAIL: quota=0"; exit 1; }

echo "PASS"
