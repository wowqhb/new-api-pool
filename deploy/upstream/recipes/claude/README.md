# Claude OAuth Recipe（半自动）

## 重要约束

- **绑卡环节风控太重**，不要尝试全自动绑卡。流程明确分两段：
  1. 自动：邮箱注册 + 抓 magic link + 登录
  2. 人工：进浏览器（headless=False）完成绑卡 + Pro 订阅
  3. 自动：抓 OAuth token + 入池

## 两种模式

### `mode=full`：完整流程

```bash
docker compose -f docker-compose.upstream.yml exec orchestrator \
    python -m orchestrator.cli submit claude --payload '{"mode":"full"}'
```

worker 会停在"等绑卡"，浏览器会保持打开（headless=False）。完成后跑：

```bash
# 通知 worker 继续
docker compose -f docker-compose.upstream.yml exec upstream-postgres \
    psql -U upstream -d upstream -c \
    "UPDATE tasks SET payload = payload || '{\"manual_done\":true}'::jsonb WHERE id = <task_id>"
```

### `mode=oauth_capture`：现成账号

如果你已经有 Pro 账号（手动注册+绑卡完成），直接抓 token 入池：

```bash
docker compose -f docker-compose.upstream.yml exec orchestrator \
    python -m orchestrator.cli submit claude --payload '{"mode":"oauth_capture","email":"x@y.com"}'
```

## OAuth 字段位置

Claude 用 Auth0：
- `localStorage["@@auth0/auth0:default"]` 包含 access/refresh token JSON
- `claude.ai` cookie `sessionKey` 用于 magic link 流程登录态

我们抓的是 `access_token` 写到渠道的 `key`，`refresh_token` 写到 `other`。

## Token 刷新

access_token 大约 8h 过期。`oauth_refresh.py` cron：

```cron
0 */4 * * * docker compose -f docker-compose.upstream.yml exec orchestrator \
    python -m recipes.claude.oauth_refresh
```

刷新逻辑：
1. 查 `accounts` 表所有 `recipe='claude' AND status='active'`
2. 用 refresh_token 调 `https://console.anthropic.com/v1/oauth/token`
3. 写回 DB + 更新 new-api channel.key

## 失败处理

| 现象 | 处理 |
|---|---|
| refresh token 失效（401） | 标记 status=dead；该号需要人工重绑 |
| 5h 窗口耗尽（429） | 不刷 token，等窗口刷新；priority 临时降到 50 |
| Pro 订阅被取消 | 自动检测 `subscription_status`，status=quarantine |

## 风险提示

⚠️ Anthropic ToS 明确禁止"代理/二次售卖"个人账号。规模化用 OAuth 池属于灰色地带，
**小规模自用 OK，对外售卖前请咨询律师**。
