#!/usr/bin/env bash
# 协议兼容性：同一份 prompt 用三种协议调，结果都要合理
set -euo pipefail

BASE="${TEST_BASE_URL}"
KEY="${TEST_API_KEY}"

# OpenAI 协议调 Claude 模型（跨协议）
RESP1=$(curl -fsS "${BASE}/v1/chat/completions" \
    -H "Authorization: Bearer ${KEY}" \
    -H "Content-Type: application/json" \
    -d '{"model":"claude-haiku-4-5","messages":[{"role":"user","content":"reply ok"}]}')
echo "$RESP1" | jq -e '.choices[0].message.content' >/dev/null \
    || { echo "FAIL: OpenAI→Claude 跨协议"; exit 1; }
echo "  ✅ OpenAI 协议调 Claude"

# Anthropic 协议调 OpenAI 模型（跨协议）
RESP2=$(curl -fsS "${BASE}/v1/messages" \
    -H "Authorization: Bearer ${KEY}" \
    -H "anthropic-version: 2023-06-01" \
    -H "Content-Type: application/json" \
    -d '{"model":"gpt-4o-mini","max_tokens":50,"messages":[{"role":"user","content":"reply ok"}]}')
echo "$RESP2" | jq -e '.content[0].text' >/dev/null \
    || { echo "FAIL: Anthropic→OpenAI 跨协议"; exit 1; }
echo "  ✅ Anthropic 协议调 OpenAI"

# Gemini 协议调 Gemini 模型（直传）
RESP3=$(curl -fsS "${BASE}/v1beta/models/gemini-2.0-flash:generateContent?key=${KEY}" \
    -H "Content-Type: application/json" \
    -d '{"contents":[{"role":"user","parts":[{"text":"reply ok"}]}]}')
echo "$RESP3" | jq -e '.candidates[0].content.parts[0].text' >/dev/null \
    || { echo "FAIL: Gemini 直传"; exit 1; }
echo "  ✅ Gemini 协议直传"

echo "PASS"
