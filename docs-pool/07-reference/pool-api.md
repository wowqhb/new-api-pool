# 号池 API 参考（`/api/pool/*`）

> 后台「号池管理」每个按钮 / 表单背后调用的接口都在这里。
> 路由源代码：[`router/pool-router.go`](../../router/pool-router.go)
> 实现：[`controller/pool.go`](../../controller/pool.go)

---

## 通用约定

| 项目 | 值 |
|---|---|
| **Base URL** | `http://<host>:<port>` （默认 `http://localhost:3000`） |
| **认证** | 全部接口要管理员鉴权（`AdminAuth` 中间件），唯一例外 `POST /api/pool/jobs/:id/callback` 用 query token |
| **认证头** | `Authorization: Bearer <ACCESS_TOKEN>`<br>access_token 从「设置 → 个人设置 → 复制系统访问令牌」拿 |
| **响应包装** | 统一 `{"success":true,"message":"","data":{...}}` 或 `{"success":false,"message":"错误描述"}` |
| **分页参数** | `?p=1&page_size=20`（部分接口） |

---

## 1. 总览

### `GET /api/pool/overview`
首页大盘数据。

**Response.data**
```json
{
  "health_score": 92,
  "active_account_count": 14,
  "open_alert_count": 0,
  "today_revenue": "10.20",
  "today_consume_usd": "3.5421",
  "today_upstream_cost": "1.0626",
  "today_profit_usd": "2.4795",
  "by_provider": [
    {"provider":"gemini","count":3,"balance_usd":"0.0000"},
    {"provider":"openai","count":2,"balance_usd":"15.2300"}
  ],
  "telegram_set": true,
  "worker": {"running": true, "max_concurrent": 2, "inflight": 0, "runner_keys": []}
}
```

---

## 2. 上游账号（Pool Accounts）

### `GET /api/pool/accounts`
**Query**：`p`，`page_size`，`provider`（可选过滤）。

**Response.data.items**：每条 PoolAccount，`key_masked`（脱敏 Key）。

### `GET /api/pool/accounts/:id`
单条账号详情。

### `POST /api/pool/accounts`
新增账号。

**Body**
```json
{
  "name": "我的 Gemini #1",
  "provider": "gemini",                 // 必填
  "account_type": "official",           // official|oauth|third_party|free
  "status": 1,                          // 1=active 2=disabled 3=banned
  "key_raw": "AIza...",                 // 写库时只存脱敏
  "balance_usd": 0,
  "expire_at": 0,
  "channel_id": 0,                      // 已有 channel 直接绑
  "group_name": "",                     // 默认 = provider
  "notes": "",

  // 自动建渠道（推荐）
  "auto_create_channel": true,
  "channel_type": 25,                   // 25=Gemini，详见 [05-architecture/data-model.md](../05-architecture/data-model.md#channel-type-mapping)
  "channel_base_url": ""
}
```

**Response.data**：新建的 PoolAccount。

### `PUT /api/pool/accounts/:id`
更新账号。`key_raw` 改了会同步更新关联 `Channel.Key`。

### `DELETE /api/pool/accounts/:id`
软删（`gorm.DeletedAt`）。**不会删关联 Channel**——如要彻底删请到「渠道管理」单独删。

### `GET /api/pool/accounts/:id/full_key`
拿明文 Key（前端「复制完整 Key」按钮）。

**Response.data**
```json
{
  "channel_id": 41,
  "channel_name": "我的 Gemini #1",
  "channel_type": 25,
  "channel_base_url": "",
  "key": "AIza...完整明文..."
}
```

> ⚠️ 仅管理员可见，不要把这个 endpoint 响应在前端 console 里 log 出来；不要在网关开 access log 包含 response body。

### `POST /api/pool/accounts/:id/bind`
一键绑定到一个 Channel（或自动匹配）。

**Body**（任一）
```json
{}                                      // 自动按 PoolAccount.name 匹配 channels.name
{ "channel_id": 41 }                   // 强制绑到指定 channel
```

**Response 三种**：
- `{"bound":true, "channel_id":N, ...}`：直接绑成功
- `{"bound":false, "candidates":[...], "hint":"命中多个渠道"}`：前端弹选择器
- `error`：未找到候选

---

## 3. Recipes（自动注册剧本）

