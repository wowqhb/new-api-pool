#!/usr/bin/env bash
# 自动生成所有随机密钥并写入 .env
# 用法：bash scripts/gen-secrets.sh [--force]
# --force 会覆盖已有的密钥（危险！会导致历史 Key 解密失败、用户被踢出登录）

set -euo pipefail

cd "$(dirname "$0")/.."

ENV_FILE=".env"
FORCE=false

if [[ "${1:-}" == "--force" ]]; then
	FORCE=true
fi

if [[ ! -f "$ENV_FILE" ]]; then
	if [[ -f ".env.example" ]]; then
		cp .env.example .env
		echo "[+] 已从 .env.example 复制为 .env"
	else
		echo "[!] 没找到 .env 也没找到 .env.example，请先准备好" >&2
		exit 1
	fi
fi

# 生成 32 字节随机串（base64 后约 44 字符），跨平台
gen_secret() {
	# /dev/urandom 在 macOS/Linux 都可用；openssl 也行做兜底
	if command -v openssl >/dev/null 2>&1; then
		openssl rand -base64 32 | tr -d '\n=/+' | cut -c1-44
	else
		head -c 64 /dev/urandom | base64 | tr -d '\n=/+' | cut -c1-44
	fi
}

# 替换 .env 中 KEY=GENERATE_ME 行
# 已经填了真实值的不动（除非 --force）
update_secret() {
	local key="$1"
	local current
	current=$(grep -E "^${key}=" "$ENV_FILE" | head -1 | cut -d= -f2- || true)

	if [[ "$FORCE" == true ]] || [[ "$current" == "GENERATE_ME" ]] || [[ -z "$current" ]]; then
		local new_val
		new_val=$(gen_secret)
		# macOS/Linux 兼容的 sed -i
		if sed --version >/dev/null 2>&1; then
			sed -i "s|^${key}=.*|${key}=${new_val}|" "$ENV_FILE"
		else
			sed -i '' "s|^${key}=.*|${key}=${new_val}|" "$ENV_FILE"
		fi
		echo "[+] ${key} 已生成"
	else
		echo "[=] ${key} 已存在，跳过（用 --force 强制覆盖）"
	fi
}

echo "═══════════════════════════════════════════"
echo "  生成 New API 部署密钥"
echo "  目标文件: $ENV_FILE"
[[ "$FORCE" == true ]] && echo "  ⚠️  FORCE 模式：会覆盖已有密钥"
echo "═══════════════════════════════════════════"

update_secret SESSION_SECRET
update_secret CRYPTO_SECRET
update_secret PG_PASSWORD
update_secret REDIS_PASSWORD
update_secret BACKUP_ENCRYPTION_PASSWORD
update_secret GRAFANA_ADMIN_PASSWORD

echo ""
echo "完成。请检查 .env 中的：API_DOMAIN / ADMIN_DOMAIN / ACME_EMAIL / ADMIN_ALLOW_CIDR"
echo ""
echo "下一步:"
echo "  docker compose -f docker-compose.prod.yml pull"
echo "  docker compose -f docker-compose.prod.yml up -d"
