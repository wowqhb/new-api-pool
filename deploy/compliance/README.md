# 数据合规

适用法规（按地区严格度）：
- **GDPR (EU)**：最严，建议默认按这套做
- **CCPA / CPRA (California)**
- **个人信息保护法 (中国)**：用户位于中国时
- **APPI (日本) / PIPA (韩国) / PIPEDA (加拿大)**

## 三件大事

1. **最小化收集**：只收必需数据
2. **可控保留**：定义保留期 + 自动清理
3. **可被请求**：用户能查 / 改 / 导出 / 删除

## 数据资产清单

| 数据 | 含 PII？ | 保留期 | 加密 | 存储 |
|---|---|---|---|---|
| `users` (邮箱/用户名) | ✅ | 账号注销 + 30 天 | Backup 加密 | PG `newapi.users` |
| `tokens` | ❌ | 用户主动删 / 过期后 90 天 | - | PG `newapi.tokens` |
| `logs` (token 数/模型/IP) | 部分（IP）| 90 天 | - | PG `newapi_logs.logs` |
| `prompt/response` 内容 | ✅✅ | **不存 或 ≤ 24h** | 是 | 默认不存 |
| `topups` | ✅（支付订单号）| 5-7 年（合规要求） | ✅ | PG `newapi.topups` |
| `redemptions` | ❌ | 7 年 | - | PG `newapi.redemptions` |
| 备份 | ✅✅ | 30 天 + 月度归档 5 年 | AES-256 | 异地对象存储 |
| Loki 日志 | 部分 | 7 天（已脱敏）| - | 本地 |
| Prometheus 指标 | ❌ | 90 天 | - | 本地 |

## 关键开关（必做）

### 1. 不存 prompt/response

```bash
# 已经在 deploy/.env.example 里有：
LOG_PROMPT_ENABLED=false       # 关掉 prompt 日志
LOG_RESPONSE_ENABLED=false     # 关掉 response 日志
LOG_CONSUME_ENABLED=true       # 只记录消耗（token 数 / 模型 / 时长）
```

如果业务必须存（如调试用），最多存 24h，到期自动清：

```sql
-- 加 cron job
DELETE FROM logs_with_content WHERE created_at < NOW() - INTERVAL '24 hours';
```

### 2. IP 脱敏

Loki promtail 已配 PII 脱敏（参考 `monitoring/loki/promtail-config.yml`）。

但 new-api 的 `logs.ip` 字段是原始 IP，建议加日 cron 把 90 天前的 IP 模糊化（`/24`）：

```sql
UPDATE logs SET ip = regexp_replace(ip, '\.\d+$', '.0/24')
WHERE created_at < NOW() - INTERVAL '90 days' AND ip NOT LIKE '%/%';
```

### 3. 退订 / 删除接口

详见 [`gdpr-handlers.md`](./gdpr-handlers.md)。

## 用户请求处理 SOP

参考 [`user-data-request-sop.md`](./user-data-request-sop.md)。

接到用户的"我要查我的数据"或"删了我"请求，**法定最迟 30 天内**处理。

## 文档清单

- [`gdpr-handlers.md`](./gdpr-handlers.md)
- [`user-data-request-sop.md`](./user-data-request-sop.md)
- [`retention-policy.md`](./retention-policy.md)
- [`data-flow.md`](./data-flow.md)
- [`scripts/`](./scripts/) 自动化脚本（导出/删除/匿名化）
