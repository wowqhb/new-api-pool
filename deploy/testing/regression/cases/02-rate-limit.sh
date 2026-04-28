#!/usr/bin/env bash
# 限速正确性：连发超 RPM 应该 429
set -euo pipefail

BASE="${TEST_BASE_URL}"
KEY="${TEST_API_KEY_RPM10}"  # 设为 RPM=10 的测试 token

success=0
rate_limited=0

for i in $(seq 1 30); do
    code=$(curl -s -o /dev/null -w "%{http_code}" "${BASE}/v1/chat/completions" \
        -H "Authorization: Bearer ${KEY}" \
        -H "Content-Type: application/json" \
        -d '{"model":"gpt-4o-mini","messages":[{"role":"user","content":"hi"}]}')
    case "$code" in
        200) success=$((success+1));;
        429) rate_limited=$((rate_limited+1));;
        *)   echo "unexpected $code"; exit 1;;
    esac
done

echo "success=$success rate_limited=$rate_limited"

# 应该有约 10 次成功和 20 次 429
[[ $success -le 12 && $rate_limited -ge 18 ]] || {
    echo "FAIL: 限速未生效"
    exit 1
}

echo "PASS"
