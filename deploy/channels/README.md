# 渠道与分组初始化

这里是号池的核心配置：4 个渠道分组 + 3 个用户分组 + 倍率/优先级配置。

## 整体架构

```
用户分组（决定售价）         渠道分组（决定路由）
─────────────────         ─────────────────
vip   (倍率 1.5×)  ─┐   ┌─ official      (priority 200)  ← 官方付费 Key
default (1.2×)    ─┼─→─┤  claude-oauth   (priority 150)  ← Claude 账号 OAuth
free  (1.0× 限模型) ─┘   ├─ gemini-free   (priority 100)  ← Gemini 免费 Key
                         └─ third-party   (priority  50)  ← 第三方二级 Key
```

## 优先级 / 权重 / 倍率三件套

| 渠道分组 | priority | 默认 weight | 备注 |
|---|---|---|---|
| official | 200 | 50 | 官方 Key，最稳，给付费用户优先 |
| claude-oauth | 150 | 50 | OAuth 5h 窗口限制，每号独立渠道 |
| gemini-free | 100 | 50 | 大批量低价 Key，限 RPM/RPD |
| third-party | 50 | 50 | 兜底，质量低，失败阈值收紧 |

| 用户分组 | 分组倍率 | 可用渠道分组 | 模型白名单 |
|---|---|---|---|
| vip | 1.5× | official, claude-oauth | 全部 |
| default | 1.2× | official, claude-oauth, gemini-free, third-party | 全部 |
| free | 1.0× | gemini-free, third-party | 仅低价模型（gemini-1.5-flash, gpt-3.5 等）|

> 1.5× / 1.2× / 1.0× 是建议值，按你的市场调整。永远要预留至少 30% 利润缓冲。

## 一键初始化（推荐）

```bash
cd deploy/

# 1. 确保 new-api 已经启动并能访问
curl -s http://127.0.0.1:3000/api/status | jq

# 2. 在管理后台 → 系统设置 → 个人中心 创建一个 "Admin Token"
#    或直接用 root 用户的 access_token，存到 .env：
#    ADMIN_API_TOKEN=xxx

# 3. 跑初始化脚本（创建分组 + 倍率）
bash scripts/init-groups.sh

# 4. 导入渠道（按提示填 Key）
bash scripts/import-channel.sh channels/template-official-openai.json
bash scripts/import-channel.sh channels/template-claude-oauth.json
bash scripts/import-channel.sh channels/template-gemini-free.json
bash scripts/import-channel.sh channels/template-third-party.json
```

## 渠道模板说明

| 模板 | 用途 |
|---|---|
| [`template-official-openai.json`](./template-official-openai.json) | 官方 OpenAI sk- Key |
| [`template-official-anthropic.json`](./template-official-anthropic.json) | 官方 Anthropic sk-ant- Key |
| [`template-official-gemini.json`](./template-official-gemini.json) | 官方付费 Gemini Key |
| [`template-claude-oauth.json`](./template-claude-oauth.json) | Claude 账号 OAuth token |
| [`template-gemini-free.json`](./template-gemini-free.json) | 多 Key 模式的 Gemini 免费池 |
| [`template-third-party.json`](./template-third-party.json) | 第三方中转的二级 Key |

每个模板都有 `_comment` 字段说明如何填，导入脚本会自动剥离。

## 监控设置（管理后台手动开）

「运营设置 → 监控设置」里这几项一定要打开：

- ✅ 失败时自动禁用通道
- ✅ 成功时自动启用通道
- ✅ 自动启用检查时间（建议 5 分钟）
- ✅ 失败禁用阈值（默认 5 次，按需）

「相关错误码」：
- `401, 403`：账号问题，立即禁用
- `429`：建议**不要**自动禁用（会导致雪崩），改为降优先级（需脚本协助）
- `500, 502, 503`：短期禁用 + 自动恢复

## 健康巡检 cron（每 10 分钟）

```bash
# 加进 crontab
*/10 * * * * cd /path/to/deploy && bash scripts/channel-healthcheck.sh >> logs/healthcheck.log 2>&1
```
