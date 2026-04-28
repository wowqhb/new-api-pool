# Runbook 09：新版本升级失败 / 引入回归

**P1** · 影响：升级期间到回滚完成的故障窗口 · 目标 MTTR：≤ 5 分钟

## 现象 / 触发

- 升级 `NEW_API_VERSION` 后 5xx 突增
- 部分功能消失或行为改变（比如 token 计费方式）
- 新版本启动失败 / 容器循环重启

## 前置准备

- [ ] **滚动升级**：从不一次升两个实例，先升 new-api-1，观察 30 分钟，再升 new-api-2
- [ ] **不要用 latest tag**：`.env` 里固定 `NEW_API_VERSION=v0.13.1`
- [ ] **升级前先备份**：`bash scripts/backup.sh`
- [ ] **新版本变更记录看一遍**：[GitHub Releases](https://github.com/QuantumNous/new-api/releases)
- [ ] **数据库 schema 迁移**：很多升级会自动跑 migration，**回滚时可能不能直接降级版本**

## 升级流程（标准）

```bash
cd deploy/

# 1. 备份
bash scripts/backup.sh

# 2. 改版本号
$EDITOR .env   # NEW_API_VERSION=v0.13.2

# 3. 拉镜像
docker compose -f docker-compose.prod.yml pull new-api-1 new-api-2

# 4. 升级实例 1（实例 2 仍在跑老版本）
docker compose -f docker-compose.prod.yml up -d --no-deps new-api-1

# 5. 观察 30 分钟
docker compose -f docker-compose.prod.yml logs -f new-api-1
# 看 Grafana 看板
# 测试关键路径：登录 / 调用 / 充值

# 6. 没问题再升实例 2
docker compose -f docker-compose.prod.yml up -d --no-deps new-api-2
```

## 紧急回滚

```bash
# 1. 改回上一个版本
$EDITOR .env   # NEW_API_VERSION=v0.13.1

# 2. 拉旧镜像（如果本地清过）
docker compose -f docker-compose.prod.yml pull

# 3. 重启实例
docker compose -f docker-compose.prod.yml up -d new-api-1 new-api-2
```

## 如果数据库 schema 已经迁移过，回滚版本用不了

这是最坑的场景。处理顺序：

```bash
# 1. 停 new-api（防写）
docker compose -f docker-compose.prod.yml stop new-api-1 new-api-2

# 2. 用升级前的备份恢复 DB
bash scripts/restore.sh ./backups/newapi-升级前的.sql.gz.enc overwrite

# 3. 启动旧版本 new-api
docker compose -f docker-compose.prod.yml up -d new-api-1 new-api-2
```

⚠️ **会丢失升级期间的所有数据**（充值 / 消耗记录），事后必须对账补录。

## 配置变更回滚

如果是改了配置（不是版本）后炸了：

```bash
# Caddyfile 历史版本
git -C /path/to/deploy log --oneline caddy/Caddyfile
git -C /path/to/deploy checkout HEAD~1 -- caddy/Caddyfile
docker compose -f docker-compose.prod.yml exec caddy caddy reload --config /etc/caddy/Caddyfile

# .env 历史
# 强烈建议 .env 也进 git（脱敏后）或用 Vault 管，否则改错没法回退
```

## 事后复盘

- 升级失败原因（容器/迁移/逻辑回归）：
- 是否 Release Note 提示但没看到：
- 是否需要灰度环境（Staging）：
- 监控有没有及时报警：
