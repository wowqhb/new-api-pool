#!/usr/bin/env bash
# 缓存命中：同样 prompt 第二次应该 HIT
set -euo pipefail

BASE="${TEST_BASE_URL}"
KEY="${TEST_API_KEY}"

PROMPT="What is 2+2? Reply with just the number."

# 第 1 次
H1=$(curl -fsS -D - "${BASE}/v1/chat/completions" \
    -H "Authorization: Bearer ${KEY}" \
    -H "Content-Type: application/json" \
    -d "{\"model\":\"gpt-4o-mini\",\"messages\":[{\"role\":\"user\",\"content\":\"${PROMPT}\"}],\"temperature\":0}" \
    -o /tmp/r1.json)
CACHE1=$(echo "$H1" | grep -i "x-cache:" | awk '{print $2}' | tr -d '\r')
echo "first: x-cache=$CACHE1"

# 第 2 次（应命中 L0）
sleep 1
H2=$(curl -fsS -D - "${BASE}/v1/chat/completions" \
    -H "Authorization: Bearer ${KEY}" \
    -H "Content-Type: application/json" \
    -d "{\"model\":\"gpt-4o-mini\",\"messages\":[{\"role\":\"user\",\"content\":\"${PROMPT}\"}],\"temperature\":0}" \
    -o /tmp/r2.json)
CACHE2=$(echo "$H2" | grep -i "x-cache:" | awk '{print $2}' | tr -d '\r')
echo "second: x-cache=$CACHE2"

# 验证：第二次必须是 HIT
case "$CACHE2" in
    HIT-L0|HIT-L1) echo "PASS";;
    *) echo "FAIL: 第二次未命中缓存（x-cache=$CACHE2）"; exit 1;;
esac
