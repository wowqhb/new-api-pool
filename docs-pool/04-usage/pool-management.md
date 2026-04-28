# 号池管理一级菜单完整说明

> 进入路径：登录后台 → 左侧菜单「号池管理」（仅管理员可见）。
> 一级菜单下挂 5 个子菜单 + 1 套通用页面壳。

---

## 1. 总览（Overview）

路径：`/console/pool/overview` · 后端：`GET /api/pool/overview` · 代码：`controller/pool.go::GetPoolOverview`

### 显示什么

```
┌────────── 顶部 4 张大卡 ──────────┐
│ 健康分      ●●●●●○  85/100      │   越绿越健康
│ 上游账号    23 个 (active 18)    │
│ 今日请求    12,450 (失败 1.2%)    │
│ 今日毛利    $42.30 USD           │   = 用户消耗 - 上游成本
└────────────────────────────────┘

┌────────── 中间 2 张分组卡 ──────┐
│ 已启用渠道  17       禁用 6      │
│ 待处理告警  3 条                  │
└────────────────────────────────┘

┌────────── 底部分组实况表 ──────┐
│ Provider │ 账号数 │ 今日请求 │ 今日成本 │
│ openai   │   3    │  4,200  │ $12.50  │
│ gemini   │   8    │  6,100  │ $0.00   │（免费）
│ ...                                     │
└─────────────────────────────────────────┘
```

### 健康分怎么算

代码 `GetPoolOverview`：
- 起 100 分
- 70 分由 `active/total 账号比` 决定
- 30 分由 `今日失败率` 反向决定
- 渠道禁用率扣最多 10 分
- 无任何账号时基准 60，无任何请求时不扣

### 今日毛利怎么算
- `今日消耗 USD = SUM(logs.quota where today and type=consume) / QuotaPerUnit`
- `今日上游成本 = 今日消耗 × PoolUpstreamCostRatio`（默认 0.6，可在 options 表改）
- `毛利 = 今日消耗 - 今日成本`

