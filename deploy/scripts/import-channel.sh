#!/usr/bin/env bash
# 单个渠道导入：读 JSON → 剥离 _comment 字段 → POST /api/channel
# 用法：
#   ADMIN_API_TOKEN=xxx bash scripts/import-channel.sh channels/template-xxx.json
#   或在 .env 里设 ADMIN_API_TOKEN
#
# 拿 token：管理后台 → 个人设置 → 系统访问令牌 → 创建（角色：管理员）

set -euo pipefail

cd "$(dirname "$0")/.."

if [[ -f .env ]]; then
	set -a
	# shellcheck disable=SC1091
	source .env
	set +a
fi

: "${ADMIN_API_TOKEN:?需要 ADMIN_API_TOKEN（从管理后台创建）}"
API_BASE="${API_BASE:-http://127.0.0.1:3000}"

if [[ $# -eq 0 ]]; then
	echo "用法：bash scripts/import-channel.sh <channel-template.json>"
	exit 1
fi

FILE="$1"
if [[ ! -f "$FILE" ]]; then
	echo "[!] 文件不存在: $FILE" >&2
	exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
	echo "[!] 需要 jq 命令" >&2
	exit 1
fi

echo "[*] 读取 $FILE"

# 剥离所有 _comment_ 开头的字段
PAYLOAD=$(jq 'walk(if type=="object" then with_entries(select(.key | startswith("_comment") | not)) else . end)' "$FILE")

# 检查必填
NAME=$(echo "$PAYLOAD" | jq -r '.name // empty')
TYPE=$(echo "$PAYLOAD" | jq -r '.type // empty')
KEY=$(echo "$PAYLOAD" | jq -r '.key // empty')

if [[ -z "$NAME" ]] || [[ -z "$TYPE" ]] || [[ -z "$KEY" ]]; then
	echo "[!] name / type / key 不能为空" >&2
	exit 1
fi

if [[ "$KEY" == *"REPLACE_ME"* ]]; then
	echo "[!] 检测到模板里的 REPLACE_ME，请先把 Key 填进去" >&2
	exit 1
fi

echo "[*] 提交渠道：$NAME（type=$TYPE）→ $API_BASE"

RESP=$(curl -fsS -X POST "${API_BASE}/api/channel" \
	-H "Authorization: Bearer ${ADMIN_API_TOKEN}" \
	-H "Content-Type: application/json" \
	-d "$PAYLOAD")

SUCCESS=$(echo "$RESP" | jq -r '.success')
if [[ "$SUCCESS" == "true" ]]; then
	CHID=$(echo "$RESP" | jq -r '.data.id // .data // empty')
	echo "[+] 创建成功 (channel_id=$CHID)"

	# 测试一下
	if [[ -n "$CHID" ]] && [[ "$CHID" != "null" ]]; then
		echo "[*] 测试渠道..."
		TEST=$(curl -fsS "${API_BASE}/api/channel/test/${CHID}" \
			-H "Authorization: Bearer ${ADMIN_API_TOKEN}" || echo '{"success":false}')
		TEST_OK=$(echo "$TEST" | jq -r '.success')
		if [[ "$TEST_OK" == "true" ]]; then
			echo "[+] 渠道测试通过"
		else
			echo "[!] 渠道测试失败: $(echo "$TEST" | jq -r '.message')"
		fi
	fi
else
	echo "[!] 创建失败: $(echo "$RESP" | jq -r '.message')" >&2
	exit 1
fi
