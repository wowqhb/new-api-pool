#!/usr/bin/env bash
# 烟雾测试：每次部署后必跑，60s 完成
set -euo pipefail

BASE="${TEST_BASE_URL:-https://api.example.com}"
KEY="${TEST_API_KEY:?需要设 TEST_API_KEY 测试 token}"

echo "[*] 烟雾测试 → ${BASE}"

fail=0

check() {
    local name="$1"; shift
    local expected="$1"; shift
    local actual
    actual=$(curl -s -o /dev/null -w "%{http_code}" "$@" -H "Authorization: Bearer ${KEY}")
    if [[ "$actual" == "$expected" ]]; then
        echo "  ✅ ${name}"
    else
        echo "  ❌ ${name} expected=${expected} actual=${actual}"
        fail=$((fail+1))
    fi
}

# 1. health
check "health endpoint"        200 "${BASE}/health"
check "models list"            200 "${BASE}/v1/models"

# 2. OpenAI 简单聊天
RESP=$(curl -fsS "${BASE}/v1/chat/completions" \
    -H "Authorization: Bearer ${KEY}" \
    -H "Content-Type: application/json" \
    -d '{"model":"gpt-4o-mini","messages":[{"role":"user","content":"reply with the word ok"}]}')
echo "$RESP" | jq . >/dev/null && echo "  ✅ chat completion JSON valid" || { echo "  ❌ chat JSON invalid"; fail=$((fail+1)); }

# 3. 流式
STREAM=$(curl -sN "${BASE}/v1/chat/completions" \
    -H "Authorization: Bearer ${KEY}" \
    -H "Content-Type: application/json" \
    -d '{"model":"gpt-4o-mini","messages":[{"role":"user","content":"hi"}],"stream":true}')
if echo "$STREAM" | grep -q "data:"; then
    echo "  ✅ streaming"
else
    echo "  ❌ streaming"
    fail=$((fail+1))
fi

# 4. embedding
EMB=$(curl -fsS "${BASE}/v1/embeddings" \
    -H "Authorization: Bearer ${KEY}" \
    -H "Content-Type: application/json" \
    -d '{"model":"text-embedding-3-small","input":"hello"}')
EMB_LEN=$(echo "$EMB" | jq '.data[0].embedding | length')
if [[ "$EMB_LEN" -gt 100 ]]; then
    echo "  ✅ embedding (dim=${EMB_LEN})"
else
    echo "  ❌ embedding dim ${EMB_LEN}"
    fail=$((fail+1))
fi

# 5. 鉴权失败应该 401
check "auth failure → 401"     401 "${BASE}/v1/models" -H "Authorization: Bearer sk-invalid-token-abc"

# 6. Anthropic 兼容
ANT=$(curl -fsS "${BASE}/v1/messages" \
    -H "Authorization: Bearer ${KEY}" \
    -H "anthropic-version: 2023-06-01" \
    -H "Content-Type: application/json" \
    -d '{"model":"claude-haiku-4-5","max_tokens":50,"messages":[{"role":"user","content":"hi"}]}')
echo "$ANT" | jq -e '.content[0].text' >/dev/null && echo "  ✅ anthropic compat" || { echo "  ❌ anthropic"; fail=$((fail+1)); }

if [[ $fail -gt 0 ]]; then
    echo ""
    echo "❌ 烟雾测试失败 ($fail 项不通过)"
    exit 1
fi

echo ""
echo "✅ 全部 6 项通过"
