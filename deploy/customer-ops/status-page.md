# 状态页 + 公告 SOP

## 工具：Uptime Kuma 自建

```yaml
# docker-compose.statuspage.yml
services:
  uptime-kuma:
    image: louislam/uptime-kuma:1
    ports: ["3002:3001"]
    volumes:
      - kuma_data:/app/data
    restart: always
volumes:
  kuma_data:
```

绑定到 `status.example.com` （Cloudflare 加速 / WAF 保护）。

## 监控对象（最少配置）

| 探针类型 | 目标 | 间隔 | 阈值 |
|---|---|---|---|
| HTTP | `https://api.example.com/v1/models`（轻量探活）| 60s | 3 次失败 |
| HTTP | `https://api.example.com/health` | 60s | 3 次 |
| TCP | api.example.com:443 | 60s | 3 次 |
| HTTPS Cert | `api.example.com` | 12h | < 14 天告警 |
| Push | `gateway-instance-1` self-report | 60s | 5 次缺失 |
| HTTP keyword | OpenAI: chat completion 测试 | 5min | 失败率 > 30% |
| HTTP keyword | Anthropic: messages 测试 | 5min | 失败率 > 30% |
| HTTP keyword | Gemini: generate 测试 | 5min | 失败率 > 30% |

## 状态分组（前端展示）

```
✅ Gateway        网关服务
✅ OpenAI 通道    含官方 + OAuth + 第三方
✅ Anthropic 通道
✅ Gemini 通道
✅ 数据库         不展示给公开用户（仅内部状态页）
✅ 支付通道       USDT / Stripe / 易支付
```

公开页面**不展示**内部数据库 / Redis / 上游账号细节，避免泄漏架构。

## 公告流程

### 故障发生

1. **0-2 min**：监控自动告警（Telegram / 短信）
2. **2-5 min**：客服值班 / 工程值班看到
3. **5-10 min**：工程值班拉 IC，开战时频道
4. **15 min 内**：发布**初步公告**（确认问题，未必有原因）：

   ```
   [Investigating] 我们注意到 OpenAI 通道可能存在异常，正在调查中。
   开始时间：2026-04-27 14:32 UTC+8
   影响范围：尝试调用 gpt-4o 系列模型的请求
   下次更新：14:50 前
   ```

5. **每 15-30 min** 更新一次（即使没有进展也要发 "still investigating"）
6. **修复中**：状态改 `Identified` → `Monitoring`
7. **修复完成**：`Resolved`，发完整 RCA 链接

### 计划维护

- 提前 **48 小时** 公告（影响少时 24 小时）
- 公告含：起止时间、影响范围、预期可恢复时间
- 选最低峰时段（一般凌晨 2-4 点 UTC+8）
- 维护中状态页显示 `Maintenance`（**不算 SLA 不达标**）

## 历史故障归档

每次 `Resolved` 后，72 小时内：
- 在状态页历史区生成一条故障记录
- 含：起止时间、影响范围、根因摘要、长期改进措施

季度发布**SLA 报告**（PDF / 网页），包含：
- 实际可用性 vs 承诺 SLA
- Top 3 故障类型
- 改进项进度

## 多渠道分发

公告同步发到：
- 状态页（主）
- Telegram 频道 [[t.me/example_status]]
- 邮件群发（用户登录后偏好里勾选才发）
- 网关用户后台首页 banner（仅当前在线用户能看到）

> ⚠️ **不要**只发到一个渠道；用户可能并不订阅你的状态页。

## 内部状态页（不公开）

另开一个 Uptime Kuma 实例，加入：
- 数据库主从延迟
- Redis Sentinel 切换历史
- 上游 KEY 健康率（每个分组的活渠道数）
- new-api 各实例 / Caddy / Vault 健康
- 备份任务执行历史
- CI/CD 部署历史
- 客服系统是否在线

只对内部 IP / Cloudflare Access 开放。

## 与工单系统联动

故障发生时：
- 状态页置顶 → 用户进 Chatwoot widget 时**自动弹横幅**："我们正在处理 #incident-xxx"
- 减少新工单数量（用户看到公告会主动等）
- 客服回复**统一引用**故障公告链接
