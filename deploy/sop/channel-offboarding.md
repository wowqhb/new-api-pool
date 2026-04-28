# SOP：渠道离池

渠道因故障 / 寿终 / 主动下架退出号池的标准流程。

## 触发条件

| 条件 | 处理 |
|---|---|
| 自动禁用 > 24h（监控告警） | 进入人工复核流程 |
| 401/403 持续 → 账号封禁 | 立即下架 |
| 429 持续不恢复 | 降权或下架 |
| 余额不足（官方付费 Key） | 下架（除非充值） |
| OAuth refresh 失败超过 3 次 | 下架，重新登录 |
| 安全事件相关（疑似泄漏） | 立即下架 + 轮换 |

## 步骤

### 1. 复核（人工）

打开 admin → 渠道，找到对应渠道：

- 看最近 50 条调用记录（错误码分布）
- 看最近一次成功调用时间
- 测一下 `/api/channel/test/{id}` 现状

### 2. 决策

| 情况 | 决策 |
|---|---|
| 临时故障，能恢复 | 重新启用，观察 1h |
| 永久失效（封号/欠费） | 下架 |
| 不确定 | 标记 `quarantine` 分组，等 7 天 |

### 3. 软下架（推荐做法）

```bash
# 不要立刻删，先改 weight=0（停止流量但保留记录）
curl -X PUT "${API_BASE}/api/channel" \
  -H "Authorization: Bearer ${ADMIN_API_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{"id": <ID>, "weight": 0, "status": 2}'
```

观察 7 天确认没人投诉/不影响后再硬删。

### 4. 硬下架

```bash
# 真要删的：
curl -X DELETE "${API_BASE}/api/channel/<ID>" \
  -H "Authorization: Bearer ${ADMIN_API_TOKEN}"
```

⚠️ 删除前先在备份里留一份完整 channel 记录（用于事后审计）。

### 5. 上游侧处理

- **官方付费 Key**：在 OpenAI/Anthropic/Google 后台 revoke 该 Key
- **Claude OAuth**：退出该账号 + 删 refresh token
- **Gemini Free Key**：在 AI Studio revoke
- **第三方**：联系供应商解约（如有月费）
- **不要忘记 Vault 里的对应密钥也要删**

### 6. Wiki 记录

更新渠道清单：
- 离池时间
- 离池原因
- 总寿命（入池→离池）
- 总调用 / 总收入 / 总成本（运营复盘用）
- 经验教训（下次怎么避免）

## 批量离池工具

```bash
# 找出所有禁用 > 24h 的渠道
bash scripts/list-stale-channels.sh

# 批量软下架
bash scripts/batch-offboard.sh < channel-ids.txt
```
