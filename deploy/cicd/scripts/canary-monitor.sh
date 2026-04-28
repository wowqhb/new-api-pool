#!/usr/bin/env bash
# 灰度监控：盯 prom 指标 N 秒，超阈值自动 fail
set -euo pipefail

DURATION="${1:-900}"  # 15 分钟
PROM="${PROM_URL:-http://prom.internal:9090}"

# SLO 阈值
MAX_ERROR_RATE=0.02          # 错误率
MAX_P95_MS=5000               # p95
MAX_DEGRADATION_RATIO=1.5     # canary p95 不超过 baseline 的 1.5 倍

start=$(date +%s)
end=$((start + DURATION))

query() {
    local q="$1"
    curl -fsSG --data-urlencode "query=$q" "${PROM}/api/v1/query" \
        | jq -r '.data.result[0].value[1] // "0"'
}

while [[ $(date +%s) -lt $end ]]; do
    err_canary=$(query 'sum(rate(new_api_http_requests_total{status=~"5..", instance="canary"}[2m])) / sum(rate(new_api_http_requests_total{instance="canary"}[2m]))')
    p95_canary=$(query 'histogram_quantile(0.95, sum by (le) (rate(new_api_http_request_duration_seconds_bucket{instance="canary"}[2m]))) * 1000')
    p95_baseline=$(query 'histogram_quantile(0.95, sum by (le) (rate(new_api_http_request_duration_seconds_bucket{instance!="canary"}[2m]))) * 1000')

    elapsed=$(($(date +%s) - start))
    printf "[%4ds] err=%.2f%%  p95_canary=%.0fms  p95_base=%.0fms\n" \
        "$elapsed" "$(echo "$err_canary * 100" | bc -l)" "$p95_canary" "$p95_baseline"

    # 阈值检查
    if (( $(echo "$err_canary > $MAX_ERROR_RATE" | bc -l) )); then
        echo "❌ canary 错误率 $err_canary > $MAX_ERROR_RATE"
        exit 1
    fi
    if (( $(echo "$p95_canary > $MAX_P95_MS" | bc -l) )); then
        echo "❌ canary p95 ${p95_canary}ms > ${MAX_P95_MS}ms"
        exit 1
    fi
    if (( $(echo "$p95_baseline > 0" | bc -l) )); then
        ratio=$(echo "$p95_canary / $p95_baseline" | bc -l)
        if (( $(echo "$ratio > $MAX_DEGRADATION_RATIO" | bc -l) )); then
            echo "❌ canary 比 baseline 慢 ${ratio}x，超过 ${MAX_DEGRADATION_RATIO}x"
            exit 1
        fi
    fi

    sleep 30
done

echo "✅ canary 监控通过 ${DURATION}s 全部 SLO 达标"
