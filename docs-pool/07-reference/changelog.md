# Changelog（fork 维护视角）

> 本文档记录 fork 自 [QuantumNous/new-api](https://github.com/QuantumNous/new-api) 之后的关键变更。
> 起点：fork 时间 2026-04（基于上游 main 的某次同步）。
> 上游 new-api 自身的变更**不在此文档范围内**，参考其 [release notes](https://github.com/QuantumNous/new-api/releases)。

记号说明：
- `+` 新增
- `-` 删除
- `*` 修改
- `!` 破坏性 / 需要数据迁移
- `🐛` Bug 修复

---

## v0.5.0 — 文档化（2026-04-28）

| 类型 | 变更 |
|---|---|
| `+` | 新增 `docs/` 工程文档：8 节 / 22 篇 markdown，覆盖架构 / 开发 / 部署 / 使用 / 排错 / API / 安全 |
| `+` | ADR 决策记录：[`docs/05-architecture/decisions.md`](../05-architecture/decisions.md) 收录 10 条核心决策 |

---

## v0.4.3 — 注册自动化清理（2026-04-27）

| 类型 | 变更 |
|---|---|
| `-` | 删除 `service/pool_runner_anthropic.go` `pool_runner_openai.go` `pool_runner_mistral.go` `pool_runner_cohere.go` `pool_runner_together.go` `pool_runner_openrouter.go` `pool_runner_mock.go` `pool_runner_helpers.go` |
| `-` | 删除 `service/pool_browser.go`（chromedp 浏览器会话池） |
| `*` | `service/pool_runners.go` 注释更新：声明本仓库不再提供商业站点全自动 Runner |
| `*` | `model/pool_recipe.go::buildDefaultRecipeSeeds()`：所有商业站点 Recipe 默认 `ManualMode=true`，并加 5 条推荐 Recipe（Google AI Studio / Groq / Cerebras / DeepSeek / SiliconFlow） |
| `+` | 启动时一次性迁移：`UPDATE pool_recipes SET manual_mode=1 WHERE manual_mode=0 AND webhook_url=''` |
| `+` | `PoolRecipe.AutomationCapability` 字段（信息字段：`full`/`sms_paid`/`oauth_only`/`realname_only`/`manual`） |
| `🐛` | 删除 `chromedp` 残留进程导致 CPU 占用的隐患 |

**ADR**：[ADR-0002 删除所有 chromedp 自动 Runner](../05-architecture/decisions.md#adr-0002删除所有-chromedp-自动-runner)

---

## v0.4.2 — 路由 + 自动建渠道一致性（2026-04-26）

| 类型 | 变更 |
|---|---|
| `🐛` | **关键 bug**：所有自动 / 半自动建 channel 改用 `ch.Insert()` 而非 `model.DB.Create(ch)`。后者跳过 `AddAbilities()`，导致路由表 `abilities` 永远没有对应行，调用上游必现 `No available channel for model X under group default` |
| `*` | `controller/pool.go::AddPoolAccount` `BindPoolAccountChannel` `ManualSubmitJobResult`、`service/pool_worker.go::runJob` 全部改用 `ch.Insert()` |
| `+` | `PoolRecipe.DefaultModels`（text，逗号分隔）字段 + 19 条内置 Recipe 全部填好 |
| `*` | `channels.group` 永远写 `"default,<provider>"` 而不是 `"<provider>"`，确保 default 用户能命中 |
| `+` | `PoolAccount` 编辑改 `key_raw` 时同步更新关联 `Channel.Key`（避免改 PoolAccount 但渠道仍用旧 key 的鬼魂状态） |

**ADR**：[ADR-0004](../05-architecture/decisions.md#adr-0004recipe-加-defaultmodels-字段) / [ADR-0005](../05-architecture/decisions.md#adr-0005channel-写入必须用-chinsert不允许-dbcreatech) / [ADR-0006](../05-architecture/decisions.md#adr-0006channelgroup-用逗号双值-defaultprovider)

---

## v0.4.1 — 一键绑定 + 完整 Key 复制（2026-04-25）

| 类型 | 变更 |
|---|---|
| `+` | `GET /api/pool/accounts/:id/full_key`：管理员可拿明文 Key（用于复制） |
| `+` | `POST /api/pool/accounts/:id/bind`：自动按 name 匹配 / 多候选返回 / 强制指定 channel_id |
| `*` | 前端「上游账号」表的「渠道」列：未绑定显示「一键绑定」按钮，绑定后显示「已绑定 #N」 + Tooltip |
| `*` | 前端 Modal 编辑表单：`destroyOnClose + key={editing?.id} + initValues={editing}`，修复"编辑数据空"bug |

---

## v0.4.0 — 删除「风控规则」（2026-04-24）

| 类型 | 变更 |
|---|---|
| `!` | **数据迁移**：删除 `pool_risk_rules` 表（在 `model/main.go::AutoMigrate` 移除） |
| `-` | 删除 `controller/pool.go::Get/Add/Update/DeletePoolRiskRule` |
| `-` | 删除 `model/PoolRiskRule` 类型 + 表 |
| `-` | 删除 `web/src/pages/Pool/Risk.jsx` |
| `-` | 删除 `router/pool-router.go::/api/pool/risk*` 路由 |
| `*` | SiderBar 一级菜单 6 → 5 子菜单（总览 / 上游账号 / 自动注册 / 收支对账 / 巡检告警） |

**ADR**：[ADR-0008 删除「风控规则」二级菜单](../05-architecture/decisions.md#adr-0008删除风控规则二级菜单)

---

## v0.3.0 — 自动化基础设施（2026-04-22）

| 类型 | 变更 |
|---|---|
| `+` | `service/pool_email_provider.go`：抽象 `EmailProvider` 接口 + `mailtmProvider` 实现 |
| `+` | `service/pool_sms_provider.go`：抽象 `SmsProvider` 接口 + `fivesimProvider` 实现 |
| `+` | Option 表新增：`PoolEmailProvider` / `PoolSmsProvider` / `PoolFivesimApiKey` / `PoolSmsActivateApiKey` |
| `+` | `GET / PUT /api/pool/automation/config` |
| `+` | 前端「自动注册」页 ⚙️ 自动化设置 Modal，可配 5sim API key + 提供商选择 + 实时余额 |
| `+` | Worker 状态接口 `GET /api/pool/worker/status`：返回 inflight / max_concurrent / runner_keys |

---

## v0.2.5 — Telegram 默认值预置（2026-04-20）

| 类型 | 变更 |
|---|---|
| `+` | 启动时调 `service/SeedDefaultTelegramConfig`：默认 Bot Token + Chat Id 写入 options 表（仅在 key 不存在时） |
| `*` | `service/pool_health.go::SendTelegramMessage` 改进错误解析：`chat not found` / `Unauthorized` 直接 surface 到前端 |
| `+` | `Alerts.jsx` 错误展示更友好 |

**ADR**：[ADR-0007 Telegram 通道默认值预置](../05-architecture/decisions.md#adr-0007telegram-通道默认值预置)

---

## v0.2.0 — 号池管理 5 子菜单（2026-04-18）

| 类型 | 变更 |
|---|---|
| `+` | 一级菜单「号池管理」+ 5 子菜单（总览 / 上游账号 / 自动注册 / 收支对账 / 巡检告警 / 风控规则[v0.4.0 删除]） |
| `+` | 表：`pool_accounts` `pool_recipes` `pool_jobs` `pool_alert_history` |
| `+` | 完整后端：`controller/pool.go` `service/pool_*.go` `model/pool_*.go` `router/pool-router.go` |
| `+` | 完整前端：`web/src/pages/Pool/Overview.jsx` `Accounts.jsx` `Recipes.jsx` `Billing.jsx` `Alerts.jsx` `PoolPageLayout.jsx` |
| `*` | `web/src/components/layout/SiderBar.jsx`：`isAdmin()` 用户可见 |
| `*` | `web/src/App.jsx`：lazy 路由 `/pool/*` |

**ADR**：[ADR-0001 走 fork + 自编译路线](../05-architecture/decisions.md#adr-0001走-fork--自编译路线不走-plugin--sidecar) / [ADR-0003 一级菜单](../05-architecture/decisions.md#adr-0003号池管理作为一级菜单不走二级--浮窗)

---

## v0.1.0 — fork 起点（2026-04-15）

- fork from [QuantumNous/new-api](https://github.com/QuantumNous/new-api) main
- 编译产物 `new-api-macos`（macOS arm64）
- 数据库 `one-api.db`
- 启动脚本 `start.command`
- 默认管理员 `root` / `123456`

---

## 不会进入 changelog 的事

- 上游 new-api 自身改动
- 改注释 / 文档（除非破坏 API 形状）
- 重命名变量 / 内部重构
- 调整 lint / 格式化

---

## 升级建议

每次发布在本地建一个 git tag：

```bash
cd <REPO>
git tag v0.5.0 && git push --tags
```

数据迁移（`!` 标记）的版本要：
1. 部署前**完整备份** `one-api.db`（[`backup-restore.md`](../06-operations/backup-restore.md)）
2. 在测试库上跑一次启动 + 巡检 + 自检 API
3. 出问题立刻回滚（替换 binary + 还原 db）
