# 密钥轮换 SOP

## 季度轮换清单（每 90 天一次）

| 密钥 | 来源 | 影响 | 难度 |
|---|---|---|---|
| `SESSION_SECRET` | new-api 会话签名 | 所有用户重新登录 | ★ |
| `CRYPTO_SECRET` | new-api 内部加密 | 配置加密的字段需重新加密 | ★★★ |
| `PG_PASSWORD` | DB 密码 | 短暂中断（重启 new-api 实例）| ★★ |
| `REDIS_PASSWORD` | Redis 密码 | 同上 | ★★ |
| `GRAFANA_ADMIN_PASSWORD` | Grafana 管理 | 仅管理员 | ★ |
| `BACKUP_ENCRYPTION_PASSWORD` | 备份加密 | 旧备份得用旧密码 | ★ |
| 上游 API Key（OpenAI/Anthropic）| 上游 | 多账号需要逐个 | ★★ |
| Vault root token | Vault | 重新 init 风险大 | ★★★★ |

## 标准流程

### 1. 准备（提前 1 周）

- [ ] 通知用户即将维护（如有用户登录态变化）
- [ ] 备份当前 .env / DB / Vault
- [ ] 计划维护窗口（凌晨 3-5 点）

### 2. 生成新密钥

```bash
cd deploy
bash scripts/gen-secrets.sh --rotate    # 生成新密钥到 .env.new
diff .env .env.new
```

### 3. 应用（按依赖顺序）

```bash
# Step 1: 应用低影响的（GRAFANA_ADMIN/BACKUP_ENC 等）
mv .env .env.old
mv .env.new .env

# Step 2: DB 密码 - 先在 PG 创建新密码，让两实例共存几分钟
docker exec new-api-postgres psql -U newapi -c "ALTER USER newapi WITH PASSWORD '新密码';"
# 然后重启 new-api 实例
docker compose -f docker-compose.prod.yml up -d new-api-1 new-api-2

# Step 3: Redis 密码 - 改 redis.conf 后 reload
docker exec new-api-redis redis-cli CONFIG SET requirepass "新密码"
docker exec new-api-redis redis-cli CONFIG REWRITE
docker compose up -d new-api-1 new-api-2

# Step 4: SESSION_SECRET（用户全部重新登录）
docker compose restart new-api-1 new-api-2
```

### 4. CRYPTO_SECRET 轮换（最复杂）

new-api 用这个加密 channel.key 等敏感字段。**直接换会导致旧字段无法解密**。

需要双密钥过渡期：
1. 加 `CRYPTO_SECRET_OLD` 环境变量为旧密钥
2. 升级到支持双密钥读、新密钥写的版本（需要 fork 改代码）
3. 跑迁移脚本把所有旧密文重新加密
4. 移除 `CRYPTO_SECRET_OLD`

如果不想做迁移：**导出所有渠道 → 删 → 用新密钥重新导入**（停服 30 分钟）：

```bash
# 导出
bash channels/scripts/export-all.sh > /tmp/channels.json

# 改 CRYPTO_SECRET，重启
$EDITOR .env && docker compose restart new-api-1 new-api-2

# 重导入（密钥从 Vault 取，所以 channels.json 里其实只有元数据）
bash channels/scripts/reimport-all.sh /tmp/channels.json
```

### 5. 上游 API Key 轮换

```bash
# 在上游平台创建新 Key（OpenAI/Anthropic/Google）
# 把新 Key 入池为新渠道，priority 200，weight 50
bash scripts/import-channel.sh channels/template-official-openai-new.json

# 灰度 24h（同时新旧并存）
# 新渠道 OK 后，旧渠道 weight=0
# 7 天后旧 Key 在上游 revoke 并删 channel
```

### 6. Vault root token 轮换

```bash
docker exec -i vault vault token create -policy=root -ttl=720h    # 创新 token
# 用新 token 测试一下读写
# 旧 token revoke：
docker exec -i vault vault token revoke <旧 root token>
```

## 验证

```bash
# 全部服务能起
docker compose -f docker-compose.prod.yml ps

# 一次端到端调用
curl -fsS https://api.example.com/v1/chat/completions \
  -H "Authorization: Bearer <test_token>" \
  -d '{"model":"gpt-4o-mini","messages":[{"role":"user","content":"ping"}]}'

# 备份能恢复（用新加密密码做一次 verify）
bash scripts/restore.sh verify <最新备份文件>
```

## 文档化

每次轮换在 [`security/rotation-log.md`](./rotation-log.md) 加一条：

```markdown
- 2026-04-27: 季度轮换。SESSION/CRYPTO/PG/REDIS/GRAFANA 已完成，CRYPTO 跑了重导入。
  - 操作人：@xxx
  - 维护窗口：03:00-04:30，实际中断 6 分钟
  - 备份：/backups/2026-04-27-before-rotation.tar.gz.enc
```
