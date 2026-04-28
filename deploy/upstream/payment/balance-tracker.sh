#!/usr/bin/env bash
# 卡余额追踪 + 告警
# 用法：./balance-tracker.sh
# 数据来源：upstream-postgres `cards` 表（需先建）
set -euo pipefail
cd "$(dirname "$0")/../.."

DB="${UPSTREAM_PG_DSN:-postgres://upstream:upstream@localhost:5433/upstream}"
LOW_BALANCE_USD="${LOW_BALANCE_USD:-5}"
TG="${TELEGRAM_BOT_TOKEN:-}"
TG_CHAT="${TELEGRAM_CHAT_ID:-}"

# 1. 确保 cards 表存在（首次运行自动创建）
psql "$DB" -c "
CREATE TABLE IF NOT EXISTS cards (
    id              BIGSERIAL PRIMARY KEY,
    label           TEXT,
    bin             TEXT,            -- 前 6 位
    last4           TEXT,            -- 后 4 位
    vendor          TEXT,            -- onekey/bybit/wildcard ...
    vault_path      TEXT,            -- 完整卡号在 Vault 的 path
    initial_balance NUMERIC(10,2) DEFAULT 0,
    spent           NUMERIC(10,2) DEFAULT 0,
    status          TEXT DEFAULT 'active', -- active/locked/depleted/retired/blacklist
    bound_account_id BIGINT,        -- 绑定到哪个 accounts.id
    created_at      TIMESTAMPTZ DEFAULT NOW(),
    last_charged_at TIMESTAMPTZ
);" >/dev/null

OUT_DIR="payment/reports/$(date +%Y%m%d)"
mkdir -p "$OUT_DIR"

# 2. 总览
psql "$DB" -c "
SELECT vendor,
       COUNT(*)                                 AS total,
       SUM(initial_balance - spent)::NUMERIC(10,2) AS remaining,
       COUNT(*) FILTER (WHERE status='active')  AS active,
       COUNT(*) FILTER (WHERE status='depleted') AS depleted,
       COUNT(*) FILTER (WHERE status='blacklist') AS blacklist
FROM cards
GROUP BY vendor
ORDER BY remaining DESC;
" > "$OUT_DIR/summary.txt"

# 3. 低余额清单
LOW_LIST=$(psql "$DB" -At -c "
SELECT id, label, vendor, last4, (initial_balance - spent)::NUMERIC(10,2)
FROM cards
WHERE status='active' AND (initial_balance - spent) < ${LOW_BALANCE_USD}
ORDER BY (initial_balance - spent) ASC;
")
echo "$LOW_LIST" > "$OUT_DIR/low-balance.txt"

# 4. 闲置清单（90 天无扣费）
psql "$DB" -c "
SELECT id, label, vendor, last4, (initial_balance - spent)::NUMERIC(10,2) AS remaining,
       last_charged_at
FROM cards
WHERE status='active'
  AND (last_charged_at IS NULL OR last_charged_at < NOW() - INTERVAL '90 days')
ORDER BY last_charged_at NULLS FIRST;
" > "$OUT_DIR/idle.txt"

echo "[+] reports → $OUT_DIR"

# 5. Telegram 告警
if [[ -n "$TG" && -n "$TG_CHAT" && -n "$LOW_LIST" ]]; then
    cnt=$(echo "$LOW_LIST" | grep -c '^' || true)
    msg="💳 卡余额告警：${cnt} 张卡余额低于 \$${LOW_BALANCE_USD}\n\n${LOW_LIST}"
    curl -fsS -X POST "https://api.telegram.org/bot${TG}/sendMessage" \
        --data-urlencode "chat_id=${TG_CHAT}" \
        --data-urlencode "text=${msg}" \
        --data-urlencode "parse_mode=HTML" >/dev/null && echo "[+] Telegram 已发送"
fi
