# 巡检与告警

> 这一章把"号池"运行期间会用到的**自动巡检 + Telegram 告警 + 日常自检**全部串起来。
> 默认开箱即用，前提是 Telegram 配置已经预置（见 ADR-0007）。

---

## 1. 总览

new-api 号池侧自带两条监控链路：

| 链路 | 频率 | 由谁触发 | 落地 | 默认通道 |
|---|---|---|---|---|
| **PoolHealthCheck** | 每 5 分钟（cron） + 任意时刻"立即巡检"按钮 | `service.RunPoolHealthCheck` | 写 `pool_alert_history` 表 + 推送 Telegram | Telegram Bot（可关） |
| **Channel 自动禁用** | 上游连续返回 401/402/限流 | new-api 原生 `service/check_channel.go` | 改 `channels.status` + 写 `logs` | 不主动外推（号池侧巡检会捞起） |

简单说：上游不可用 → channel 被原生机制禁用 → 5 分钟内号池巡检发现 → 推 Telegram。

---

## 2. 配置 Telegram 通道

开源版默认**不带任何 Bot Token / Chat Id**——必须自己配。三种方式（任选其一）：

### 方式 A：环境变量（推荐 CI/CD / Docker）

启动前 export 两个变量，第一次启动时 `SeedDefaultTelegramConfig` 会写入 `options` 表（仅当不存在时）：

```bash
export POOL_TELEGRAM_BOT_TOKEN=123456789:AAxxxxxxxxxxxxxxxxxxxxxxxxxxx
export POOL_TELEGRAM_CHAT_ID=-1001234567890
./new-api-macos
```

### 方式 B：后台 UI 热改

后台「号池管理 → 巡检告警 → ⚙️ Telegram 设置」直接填，立即生效。

### 方式 C：直接 SQL（不推荐）

```sql
UPDATE options SET value='123456789:AAxxx...' WHERE `key`='PoolTelegramBotToken';
UPDATE options SET value='-1001234567890'    WHERE `key`='PoolTelegramChatId';
```
改完重启服务才生效（OptionMap 在启动时一次性载入）。

