#!/usr/bin/env bash
# 混沌实验 C-01：kill 一个 new-api 实例，看流量是否切走
set -euo pipefail

INSTANCE="${1:-new-api-2}"
DURATION="${2:-300}"  # 秒，默认 5 分钟
COMPOSE="${COMPOSE_FILE:-../../docker-compose.prod.yml}"

cd "$(dirname "$0")"

echo "[C-01] 准备 kill ${INSTANCE} 持续 ${DURATION}s"
read -r -p "继续？[y/N] " ok
[[ "${ok,,}" == "y" ]] || exit 0

# 1. 通知 staging 群（如配置）
if [[ -n "${TELEGRAM_BOT_TOKEN:-}" ]]; then
    curl -fsS "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
        -d "chat_id=${TELEGRAM_CHAT_ID}" \
        -d "text=🧪 [Chaos] 即将 kill ${INSTANCE} 持续 ${DURATION}s（不是真故障）" || true
fi

# 2. 启动 SLO 监控（后台跑 5 分钟，每 10s 探活）
(
    sloout="/tmp/chaos-c01-${INSTANCE}-$(date +%s).log"
    end=$(($(date +%s) + DURATION + 60))
    while [[ $(date +%s) -lt $end ]]; do
        code=$(curl -s -o /dev/null -w "%{http_code}" "https://api-staging.example.com/v1/models" \
            -H "Authorization: Bearer ${TEST_API_KEY}")
        echo "$(date -u +%FT%TZ) $code" >> "$sloout"
        sleep 5
    done
    echo "[*] SLO 日志：$sloout"
) &
SLO_PID=$!

# 3. 停容器
docker compose -f "$COMPOSE" stop "$INSTANCE"

# 4. 等待 N 秒
echo "[*] ${INSTANCE} 已停，等 ${DURATION}s..."
sleep "$DURATION"

# 5. 恢复
docker compose -f "$COMPOSE" start "$INSTANCE"

# 6. 等 SLO 监控结束
wait "$SLO_PID"

# 7. 计算可用率
LOG=$(ls -t /tmp/chaos-c01-${INSTANCE}-*.log | head -1)
total=$(wc -l < "$LOG")
ok=$(grep -c " 200" "$LOG" || true)
rate=$(awk "BEGIN{printf \"%.2f\", $ok/$total*100}")
echo "[+] 可用率：${ok}/${total} = ${rate}%"
echo "[+] 详细：$LOG"

if (( $(echo "$rate < 99" | bc -l) )); then
    echo "❌ 可用率 ${rate}% < 99%，故障切换不达标"
    exit 1
fi
echo "✅ 通过"
