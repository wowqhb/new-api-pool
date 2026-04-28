#!/usr/bin/env bash
# 批量生成邀请码（new-api 用 redemption + 用户邀请双轨制）
# 这里生成的是 "免费试用兑换码"，新人用兑换码注册可绑定到推荐人
# 用法：bash gen-invite-codes.sh [数量] [面额quota]
set -euo pipefail
cd "$(dirname "$0")/../.."
if [[ -f .env ]]; then set -a; source .env; set +a; fi
: "${ADMIN_API_TOKEN:?}"
API_BASE="${API_BASE:-http://127.0.0.1:3000}"

COUNT="${1:-50}"
QUOTA="${2:-500000}"

OUT="risk-control/invites-$(date +%Y%m%d-%H%M%S).csv"
mkdir -p risk-control
echo "name,key" > "$OUT"

for i in $(seq 1 "$COUNT"); do
	NAME="invite-$(date +%Y%m%d)-$(printf '%03d' "$i")"
	RESP=$(curl -fsS -X POST "${API_BASE}/api/redemption" \
		-H "Authorization: Bearer ${ADMIN_API_TOKEN}" \
		-H "Content-Type: application/json" \
		-d "{\"name\":\"${NAME}\",\"quota\":${QUOTA},\"count\":1}")
	if [[ "$(echo "$RESP" | jq -r '.success')" == "true" ]]; then
		KEY=$(echo "$RESP" | jq -r '.data[0]')
		echo "${NAME},${KEY}" >> "$OUT"
		echo "[+] $NAME -> $KEY"
	else
		echo "[!] 第 $i 失败: $(echo "$RESP" | jq -r '.message')"
	fi
done

echo ""
echo "[+] 完成: $OUT"
echo "[*] 分发方式："
echo "    - 群发：把 KEY 列复制粘贴"
echo "    - 一对一：CSV 导入 CRM"
echo "    - 注意：邀请码有面额，不要乱发！"
