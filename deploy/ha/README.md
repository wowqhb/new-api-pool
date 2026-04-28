# 高可用架构

> 单节点 = 单点故障。这一目录给出**真正生产级**的 HA 方案。

## 架构

```
                    ┌──────────────────────┐
                    │ Cloudflare (anycast) │
                    └──────────┬───────────┘
                               ↓
                    ┌──────────┴───────────┐
                    │  HAProxy / Caddy LB  │ (Active-Active VIP)
                    └─────┬──────────┬─────┘
                          ↓          ↓
                    ┌─────┴──────────┴─────┐
                    │    new-api * 3       │ (无状态)
                    └─────┬──────────┬─────┘
                          ↓          ↓
            ┌───────────┐ ↓          ↓ ┌───────────┐
            │ Patroni   │←──→ etcd ←──→│ Patroni   │
            │ PG-1 主   │              │ PG-2 从   │
            └───────────┘              └───────────┘
                          ↓
                ┌─────────┴──────────┐
                │ Redis Sentinel * 3 │
                │ Master / 2 Replica │
                └────────────────────┘
```

## 模块

### 1. PostgreSQL HA: Patroni + etcd

- 3 节点 etcd 集群（DCS）
- 2 节点 PG（1 主 1 从，pgBouncer 在前面做 connection pool）
- 自动 failover，故障 < 30s

详见 [`patroni/`](./patroni/)。

### 2. Redis HA: Redis Sentinel

- 3 节点 Sentinel（仲裁，不存数据）
- 1 主 2 从

详见 [`sentinel/`](./sentinel/)。

### 3. 应用层 HA

new-api 本身**无状态**，3 个实例 + LB 即可。已经在 `docker-compose.prod.yml` 跑了 2 个，再加一个备机：

```yaml
new-api-3:
  <<: *newapi-base
  container_name: new-api-3
  environment:
    <<: *newapi-env
    NODE_TYPE: slave
    NODE_NAME: new-api-slave-2
```

## 部署模式

| 规模 | 推荐 | 成本 |
|---|---|---|
| MVP | 单机 prod compose | $20/月 |
| 小流量（< 1k QPS）| 单机 + 备份 + 异地从库 | $50/月 |
| 中等（1-10k QPS）| 这套 HA + 单数据中心 | $300-800/月 |
| 大（> 10k QPS）| 多数据中心 + 多区域 | $2000+/月 |

## 演练

每月一次，必做：

- [ ] kill 主 PG，看 failover 时间
- [ ] kill 主 Redis，看 Sentinel 切换
- [ ] 网络分区（用 `tc` 加延迟）
- [ ] 单 new-api 实例挂，看 LB 路由
