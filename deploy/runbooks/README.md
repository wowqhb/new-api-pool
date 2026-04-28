# 应急 Runbook 索引

每份 runbook 都是**告警触发时直接打开的操作手册**，按 5 分钟内能解决的优先级排序。

| 编号 | 场景 | P 级 | 触发告警 |
|---|---|---|---|
| [01](./01-upstream-down.md) | 主上游 API 全挂 | P0 | `UpstreamDown` × 多 |
| [02](./02-postgres-failover.md) | Postgres 数据库不可用 | P0 | `PostgresDown` |
| [03](./03-redis-down.md) | Redis 不可用 | P1 | `RedisDown` |
| [04](./04-cloudflare-block.md) | Cloudflare 误拦/触发挑战 | P1 | 5xx 突增 + 用户反馈 |
| [05](./05-domain-blocked.md) | 主域名被墙/被劫持 | P1 | 国内监测掉线 |
| [06](./06-payment-down.md) | 支付通道停服/失败 | P1 | 充值成功率下降告警 |
| [07](./07-account-mass-fail.md) | 号池大批失效 | P1 | `ChannelMassFailure` |
| [08](./08-data-leak.md) | 疑似数据泄漏 | P0 | 安全工单/异常活动 |
| [09](./09-bad-release.md) | 新版本升级失败 | P1 | 升级后 5xx 突增 |

## 通用原则

1. **先止血，后查根因**：大部分故障 90% 时间花在恢复服务上，事后复盘再分析。
2. **一定要发公告**：5 分钟内未恢复就在状态页 + Telegram 频道公告，比用户提工单更省事。
3. **记录时间线**：每个 runbook 末尾都有"事后复盘"模板，事故结束 24h 内必填。
4. **演练**：每月轮值演练一个场景，事先告知，注意不要在高峰期。

## 通用应急工具箱

```bash
cd deploy/

# 看所有容器状态
docker compose -f docker-compose.prod.yml ps

# 实时日志
docker compose -f docker-compose.prod.yml logs -f --tail 100 new-api-1

# 进容器
docker exec -it new-api-1 sh
docker exec -it new-api-postgres psql -U newapi -d newapi
docker exec -it new-api-redis redis-cli -a "$(grep REDIS_PASSWORD .env | cut -d= -f2)"

# 重启单实例（滚动）
docker compose -f docker-compose.prod.yml restart new-api-1

# 紧急停整个服务（最后手段，会断业务）
docker compose -f docker-compose.prod.yml down

# 回滚版本（先改 .env 的 NEW_API_VERSION）
docker compose -f docker-compose.prod.yml up -d new-api-1 new-api-2

# 状态页 / 公告快速发布（占位，按你实际工具改）
# tg-cli send "@status_channel" "正在排查 ..." 
```
