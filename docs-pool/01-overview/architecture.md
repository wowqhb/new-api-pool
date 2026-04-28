# 系统架构总览

## 1. 三层视角

```
┌──────────────────────────────────────────────────────────────────────┐
│                        终端用户 / 第三方应用                            │
│   curl / Cherry Studio / NextChat / OpenAI SDK / Anthropic SDK 等       │
└────────────────────────────┬─────────────────────────────────────────┘
                             │   OpenAI / Anthropic / Gemini 兼容路径
                             │   (chat.completions, messages, embeddings, ...)
                             ▼
┌──────────────────────────────────────────────────────────────────────┐
│                     ┌──────────  new-api  ──────────┐                 │
│                     │  Gin (Go)  +  React (Semi UI) │                 │
│  鉴权 / 计费 / 限速 │  /api/pool/*    /api/relay/*  │  渠道路由 / 转发 │
│                     └──────────────┬────────────────┘                 │
│                                    │                                   │
│   ┌──────────┐    ┌────────┐    ┌──┴────────┐    ┌────────┐           │
│   │ Channels │←──→│Abilities│   │  Tokens   │    │ Users  │           │
│   └────┬─────┘    └─────────┘   └───────────┘    └────────┘           │
│        │ 弱关联                                                         │
│        ▼                                                                │
│   ┌──────────────┐  ┌────────────┐  ┌──────────┐  ┌──────────┐        │
│   │ PoolAccounts │  │ PoolRecipes│  │ PoolJobs │  │PoolAlerts│        │
│   └──────────────┘  └────────────┘  └──────────┘  └──────────┘        │
│                          号池管理（fork 新增）                           │
└────────────────────────────┬─────────────────────────────────────────┘
                             │
                             ▼
┌──────────────────────────────────────────────────────────────────────┐
│                          上游 LLM / 服务商                              │
│   OpenAI · Anthropic · Google AI Studio · Groq · Cerebras · DeepSeek  │
│   SiliconFlow · Moonshot · 智谱 · Vertex AI · OpenRouter · ...        │
└──────────────────────────────────────────────────────────────────────┘
```

3 层职责：

1. **流量入口（new-api 核心）**——OpenAI / Anthropic / Gemini 等兼容协议接收，鉴权、计费、限速、流式转发，是这个系统的"AI 网关"。
2. **号池管理（本 fork 的核心改动）**——把过去散落在 Excel / 邮箱 / 截图里的"上游账号采购台账"做进系统：账号入库、人工/半自动注册、巡检、对账、Telegram 告警，与渠道（Channels）双向关联。
3. **上游接入**——所有外部服务商通过 `Channels.Type + BaseURL + Key` 抽象，路由表 `Abilities` 动态命中。

## 2. 进程与代码结构

```
new-api 进程（单 binary）
├── main.go           启动入口
│   ├── InitResources()              ← 数据库 / Redis / i18n / OAuth
│   ├── model.CheckSetup()           ← AutoMigrate 所有表 + Seed 默认数据
│   ├── controller.AutomaticallyTestChannels()    ← 渠道自检
│   ├── service.StartCodexCredentialAutoRefreshTask()  ← Codex token 自动刷新
│   ├── service.StartPoolHealthCron()      ← 【号池】健康巡检 cron（5min）
│   ├── service.StartPoolWorker()          ← 【号池】Job 队列 worker
│   └── server.Run(:port)
│
├── router/           路由分组
│   ├── api-router.go         /api/*       管理 / 用户接口
│   ├── relay-router.go       /v1/*        OpenAI 兼容
│   ├── video-router.go       /api/video/* 视频生成（如启用）
│   └── pool-router.go        /api/pool/*  ★ 号池管理（本 fork 新增）
│
├── controller/       业务逻辑层
│   ├── channel.go / token.go / user.go ...   原 new-api
│   └── pool.go              ★ 号池所有 endpoints（约 1244 行）
│
├── service/          后台服务 / 第三方集成
│   ├── pool_worker.go       Job 调度 / Runner 派遣 / 自动建渠道
│   ├── pool_runners.go      RecipeRunner 接口 + 注册表
│   ├── pool_email.go        EmailProvider 抽象（mailtm / guerrilla / 1secmail）
│   ├── pool_mailtm.go       mail.tm 客户端
│   ├── pool_sms.go          SmsProvider 抽象（5sim / sms-activate / mock）
│   └── pool_health.go       巡检 + Telegram 推送
│
├── model/            ORM 模型 + 迁移 + Seed
│   ├── channel.go / token.go / user.go / option.go ... 原 new-api
│   ├── pool_account.go      ★ 上游账号
│   ├── pool_recipe.go       ★ Recipe + Job + 默认 Seed（≈19 个内置剧本）
│   └── pool_alert.go        ★ 告警历史
│
└── web/              前端（React + Vite + Semi UI）
    └── src/pages/Pool/      ★ 号池一级菜单 6 个子页
        ├── Layout.jsx       共用页面壳
        ├── Overview.jsx     总览
        ├── Accounts.jsx     上游账号
        ├── Recipes.jsx      自动注册（Recipe + Job）
        ├── Billing.jsx      收支对账
        └── Alerts.jsx       巡检告警 + Telegram 配置
```

## 3. 关键数据流

### 3.1 用户调用一次 OpenAI 兼容接口的全链路

