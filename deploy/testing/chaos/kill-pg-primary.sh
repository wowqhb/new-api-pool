#!/usr/bin/env bash
# 混沌实验 C-02：kill PG 主库，验证 Patroni failover RTO < 30s
set -euo pipefail

cd "$(dirname "$0")"

echo "[C-02] 准备 kill PG 主库（依赖 Patroni 自动 failover）"
echo "  ⚠️ 仅在 staging 跑！"
read -r -p "继续？[y/N] " ok
[[ "${ok,,}" == "y" ]] || exit 0

# 1. 找当前 leader
LEADER=$(docker exec etcd1 etcdctl get /service/upstream/leader --print-value-only 2>/dev/null \
    || echo "patroni1")

echo "[*] 当前 leader: $LEADER"

# 2. 起监控（每 1s 写探活）
mon="/tmp/chaos-c02-$(date +%s).log"
(
    end=$(($(date +%s) + 120))
    while [[ $(date +%s) -lt $end ]]; do
        if docker exec haproxy psql -U postgres -h localhost -p 5000 -c "SELECT 1" >/dev/null 2>&1; then
            echo "$(date +%s%3N) ok" >> "$mon"
        else
            echo "$(date +%s%3N) DOWN" >> "$mon"
        fi
        sleep 1
    done
) &
MON_PID=$!

START=$(date +%s)

# 3. 杀 leader
docker stop "$LEADER"

# 4. 等切换完成（haproxy 上能写为止）
for i in {1..60}; do
    if docker exec haproxy psql -U postgres -h localhost -p 5000 -c "SELECT pg_is_in_recovery()" 2>/dev/null | grep -q "f"; then
        END=$(date +%s)
        RTO=$((END - START))
        break
    fi
    sleep 1
done

wait "$MON_PID"

# 5. 启动旧 leader 作为 replica
docker start "$LEADER"

# 6. 检查 RTO
echo "[+] RTO ≈ ${RTO:-?}s"
echo "[+] 监控日志：$mon"

DOWN=$(grep -c " DOWN" "$mon" || true)
echo "[+] 不可用次数（每秒 1 次探活）：$DOWN"

if (( ${RTO:-99} > 30 )); then
    echo "❌ RTO ${RTO}s > 30s 不达标"
    exit 1
fi
echo "✅ 通过"
