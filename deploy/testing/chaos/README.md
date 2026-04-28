# 混沌实验

> 主动注入故障，验证 SLO 不会塌方。

## 实验清单

| ID | 实验 | 预期 | 频率 |
|---|---|---|---|
| C-01 | kill 一个 new-api 实例 | 流量切到另一实例，失败率 < 1% | 月 |
| C-02 | kill PG 主库，等 Patroni failover | RTO < 30s，写 RPO < 5s | 月 |
| C-03 | block Redis Sentinel 5 分钟 | 客户端 fallback 到无缓存模式 | 月 |
| C-04 | mock 上游 OpenAI 全 503 | 自动切换到 Anthropic 分组 | 月 |
| C-05 | 网络丢包 5% 持续 5 分钟 | 自动重试，最终成功率 > 99% | 季 |
| C-06 | 磁盘填满 90% | 监控告警 + 自动清理 | 季 |
| C-07 | 时钟漂移 60s | TLS 不应失败（依赖 NTP）| 季 |
| C-08 | 数据库连接池打满 | 优雅降级，不应崩 | 季 |

## 通用原则

- **永远在 staging 跑，不在生产跑**（除非已演练 5+ 次）
- 跑前**必须发公告**到内部群（避免被误以为是真故障）
- 跑前**必须能回滚**（一键脚本 / 手动操作清单）
- 跑后**必须复盘**（写报告：预期 vs 实际 / 改进项）

## 工具

- [`kill-one-gateway.sh`](./kill-one-gateway.sh) C-01
- [`kill-pg-primary.sh`](./kill-pg-primary.sh) C-02
- [`block-redis-sentinel.sh`](./block-redis-sentinel.sh) C-03
- [`mock-openai-503.sh`](./mock-openai-503.sh) C-04
- [`tc-loss.sh`](./tc-loss.sh) C-05（用 `tc` netem）
- [`fill-disk.sh`](./fill-disk.sh) C-06

## 月度演练流程

```mermaid
flowchart LR
    Plan[周一规划] --> Notify[周二早上 9:00 内部公告]
    Notify --> Run[周二 14:00 执行实验]
    Run --> Observe[Run + 1h 内观察告警/SLO]
    Observe --> Recover[手动恢复 if needed]
    Recover --> Report[周三 9:00 复盘报告]
```

## 复盘报告模板

```markdown
# 混沌实验报告 #{exp_id} - {date}

## 实验背景
- 实验 ID：C-01
- 执行时间：YYYY-MM-DD HH:MM ~ HH:MM
- 执行人：@xxx
- 预期：…

## 实际过程
- 注入：…
- 系统表现：…
- 告警是否按预期发出：…
- 用户侧影响（应该没有）：…

## 偏差
- 预期 vs 实际：…
- 偏差原因：…

## 改进项
- [ ] 修 bug：…
- [ ] 改告警阈值：…
- [ ] 改 runbook：…

## 下次演练
- 优化点：…
- 增加新场景：…
```