> 这个数字是**估算**，不是会计意义上的实际成本。要精确：去 [收支对账](#4-收支对账billing) 页看上游账单聚合。

---

## 2. 上游账号（Accounts）

路径：`/console/pool/accounts` · 代码：`web/src/pages/Pool/Accounts.jsx` + `controller/pool.go` `GetPoolAccounts/AddPoolAccount/UpdatePoolAccount/DeletePoolAccount/BindPoolAccountChannel/GetPoolAccountFullKey`

### 列表字段

| 列 | 说明 |
|---|---|
| 名称 | 你给账号起的辨识名（同 provider 内唯一） |
| Provider | 上游标识（openai / gemini / claude / groq / ...） |
| 类型 | official / oauth / free / third |
| Key | 默认显示前 4 字符 + ... + 后 4 字符。点👁可弹「完整 Key」对话框（带复制按钮） |
| 余额 | `balance_usd`，可在巡检 / 编辑时更新 |
| 渠道 | 绑定状态：「已绑定 #N」/「一键绑定」按钮 |
| 状态 | active(绿) / warning(黄) / disabled(灰) |
| 操作 | 编辑 / 删除 |

### 新增上游账号 Modal

字段：

| 字段 | 含义 |
|---|---|
| 名称 (必填) | 同 provider 内唯一 |
| Provider (必填) | 下拉：OpenAI / Anthropic / Gemini / DeepSeek / SiliconFlow / ... |
| 类型 | official / oauth / free / third |
| Key (必填) | 完整明文 Key，提交后只存 mask + 关联到 channel.key |
| Group | 默认 `default`；填多组时 channel.group 会写 `default,xxx,yyy` |
| 余额 / 备注 | 可选 |
| 自动建渠道 ✓ | 推荐勾上：保存时自动建一个对应 type 的 channel.tag=`pool` |
| Channel Type / BaseURL | 勾上"自动建渠道"才需填 |

提交后做了什么（详见 `controller.AddPoolAccount`）：
1. 写 `pool_accounts`，`KeyMasked = sk-xxx...xxxx`，`KeyRaw` 不入库（隐去）。
2. 如果勾了"自动建渠道"：
   - 找一个匹配 `Recipe.Provider = provider` 的 Recipe → 用它的 `DefaultModels` 填 `channel.Models`。
   - `channel.Group` = `"default," + groupName`（保证 default 组用户能命中）。
   - `ch.Insert()` 自动写 `abilities` 表。
   - `pool_accounts.ChannelId` 回填。

### 编辑

打开 Modal 会**回显所有字段**（含原始 KeyRaw 通过 `GET /api/pool/accounts/:id/full_key` 单独获取）。改 KeyRaw 会自动同步到关联的 `channels.key`。

### 一键绑定

`BindPoolAccountChannel` 流程：
1. 没参数 → 自动按 `provider` 找一个未绑定的同 provider channel；找不到就建一个。
2. 带 `channel_id` → 绑定到指定 channel。
3. 双向写：`pool_accounts.ChannelId = X`、`channels.key = pool_accounts.KeyRaw`、`channels.tag = "pool"`。

UI 上未绑定状态显示「一键绑定」按钮，已绑定显示「已绑定 #N」（点开能跳到原生渠道详情）。

---

## 3. 自动注册（Recipes & Jobs）

路径：`/console/pool/recipes` · 代码：`Recipes.jsx` + `controller/pool.go` `GetPoolRecipes/UpdatePoolRecipe/EnqueuePoolRecipe/ManualSubmitJobResult/CancelPoolJob/RetryPoolJob`

页面有 3 个 tab：

### 3.1 剧本（Recipes）tab

每行一个内置或用户加的 Recipe。重要字段：
- ⭐ 标识：推荐首选（5 分钟内能拿到 Key）
- Provider：分组用
- Difficulty：easy / medium / hard
- IPRequirement：any / residential / specific_country
- AutomationCapability：full / sms_paid / oauth_only / realname_only / manual
- Enabled：用户必须 enable 才能入队
- ManualMode：true=半自动（默认），false=全自动（需 Runner）
- Success / Failure：累计计数

操作：
- 编辑：所有字段可改（注意改完 ManualMode/WebhookURL 会被 `upsertPoolRecipe` 保护，不会被下次 Seed 覆盖）。
- 入队 Run：调 `EnqueuePoolRecipe`，根据 ManualMode 创建 `manual_pending` 或 `pending` 任务。
- 查看步骤：弹 ManualSteps + RequiredMaterials + DocURL。

### 3.2 任务（Jobs）tab

显示所有 PoolJob 历史，按状态过滤：
- pending / manual_pending：等处理
- running：worker 正在跑
- success / failed / cancelled：完结

每条任务的操作：
- 录入结果（仅 manual_pending）：弹 Modal 填 `pool_account_name + key_raw`，调 `ManualSubmitJobResult`。
- 取消：`CancelPoolJob`，写 `cancelled` 状态。
- 重试：`RetryPoolJob`，把 status 重置为 pending。
- 查看错误：失败任务展开 `error_msg`。

### 3.3 自动化设置 tab

存在 `options` 表，启动时由 `SeedDefaultAutomationConfig` 写入默认值：

| Key | 默认 | 含义 |
|---|---|---|
| `PoolEmailProvider` | `mailtm` | 一次性邮箱（mailtm / guerrilla / 1secmail） |
| `PoolSmsProvider` | `5sim` | 接码服务（5sim / smsactivate / mock） |
| `PoolFivesimApiKey` | 用户提供的 JWT | 5sim Bearer JWT |
| `PoolSmsActivateApiKey` | 用户提供的 deprecated key | sms-activate 旧版 API Key |
| `PoolWorkerMaxConcurrent` | 2 | worker 同时处理的最大 Job 数 |
| `PoolUpstreamCostRatio` | 0.6 | 总览页毛利估算系数 |

修改后立即热生效（`common.OptionMap` 周期性同步）。

---

## 4. 收支对账（Billing）

路径：`/console/pool/billing` · 代码：`Billing.jsx` + `GetPoolBillingSummary`

显示窗口：默认最近 7 天，可切到 30 / 自定义。

### 收入（Income）
- 来自 `topups` 表，仅 `status='success'`。按天分组求 `SUM(amount)`。

### 上游成本（Cost）
- `logs.quota` (type=consume) 求和 / `QuotaPerUnit` × `PoolUpstreamCostRatio`。
- 这是**粗估**：因为没接入上游真实账单 API（GPT 用 tiktoken 估算成本，Claude 同理；Gemini Free 实际为 0）。

### 毛利（Profit）
- `毛利 = 收入 - 成本`
- 折线图：日维度 + 7 天滚动均值

### 分组毛利
- 按 `channel.group` 拆分，看哪个上游"亏本"。
- 实战例子：发现 Claude 渠道毛利率为负 → 调高 model_ratio / 关闭这渠道 / 换上游。

---

## 5. 巡检告警（Alerts）

路径：`/console/pool/alerts` · 代码：`Alerts.jsx` + `controller/pool.go` `GetPoolAlerts/TriggerPoolHealthCheck/ResolvePoolAlert/GetPoolTelegramConfig/SetPoolTelegramConfig/TestPoolTelegram`

### 5.1 告警历史
- 来自 `pool_alert_history` 表。
- 字段：rule_key / severity / title / message / target_type / target_id / resolved。
- 支持过滤：severity (info/warning/critical) + resolved (是/否/全部)。
- 点「已处理」调 `ResolvePoolAlert`，写 `resolved=true + resolved_at`。

### 5.2 巡检规则
当前内置在 `service/pool_health.go::checkOnce`：
- `channel_down`：渠道连续失败率 > 50% 且总样本 ≥ 10
- `channel_disabled`：自动健康检查把渠道置为 disabled
- `balance_low`：上游账号 balance_usd < 阈值（默认 5）
- `pool_account_expire`：90% 配额耗尽 / `expire_at` 临近 7 天
- `system_health`：DB 连接异常 / Redis 宕机（如启用）

每 5 分钟一次（`StartPoolHealthCron`）。命中 → 写 `pool_alert_history` + 推 Telegram。

### 5.3 立即巡检
点页面顶部「立即巡检」按钮 → `POST /api/pool/alerts/run` → 同步跑一次 checkOnce。

### 5.4 Telegram 通道
表单：
- Bot Token（默认已 seed）
- Chat Id（默认已 seed）
- 「保存」→ 写 `options` 表 `PoolTelegramBotToken` / `PoolTelegramChatId`
- 「测试发送」→ `POST /api/pool/alerts/telegram/test` → 实际打 `https://api.telegram.org/bot<TOKEN>/sendMessage`，错误会带具体 API 返回（"chat not found" 等）。

### 5.5 告警消息长什么样
```
🚨 [warning] 渠道连续失败
渠道 #5 [type=24 gemini-personal-1]
最近 30 个请求，失败率 67% (20/30)
失败原因：API key not valid

时间：2026-04-28 12:35:11
查看：http://localhost:3000/console/channel
```

---

## 6. 共用页面壳（Layout）

文件：`web/src/pages/Pool/Layout.jsx`。

每个 Pool 子页面用 `<PoolPageLayout title=... subtitle=... badge=... extra=...>` 包一层，统一：
- 顶部留 60px（避开 new-api 顶栏）
- 标题 + Tag + 副标题
- 右上角 extra 放刷新 / 添加按钮

新加 Pool 子页面建议直接用这个 Layout，视觉就对齐。
