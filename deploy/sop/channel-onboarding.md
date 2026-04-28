# SOP：渠道入池

任何新渠道（官方 Key / OAuth 账号 / Gemini Free Key / 第三方）入池标准流程。

## 入池前检查

- [ ] 来源合法（不要用偷的 Key）
- [ ] 类型已分类：official / claude-oauth / gemini-free / third-party
- [ ] 备注信息：账号邮箱、充值额度、绑卡尾号、过期日（必填）
- [ ] 已确定 priority + weight + group（按 [`channels/README.md`](../channels/README.md)）

## 步骤

### 1. 单测（手动）

```bash
# 用 import-channel.sh 自动测一次
ADMIN_API_TOKEN=xxx bash scripts/import-channel.sh channels/template-xxx.json

# 失败 → 不入池，回去查 Key
# 成功 → 看下面进灰度
```

### 2. 进灰度分组

新建的渠道**先丢到 `xxx-canary` 分组**（如 `gemini-free-canary`），不要进正式分组。

```bash
# 直接在 admin UI 改 group 字段为 *-canary
# 或者在导入时就把 template 的 group 改成 canary
```

灰度分组只对**内测用户**开放（用户分组 `internal`），用真实流量打 24h。

### 3. 灰度 24h 观察指标

在 Grafana → New API 总览 → 渠道详情看板，过滤 group=xxx-canary，看：

- [ ] 成功率 ≥ 98%
- [ ] p95 延迟 ≤ 上游官方 + 500ms
- [ ] 没有连续错误码异常（401/403/429 大批）
- [ ] 至少处理过 100 个真实请求

### 4. 转正

```bash
# 把渠道 group 改成正式（如 gemini-free），priority/weight 也调整
# 通过 PUT /api/channel/{id} 或 admin UI
curl -X PUT "${API_BASE}/api/channel" \
  -H "Authorization: Bearer ${ADMIN_API_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{"id": <CHANNEL_ID>, "group": "gemini-free", "priority": 100, "weight": 50}'
```

### 5. Wiki 记录

在内部 Wiki / Notion 渠道清单记录：
- 渠道 ID / 名字
- 来源（账号/购买渠道）
- 入池时间 / 入池人
- 期望寿命（如 Gemini Free 1-3 周）
- 备注（特殊配置 / 限速 / 已知问题）

## 红灯（满足任一立即停止入池）

- 渠道是从来路不明的群里买的
- Key 格式异常（不像官方）
- 测试调用就 401/403
- 测试响应内容异常（如返回的不是模型输出）
- 上游有公告"近期严打" → 暂缓 1-2 周
