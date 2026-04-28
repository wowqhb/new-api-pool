# Vault 集成

把上游 Key（OpenAI/Anthropic/Google/OAuth refresh token）从 new-api 的 PostgreSQL 里搬到 [HashiCorp Vault](https://www.vaultproject.io/)，明文密钥不再落 DB。

## 目标方案

- 每个上游账号在 Vault 一个 path：`secret/upstream/<source>/<account>` 存 `{ api_key, refresh_token, ... }`
- new-api 启动时通过环境变量 / sidecar 拉对应密钥（**或者**只在创建/编辑渠道时手动从 Vault 取出贴进 admin）
- DB 里的 `key` 字段改存 Vault 引用 `vault://secret/upstream/openai/account-1`，不再是明文

> ⚠️ new-api 原生不支持 Vault 引用，需要在 sidecar 拦截或 fork 改 `relay/channel/keystore.go`。下文给的是最低成本方案：**密钥进 Vault，从 Vault 注入到 new-api 的运行时 env**。

## 方案 A：env 注入（成本最低，复用 new-api 现状）

适合：上游 Key 数量 < 100，主要是官方 Key

```yaml
# docker-compose.prod.yml 加 secrets-injector sidecar
new-api-1:
  environment:
    OPENAI_KEYS_FROM_VAULT: ${OPENAI_KEYS}
    # 启动前通过 entrypoint 包装从 Vault 拉值
```

参考 [`vault/inject-secrets.sh`](./vault/inject-secrets.sh) 实现一个 entrypoint 包装器。

## 方案 B：DB 字段加密（fork 改）

适合：上游 Key > 100，需要 admin UI 仍能用

1. fork new-api，改 `Channel.Key` 字段在写入前 envelope 加密（KEK 来自 Vault Transit 引擎）
2. 加 background goroutine 缓存解密结果
3. 维护成本高但安全性最强

## 方案 C：托管密钥但不变 Schema（推荐）

每个 channel 入池前**先 PUT 到 Vault**，只让 admin 拷贝来贴入 new-api：

```bash
# 入池前先存 Vault
vault kv put secret/upstream/openai/sk-proj-001 \
  api_key="sk-proj-..." \
  org_id="org-xxx" \
  email="account@example.com" \
  expires_at="2027-01-01"

# 然后人工 admin → 渠道 → 新建，密钥贴 sk-proj-...
# 关键点：万一 DB 泄漏，攻击者只拿到 sk-... 没有元数据，且 Vault 有审计
```

至少做到：

- 所有上游 Key 在 Vault 有备份（DB 丢了能从 Vault 重建渠道）
- Vault 启用审计（谁/何时/动了哪个密钥）

## 部署 Vault

```bash
cd deploy/security/vault
docker compose -f docker-compose.vault.yml up -d
docker exec -it vault vault operator init       # 记下 5 个 unseal key + root token
docker exec -it vault vault operator unseal     # 跑 3 次（输入 3 个 unseal key）

# 启用 KV v2
docker exec -it vault vault secrets enable -version=2 -path=secret kv

# 启用审计
docker exec -it vault vault audit enable file file_path=/vault/audit/audit.log
```

**5 个 unseal key 必须分给 5 个不同的人，至少 3 人在线才能 unseal**。Root token 写到密码管理器后立即用 policy + AppRole 替代。

## 运行时拉取（新增脚本）

```bash
bash scripts/vault-export.sh openai/sk-proj-001
# 输出 sk-proj-... （拷贝到 admin 用）
```

详见 [`vault/inject-secrets.sh`](./vault/inject-secrets.sh)。