### `GET /api/pool/recipes`
列出所有 Recipe（含 `manual_steps` / `required_materials` / `default_models` / `success_count`/`failure_count`）。

### `PUT /api/pool/recipes/:id`
更新 Recipe（`manual_mode`、`enabled`、`webhook_url`、`difficulty`、`channel_type`、`default_models` 等）。

### `POST /api/pool/recipes/:key/enqueue`
提交一次注册任务。

**Body**：可选 `params`（任意 JSON 透传给 runner 或人工操作步骤）。

**Response（manual_mode=true）**
```json
{
  "job_id": 42,
  "mode": "manual",
  "status": "manual_pending",
  "manual_steps": "...步骤文本...",
  "required": "邮箱/手机号/护照",
  "doc_url": "https://...",
  "output_format": "申请通过后从 Dashboard → API Keys 复制 sk-..."
}
```

**Response（manual_mode=false 且有内部 Runner）**
```json
{ "job_id": 42, "mode": "auto-internal", "queued": true }
```

**Response（manual_mode=false + 无 Runner + 配了 webhook）**
```json
{ "job_id": 42, "mode": "auto-webhook", "queued": true }
```

> 当前 fork **不内置任何商业站点的内部 Runner**（[ADR-0002](../05-architecture/decisions.md#adr-0002删除所有-chromedp-自动-runner)）。所有内置 Recipe 默认 `manual_mode=true`。

### `POST /api/pool/jobs/:id/manual-result`
人工注册完成 → 录入结果。

**Body**
```json
{
  "account_name": "Cerebras Free Tier #1",
  "key_raw": "csk-XXX",
  "balance_usd": 0,
  "expire_at": 0,
  "notes": "免费额度，每分钟 10 RPM",
  "create_channel": true,
  "group_name": ""                       // 留空 = "default"
}
```

**Response**
```json
{
  "pool_account_id": 27,
  "channel_id": 53,
  "job_status": "success"
}
```

### `POST /api/pool/jobs/:id/cancel`
取消未跑完的 Job。

### `POST /api/pool/jobs/:id/retry`
基于旧 Job 的 `recipe_key` + `params_json` 创建新 Job（按 Recipe 当前的 `manual_mode` 决定走哪条路径）。

### `GET /api/pool/worker/status`
**Response.data**
```json
{ "running": true, "max_concurrent": 2, "inflight": 0, "runner_keys": [] }
```

`runner_keys` = 已注册的内部 Runner（`service.RegisterRunner` 列表）。fork 默认空数组。

### `GET /api/pool/automation/config`
**Response.data**
```json
{
  "email_providers": ["mailtm","manual"],
  "sms_providers":   ["5sim","mock"],
  "runner_keys":     [],
  "current": {
    "PoolEmailProvider":     "mailtm",
    "PoolSmsProvider":       "5sim",
    "PoolSmsActivateApiKey": "****1234",
    "PoolFivesimApiKey":     "****abcd"
  },
  "sms_balance_usd": 12.34,
  "sms_balance_unit": "RUB",
  "sms_provider": "5sim"
}
```

### `PUT /api/pool/automation/config`
**Body**：四个字段都是 `*string`，**不传 = 不改**，传 `[unchanged]` = 不改（前端展示掩码时用）。

```json
{
  "PoolEmailProvider":     "mailtm",
  "PoolSmsProvider":       "5sim",
  "PoolSmsActivateApiKey": "新值",
  "PoolFivesimApiKey":     "[unchanged]"
}
```

---

## 4. Billing（收支对账）

### `GET /api/pool/billing/summary`
**Query**：`period=today|7d|30d`。

**Response.data**
```json
{
  "period": "today",
  "start_ts": 1714233600,
  "revenue":        "10.20",
  "consume_usd":    "3.5421",
  "upstream_cost":  "1.0626",
  "gross_profit":   "2.4795",
  "margin_percent": "70.00",
  "upstream_ratio": 0.3,
  "by_model":  [{"model":"gemini-2.5-flash","requests":1234,"consume_usd":"0.4321"}, ...],
  "by_group":  [{"group":"default","requests":120,"consume_usd":"...", "upstream_usd":"...", "profit_usd":"..."}, ...]
}
```

`upstream_ratio` 默认 `0.3`，可通过 option 表 `PoolBillingUpstreamRatio` 改（**全局默认上游成本占比 = 30%**，业务自己估算）。

---

## 5. Alerts（巡检告警）

### `GET /api/pool/alerts`
**Query**：`severity` / `resolved` / 分页。

**Response.data**
```json
{
  "history":     {"items":[...], "total":15, ...},
  "open_count":  0,
  "telegram_set": true
}
```

### `POST /api/pool/alerts/run`
立即跑一次健康巡检。返回 `{"started": true}`，**异步**执行，结果落到 `pool_alert_history`。

### `POST /api/pool/alerts/:id/resolve`
人工标记一条告警已解决。

### `GET /api/pool/alerts/telegram`
**Response.data**
```json
{
  "token_masked": "874989...arMg",
  "chat_id": "-1001234567890",
  "enabled": true
}
```

### `PUT /api/pool/alerts/telegram`
**Body**
```json
{
  "token": "新 token；空字符串 = 不改",
  "chat_id": "-1001234567890"
}
```

### `POST /api/pool/alerts/telegram/test`
发一条测试消息到当前配置。

---

## 6. 外部 Worker 回调

### `POST /api/pool/jobs/:id/callback?token=<shared_secret>`
**仅给外部 worker 用**。当前 fork 没有内置 worker，但接口保留。

**Auth**：query token 与 option `PoolWorkerSharedToken` 相等。

**Body**
```json
{
  "status": "success",                  // success | failed | running
  "result_json": "{...}",               // 业务自定义
  "error_msg":   ""
}
```

成功会 `pool_recipes.success_count + 1`，失败 `failure_count + 1`。

---

## 错误码参考

| 场景 | message 例子 |
|---|---|
| 缺必填字段 | `"账号名称不能为空"` `"account_name 和 key_raw 不能为空"` |
| 找不到资源 | `"未找到 Recipe: foo"` `"未找到关联渠道 #N"` |
| 状态不允许 | `"该任务状态非 manual_pending，无法手动回填"` `"任务已结束"` |
| Recipe 配置不全 | `"该 Recipe 自动模式无法运行：未注册内部 Runner，也未配 Webhook URL..."` |
| 未配 Telegram | `"Telegram 未配置"` |
| 自动建渠道失败 | `"自动创建渠道失败: ...."` |
| 鉴权失败 | `"无权限"` / 401 |

---

## 调用示例（curl）

完整端到端：用 Recipe 注册 → 录结果 → 调上游：

```bash
TOKEN="你的 access_token"
BASE="http://localhost:3000"

# 1. 入队 deepseek（manual_mode=true）
JOB_ID=$(curl -s -X POST "$BASE/api/pool/recipes/deepseek-direct/enqueue" \
   -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
   -d '{}' | jq -r '.data.job_id')
echo "job_id=$JOB_ID"

# 2. 线下注册 → 拿到 key sk-xxx，回填
curl -X POST "$BASE/api/pool/jobs/$JOB_ID/manual-result" \
  -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  -d '{
    "account_name":"DeepSeek 自购 #1",
    "key_raw":"sk-deepseek-xxx",
    "balance_usd": 5,
    "create_channel": true,
    "group_name":"deepseek"
  }'

# 3. 立即用，注意 model 名要在 channel.models 里有
curl "$BASE/v1/chat/completions" \
  -H "Authorization: Bearer <用户访问令牌>" \
  -H "Content-Type: application/json" \
  -d '{"model":"deepseek-chat","messages":[{"role":"user","content":"hello"}]}'
```

---

## 字段持久化映射

| API 字段 | 数据库字段 | 说明 |
|---|---|---|
| `key_raw`（仅请求） | `pool_accounts.key_masked` + `channels.key` | API 不回写 raw，落库时拆两份 |
| `provider` | `pool_accounts.provider`（不变） | |
| `account_type` | `pool_accounts.account_type` | enum：`official` / `oauth` / `third_party` / `free` |
| `status` (PoolAccount) | `pool_accounts.status` | int：1=active 2=disabled 3=banned |
| `status` (Channel) | `channels.status` | int：1=enabled 2=manually_disabled 3=auto_disabled |
| `group_name` | `pool_accounts.group_name` + `channels.group` | channels.group = `"default,<group_name>"` |
| `default_models` | `channels.models` | 自动建渠道时来自 `recipes.default_models` |

详细表结构见 [`05-architecture/data-model.md`](../05-architecture/data-model.md)。