### 怎么拿 Bot Token / Chat Id
1. 在 Telegram 找 [@BotFather](https://t.me/BotFather) → `/newbot` → 拿到 `<bot_id>:<secret>`
2. 把 bot 加到目标群，或私聊 bot 发任意消息
3. `curl https://api.telegram.org/bot<TOKEN>/getUpdates | jq '.result[].message.chat'` → 拿 `id`

### 测试通道
1. 进入 后台 → 号池管理 → 巡检告警
2. 右上角 Tag 显示「Telegram: 已开启」即配置生效
3. 点「发送测试消息」→ Telegram 群里收到 `✅ new-api 号池告警通道测试成功`
4. curl 等价：
   ```bash
   curl -X POST http://localhost:3000/api/pool/alerts/telegram/test \
        -H "Authorization: Bearer <root_access_token>"
   ```

### 关闭通道
- 把 `PoolTelegramChatId` 清空保存即可，bot token 留着无害。
- 也可以直接 SQL：`UPDATE options SET value='' WHERE \`key\`='PoolTelegramChatId';` 然后重启服务。

---

## 3. 巡检规则

`service/pool_health.go` 内置以下规则：

| RuleKey | 严重等级 | 触发条件 | 自愈条件 |
|---|---|---|---|
| `health_check` | info | 每次巡检完成时落 1 条"心跳"（默认关闭，避免刷屏） | / |
| `channel_down` | critical | `channels.status != 1` 的渠道里有从号池来的（tag like `pool%`） | 该 channel 重新启用 |
| `balance_low` | warning | `pool_accounts.balance_usd < 1.0` 且 `account_type='official'` | 余额 ≥ 1.0 |
| `fail_rate_high` | warning | 该渠道近 24h 失败率 > 30% 且总请求 ≥ 50 | 失败率回落 |
| `expire_soon` | warning | `pool_accounts.expire_at` 在 7 天内 | 续期或换号 |

每条规则触发都会：
1. 在 `pool_alert_history` 插一条新记录（带 `target_type`/`target_id`）。
2. 如果 Telegram 配了，发一条消息（包含 severity emoji + 标题 + 详情 + 跳转链接）。
3. **同一目标 + 同一规则 24h 内只发一次**（去重在 `pool_health.go::dedupAlert` 里）。

### 手动触发巡检
后台「号池管理 → 巡检告警 → 🔄 立即巡检」一键跑一遍。同步看 Telegram 收没收到。

curl 等价：
```bash
curl -X POST http://localhost:3000/api/pool/alerts/run \
     -H "Authorization: Bearer <root_access_token>"
```
返回 `{"started": true}`，结果异步落表。

---

## 4. 告警查阅 / 处置

后台「号池管理 → 巡检告警」页主区是告警历史表，支持：

| 操作 | 说明 |
|---|---|
| 按严重度筛选 | info / warning / critical |
| 按是否已解决筛选 | 默认看未解决 |
| 标记解决 | 点行尾「✅ 标记已解决」按钮（写 `resolved=true / resolved_at`） |
| 复制详情 | 长按消息复制到剪贴板 |

> 📌 **不要靠人肉关掉告警去掩盖问题**——同一规则 24h 后会重发。
> 真正的修复路径：去「上游账号」/「渠道管理」处理源头。

---

## 5. 巡检日志位置

| 路径 | 内容 |
|---|---|
| `data/logs/oneapi-yyyy-mm-dd.log` | 巡检引擎运行流水（带 `[pool/health]` 前缀） |
| `pool_alert_history` 表 | 结构化告警 |
| Telegram 群 | 实时推送（人看的） |

排查告警没收到：
1. 看 `oneapi-*.log` 里 `[pool/health]` 起始行是否有报错（如 `chat not found` / `unauthorized`）。
2. `SELECT * FROM pool_alert_history ORDER BY id DESC LIMIT 5;` 看是不是写入了。
3. 单独跑 Telegram 测试消息（步骤 2.「测试通道」）。

---

## 6. 推荐的"运营自检日历"

| 频率 | 操作 | 何处 |
|---|---|---|
| 每天早 | 看 Telegram 过去 24h 告警列表，确认每条都有结论 | Telegram |
| 每天早 | 进「号池管理 → 总览」看健康分（≥ 90 安心） | 后台 |
| 每周一 | 进「号池管理 → 收支对账」看周毛利率（< 30% 立即换 Recipe / 换 Group） | 后台 |
| 每周一 | 进「号池管理 → 上游账号」按余额倒序，余额 < $5 的开新号补位 | 后台 |
| 每月一 | `cp one-api.db backup-yyyy-mm.db && tar -czf data-yyyy-mm.tgz data/` | 服务器 shell |
| 每月一 | 检查 fork 自身有没有 `git status` 未提交的"野改"，全部入 commit | 服务器 shell |

---

## 7. 进阶：把告警接到第三方（webhook）

号池侧目前只支持 Telegram。如果你要接钉钉 / 飞书 / 企微 / Slack：

最快做法 — 让 Telegram bot 转发：
- 用 `tdlib` / 等 Telegram client 监听机器人消息，转 webhook 出去。

干净做法 — 改源码：
1. `service/pool_health.go::sendAlert` 函数末尾加你自己的 `sendDingtalk(...)` `sendFeishu(...)`。
2. 在 `controller/pool.go::SetPoolTelegramConfig` 旁边照葫芦画瓢加新的 `SetPoolDingtalkConfig`。
3. 前端「巡检告警」页加新的设置 Modal。
4. 不要改 Telegram 字段名 / API 形状，否则前端也得改。

> 改完记得把 ADR-0007 加一条修订（superseded by ADR-XXXX）说明新增了哪些通道。

---

## 8. 故障演练（每季度做一次）

1. **拉网线测试**：临时把上游 base_url 改成不可达地址 → 看是否在 5 分钟内出现 `channel_down` 告警 + Telegram 推送。
2. **掉余额测试**：手改某 PoolAccount 的 `balance_usd = 0.5` → 看是否出 `balance_low`。
3. **关 Telegram 测试**：清空 `PoolTelegramChatId` → 巡检仍跑 + 历史落表 + 不推 Telegram。

演练完恢复配置，并在 Telegram 群里 ping 一句"演练已结束"，避免误以为真出事。
