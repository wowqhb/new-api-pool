#!/usr/bin/env bash
# 批量生成兑换码（充值码）
# 用法：bash gen-redemption.sh <名称前缀> <面额(quota单位)> <数量>
#   例：bash gen-redemption.sh promo-may 1000000 100
#       生成 100 张面额 1,000,000 quota（≈ $5）的"promo-may-XXX"兑换码
set -euo pipefail
cd "$(dirname "$0")/../.."
if [[ -f .env ]]; then set -a; source .env; set +a; fi
: "${ADMIN_API_TOKEN:?需要 ADMIN_API_TOKEN}"
API_BASE="${API_BASE:-http://127.0.0.1:3000}"

NAME="${1:-redeem-$(date +%Y%m%d)}"
QUOTA="${2:-500000}"
COUNT="${3:-50}"

OUT="billing/reports/redemption-$(date +%Y%m%d-%H%M%S).csv"
mkdir -p "$(dirname "$OUT")"
echo "name,key,quota" > "$OUT"

for i in $(seq 1 "$COUNT"); do
	BATCH_NAME="${NAME}-$(printf '%03d' "$i")"
	RESP=$(curl -fsS -X POST "${API_BASE}/api/redemption" \
		-H "Authorization: Bearer ${ADMIN_API_TOKEN}" \
		-H "Content-Type: application/json" \
		-d "{\"name\":\"${BATCH_NAME}\",\"quota\":${QUOTA},\"count\":1}")
	OK=$(echo "$RESP" | jq -r '.success')
	if [[ "$OK" == "true" ]]; then
		KEY=$(echo "$RESP" | jq -r '.data[0]')
		echo "${BATCH_NAME},${KEY},${QUOTA}" >> "$OUT"
		echo "[+] $BATCH_NAME -> $KEY"
	else
		echo "[!] 第 $i 个失败: $(echo "$RESP" | jq -r '.message')" >&2
	fi
done

echo "[+] 完成，输出: $OUT"
