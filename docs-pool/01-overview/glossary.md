# 术语表

按字母 / 拼音排序。代码 / 后台 UI / 文档使用同一组术语，避免歧义。

| 术语 | 英文 / 字段 | 含义 |
|---|---|---|
| **一级菜单** | Sidebar Group | 后台左侧栏的可折叠分组（如「号池管理」），下挂多个二级菜单 |
| **二级菜单** | Sidebar Item | 实际跳路由的页面入口（如「上游账号」→ `/console/pool/accounts`） |
| **号池** | Pool | 上游账号台账系统的统称；后台一级菜单名 |
| **上游账号** | PoolAccount | 在 `pool_accounts` 表里的一条记录，对应一个外部服务商账号 / Key |
| **渠道** | Channel | new-api 原生概念，对应 `channels` 表，是真正承载流量转发的"路由槽" |
| **Channel 类型** | Channel.Type (int) | new-api 内置的整数枚举：1=OpenAI、14=Anthropic、24=Gemini、43=DeepSeek 等等 |
| **能力** | Ability | `abilities` 表，由 `(group, model, channel_id)` 三元组组成的路由命中索引；`Channel.Insert()` 时自动写入 |
| **分组** | Group | `Channel.Group` / `Token.Group`，路由命中条件之一；本 fork 自动建渠道时使用 `"default,<provider>"` 双值，确保默认组也能命中 |
| **Recipe** | PoolRecipe | "注册剧本"——一份给特定上游服务商写的注册指引（DocURL / 必备材料 / 操作步骤 / 自动建渠道参数）；存 `pool_recipes` 表 |
| **Job** | PoolJob | 一次"按某个 Recipe 跑注册"的任务实例；存 `pool_jobs` 表，状态机见下 |
| **半自动模式** | Recipe.ManualMode = true | 系统只跟踪流程，由用户线下完成上游注册并把 Key 回填到后台 |
| **自动模式** | Recipe.ManualMode = false | 由 `service.PoolWorker` 调用对应 `RecipeRunner` 实现 chromedp + 接码 + 邮箱接管，完成全程注册 |
| **Runner** | RecipeRunner (interface) | 一个 Recipe 的自动执行器；通过 `RegisterRunner()` 注册到全局表；本仓库 v2.0 起**未内置任何商业站点 Runner** |
| **AutomationCapability** | Recipe.AutomationCapability | 信息字段：`full` / `sms_paid` / `oauth_only` / `realname_only` / `manual`，告诉用户该上游自动化的可行性 |
| **DefaultModels** | Recipe.DefaultModels | 自动建渠道时用来填 `Channel.Models` 的逗号分隔模型列表 |
| **EmailProvider** | service.EmailProvider | 一次性邮箱抽象：mailtm（默认） / guerrilla / 1secmail |
| **SmsProvider** | service.SmsProvider | 接码服务抽象：5sim（默认，需 JWT） / sms-activate / mock |
| **巡检** | Pool Health Check | `service.StartPoolHealthCron`，默认每 5 分钟扫一遍：渠道是否报错、号池账号是否过期 / 余额低 |
| **告警** | PoolAlertHistory | 巡检命中规则后写入 `pool_alert_history` 表的一条记录；同时推 Telegram |
| **Telegram 通道** | PoolTelegramBotToken / PoolTelegramChatId | 存在 `options` 表，启动时 `SeedDefaultTelegramConfig` 写入默认值 |
| **Token / 用户令牌** | tokens 表 | new-api 原生：终端用户调用 API 用的 sk- 开头令牌；与号池里的"上游 Key"概念**不要混淆** |
| **Quota** | tokens.remain_quota | new-api 原生计费单位（500000 quota = $1）；号池侧也有 `pool_accounts.used_quota` 表征上游消耗 |
| **OptionMap** | common.OptionMap | 内存配置缓存，从 `options` 表加载；号池所有自动化配置都走这里 |
| **MasterNode** | common.IsMasterNode | 多节点部署时只有 master 跑后台 cron / worker；本机单 binary 永远是 master |
| **关键 Tag** | Channel.Tag | 标记渠道来源：`pool-auto`（worker 自动建）/ `pool-manual`（手动回填后建）/ `pool`（手动绑定） |
| **半自动入队** | EnqueuePoolRecipe | UI 操作：在 Recipes 页点剧本 → 创建 PoolJob.status=manual_pending → 等用户回填 |
| **录入结果** | ManualSubmitJobResult | UI 操作：粘贴线下拿到的 Key → 写 PoolAccount + 自动建 Channel + Job 完结 |
| **一键绑定** | BindPoolAccountChannel | UI 操作：在 Accounts 页点未绑定的账号 → 自动匹配/选/创建一个 Channel 并双向关联 |

## PoolJob 状态机

```
pending  ─┬─→ running  ─┬─→ success
          │             ├─→ failed
          │             └─→ cancelled
          ↓
   manual_pending  ──→ success / failed / cancelled
```

| 状态 | 谁会进入 | 含义 |
|---|---|---|
| `pending` | EnqueuePoolRecipe（自动模式） | worker 还没扫到 |
| `manual_pending` | EnqueuePoolRecipe（半自动） | 等用户线下操作 + 回填 |
| `running` | worker dispatch | Runner 在跑（chromedp...） |
| `success` | 完结 | 已写 PoolAccount 和 Channel |
| `failed` | 完结 | error_msg 字段记录原因 |
| `cancelled` | 用户主动取消 | UI 点取消按钮 |

## PoolAccount 状态码

| Status | 数值 | 含义 |
|---|---|---|
| Active | 1 | 正常 |
| Warning | 2 | 巡检发现异常但还能用 |
| Disabled | 3 | 停用 |

## PoolAccount 类型

| AccountType | 含义 |
|---|---|
| `official` | 官方付费 API Key（sk-...） |
| `oauth` | Claude / Codex / Gemini OAuth refresh_token |
| `free` | 免费配额（Gemini Free / Groq 等） |
| `third` | 第三方代销 Key |

## 难度 / IP / 自动化能力

| Recipe.Difficulty | Recipe.IPRequirement | Recipe.AutomationCapability |
|---|---|---|
| `easy` 5 分钟 | `any` 任意 | `full` 全自动可行 |
| `medium` 10–20 分钟 | `residential` 必须住宅 IP | `sms_paid` 需付费接码 |
| `hard` 30 分钟+ 含信用卡 | `specific_country` 指定国家 | `oauth_only` 必须 OAuth 走人工 |
|  |  | `realname_only` 必须实名 / 国内手机号 |
|  |  | `manual` 纯手动 |
