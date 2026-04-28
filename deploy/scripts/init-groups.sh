#!/usr/bin/env bash
# 初始化用户分组（vip / default / free）和分组倍率
# 注意：new-api 大多数分组配置在「运营设置」UI 里改，没有完整的 CRUD API
# 这个脚本会用 SQL 直写，避免 UI 一项项点
#
# 使用前请确保：
#   - new-api 至少启动过一次（建好表）
#   - .env 里有 PG_USER / PG_PASSWORD / PG_DB
#   - 你已经备份过

set -euo pipefail

cd "$(dirname "$0")/.."

if [[ -f .env ]]; then
	set -a
	# shellcheck disable=SC1091
	source .env
	set +a
fi

: "${PG_USER:?}"
: "${PG_DB:?}"
: "${PG_PASSWORD:?}"

PG_CONTAINER="new-api-postgres"

echo "═══════════════════════════════════════════"
echo " 初始化用户分组与倍率"
echo " 数据库: ${PG_DB} @ ${PG_CONTAINER}"
echo "═══════════════════════════════════════════"

read -p "继续吗？[y/N] " -n 1 -r CONFIRM
echo
if [[ ! $CONFIRM =~ ^[Yy]$ ]]; then
	echo "[!] 取消"
	exit 0
fi

run_sql() {
	docker exec -e PGPASSWORD="$PG_PASSWORD" "$PG_CONTAINER" \
		psql -U "$PG_USER" -d "$PG_DB" -v ON_ERROR_STOP=1 "$@"
}

echo "[*] 设置用户分组倍率（system options）..."

# new-api 把分组倍率存在 options 表里，key 一般是 GroupRatio
# 不同版本字段名略有不同：GroupRatio 或 group_ratio
run_sql -c "
INSERT INTO options (key, value)
VALUES (
  'GroupRatio',
  '{\"vip\": 1.5, \"default\": 1.2, \"free\": 1.0, \"auto\": 1.2}'
)
ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value;
"

echo "[*] 设置默认用户分组（新注册用户）..."
run_sql -c "
UPDATE options SET value = 'default' WHERE key = 'DefaultGroup';
INSERT INTO options (key, value)
SELECT 'DefaultGroup', 'default'
WHERE NOT EXISTS (SELECT 1 FROM options WHERE key = 'DefaultGroup');
"

echo "[*] 关闭公开注册（生产环境）..."
run_sql -c "
INSERT INTO options (key, value) VALUES ('RegisterEnabled', 'false')
ON CONFLICT (key) DO UPDATE SET value = 'false';
"

echo "[*] 启用监控设置（自动禁用/自动启用）..."
run_sql -c "
INSERT INTO options (key, value) VALUES ('AutomaticDisableChannelEnabled', 'true')
ON CONFLICT (key) DO UPDATE SET value = 'true';
INSERT INTO options (key, value) VALUES ('AutomaticEnableChannelEnabled', 'true')
ON CONFLICT (key) DO UPDATE SET value = 'true';
"

echo "[+] 完成"
echo ""
echo "下一步："
echo "  1. 管理后台 → 系统设置 → 倍率设置：检查 GroupRatio 是否生效"
echo "  2. 管理后台 → 运营设置 → 监控设置：调整失败禁用阈值（建议 5）"
echo "  3. 用 import-channel.sh 导入各分组渠道"
echo "  4. 创建第一批邀请码（管理后台 → 邀请码管理）"