```
client (sk-xxx 用户 token)
    │  POST /v1/chat/completions
    ▼
middleware/token-auth   → 查 tokens 表，验签 / 限速 / 计费上限
    │
    ▼
relay router (按 model 找渠道)
    │
    ▼
abilities 表查询：model = "gemini-2.5-flash" AND group ∈ ("default") AND status=enabled
    │  → 选中 channel_id（含权重 / 优先级）
    ▼
channels 表取出 base_url + key + type
    │
    ▼
relay/<provider>/adaptor.go   → 协议转换（OpenAI ↔ Anthropic ↔ Gemini）
    │
    ▼
HTTP → 上游服务商（generativelanguage.googleapis.com 等）
    │
    ▼
流式 SSE / 一次性 JSON 回写客户端
    │
    ▼
异步：写 logs、扣 quota、累加 channel.used_quota
```

`abilities` 是核心索引表，由 `Channel.Insert()` 自动维护——这个细节非常重要，详见 [routing-abilities.md](../05-architecture/routing-abilities.md)。

### 3.2 号池注册一个上游账号的全链路

```
管理员 → 后台「自动注册」页 → 点剧本「⭐ Google AI Studio (免费 Gemini)」→ 入队
    │
    ▼
controller.EnqueuePoolRecipe
    │  写入 pool_jobs（status=manual_pending / pending）
    ▼
                    ┌────────────────────────────┐
                    │   Recipe.ManualMode ?      │
                    └────────┬───────────────────┘
                  yes (默认) │      │ no
              ┌──────────────┘      └─────────────────────────────┐
              ▼                                                    ▼
     pool_jobs.status =                                    service.StartPoolWorker
         manual_pending                                    每 8s 扫一次 pending
              │                                                    │
              ▼                                                    ▼
     UI 在 Recipes 页弹出                                    GetRunner(recipe.Key)
     操作步骤 + DocURL + 必备材料                                  │
              │                                                    ▼
              │ 用户线下花 3-10 分钟操作                     RecipeRunner.Run
              │ 拿到上游 Key                              （chromedp + mail.tm + 5sim）
              ▼                                                    │
     UI 点「录入结果」粘贴 Key                                       ▼
              │                                              成功返回 KeyRaw
              │                                                    │
              └─────────────────┬──────────────────────────────────┘
                                ▼
                      controller / worker 共用收尾：
                        1) pool_accounts 写入（KeyMasked + ChannelId=0）
                        2) 若 Recipe.ChannelType > 0：
                           channel := &Channel{Type, Key, Models=DefaultModels,
                                               Group="default,<provider>", Tag="pool-auto"/"pool-manual"}
                           channel.Insert()    ← 关键：自动写 abilities 表
                           pool_account.ChannelId = channel.Id
                        3) pool_jobs.status = success
                        4) 计数器 +1
```

完整管线代码：[`service/pool_worker.go`](../../service/pool_worker.go) + [`controller/pool.go`](../../controller/pool.go) `ManualSubmitJobResult`。

> **注**：本仓库 v2.0 起**不内置任何 chromedp 自动 Runner**——主流商业站点（OpenAI / Anthropic / OpenRouter / Cohere / Mistral / Together / xAI）实测全部部署 Cloudflare Turnstile + 设备指纹，自动化必败。所有 19 个内置 Recipe 默认 `ManualMode=true`，走半自动流程。详见 [decisions.md](../05-architecture/decisions.md) ADR-0002。

## 4. 部署形态

| 形态 | 适用 | 启动方式 |
|---|---|---|
| **本机单 binary** | 个人 / 内测 / 当前主力 | 双击 `start.command` |
| **生产 Compose** | 公开运营 | 见 [deploy/docker-compose.prod.yml](../../deploy/docker-compose.prod.yml) |
| **多区域 + HA** | P3+ 阶段 | 见 [deploy/multi-region/](../../deploy/multi-region/) |

本机单 binary 已自带：Web UI、API、号池 cron、号池 worker、健康巡检、Telegram 告警——一台 macOS / Linux 就能跑完整业务，**无需 Postgres / Redis / Docker**（SQLite 撑 ≤ 50 用户没问题）。

## 5. 关键外部依赖

| 依赖 | 用途 | 是否必须 | 配置位置 |
|---|---|---|---|
| 上游 LLM 厂商 API Key | 实际推理 | 必须 | 渠道管理 / 号池账号 |
| Telegram Bot Token | 巡检告警推送 | 推荐 | 巡检告警 → Telegram 通道（已默认） |
| mail.tm | 一次性邮箱（自动注册时用） | 可选 | 号池 → 自动化设置 |
| 5sim.net | 接码（自动注册时用） | 可选 | 号池 → 自动化设置（默认 JWT 已写入） |
| sms-activate.io | 接码备用 | 可选 | 同上 |

## 6. 跟原 new-api 的差别

| 点 | 原 new-api | 本 fork |
|---|---|---|
| 一级菜单 | 控制台 / 渠道 / 令牌 / 日志 / 用户 等 | **+ 号池管理**（6 子菜单） |
| 表 | channels / tokens / users / logs / options / ... | **+ pool_accounts / pool_recipes / pool_jobs / pool_alert_history** |
| 后台 cron | 渠道自检 / Codex token 刷新 | **+ 号池健康巡检 / 号池 worker 队列** |
| 路由 | `/api/...` `/v1/...` | **+ `/api/pool/*`**（22 个 endpoints） |
| 前端 | 现有页面 | **+ `web/src/pages/Pool/`**（5 个 .jsx + 1 个 Layout） |
| 自动化运行体 | 无 | **+ EmailProvider / SmsProvider / RecipeRunner 接口**（runner 注册表当前为空） |

更详细对比：[05-architecture/decisions.md](../05-architecture/decisions.md)。
