#!/usr/bin/env bash
# 完整回归测试（每周一次，跑约 10 分钟）
set -euo pipefail

BASE="${TEST_BASE_URL:-https://api-staging.example.com}"
KEY="${TEST_API_KEY:?需要设 TEST_API_KEY}"

cd "$(dirname "$0")"

mkdir -p reports
ts=$(date +%Y%m%d-%H%M%S)
LOG="reports/${ts}.log"

run_case() {
    local name="$1" script="$2"
    echo "=== $name ===" | tee -a "$LOG"
    if bash "$script" >> "$LOG" 2>&1; then
        echo "  ✅ $name"
    else
        echo "  ❌ $name"
        return 1
    fi
}

PASS=0
FAIL=0

for case_script in cases/*.sh; do
    name=$(basename "$case_script" .sh)
    if run_case "$name" "$case_script"; then
        PASS=$((PASS+1))
    else
        FAIL=$((FAIL+1))
    fi
done

echo ""
echo "========================================"
echo "回归测试结果：通过 $PASS / 失败 $FAIL"
echo "日志：$LOG"
echo "========================================"

[[ $FAIL -eq 0 ]]
