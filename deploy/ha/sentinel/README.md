# Redis Sentinel

## 拓扑

```
                    ┌─────────────┐
                    │ Sentinel × 3│ (仲裁，Quorum 2)
                    └──────┬──────┘
                           ↓
              ┌────────────┴────────────┐
              ↓            ↓            ↓
        ┌──────────┐ ┌──────────┐ ┌──────────┐
        │  master  │ │ replica1 │ │ replica2 │
        └──────────┘ └──────────┘ └──────────┘
```

## 启动

```bash
cd deploy/ha/sentinel
docker compose -f docker-compose.sentinel.yml up -d

# 看主从
docker exec redis-master redis-cli -a "$REDIS_PASSWORD" INFO replication
docker exec redis-replica-1 redis-cli -a "$REDIS_PASSWORD" INFO replication

# 看 Sentinel 状态
docker exec redis-sentinel-1 redis-cli -p 26379 SENTINEL masters
```

## new-api 改连 Sentinel

new-api 不直接连 Sentinel（不支持），需要：

**方案 A**：用 [Redis Sentinel Proxy](https://github.com/patrickdk77/redis-sentinel-proxy) 在前面

**方案 B**：用 HAProxy + 自定义 health check（推荐）：

```haproxy
frontend redis_master_fe
    bind *:6379
    default_backend redis_master_be

backend redis_master_be
    option tcp-check
    tcp-check send AUTH\ $REDIS_PASSWORD\r\n
    tcp-check expect string +OK
    tcp-check send INFO\ replication\r\n
    tcp-check expect string role:master
    server redis-master redis-master:6379 maxconn 5000 check inter 2s
    server redis-replica-1 redis-replica-1:6379 maxconn 5000 check inter 2s backup
    server redis-replica-2 redis-replica-2:6379 maxconn 5000 check inter 2s backup
```

new-api 还是连 `redis://haproxy:6379`。

## Failover 演练

```bash
# 1. kill master
docker stop redis-master

# 2. ~5s 后 Sentinel 应该 promote 一个 replica
docker exec redis-sentinel-1 redis-cli -p 26379 SENTINEL get-master-addr-by-name mymaster

# 3. 应用层应该几乎无感知（HAProxy 切到新主）

# 4. 启回旧 master，自动变 replica
docker start redis-master
```

**目标 RTO**：< 10s（Sentinel down-after-milliseconds=5000 + failover-timeout）

## 监控

```yaml
# 加到 prometheus.yml 的 redis-exporter 配置
- job_name: redis-master
  static_configs: [{ targets: [redis-master:6379] }]
  metrics_path: /scrape
  params:
    target: ['redis-master:6379']

# 或者 redis_exporter 接 sentinel 自动发现：
# https://github.com/oliver006/redis_exporter
```

## 提示

- **生产**：每个 Sentinel 跑在独立 host（不要 3 个 Sentinel 在同 host）
- 如果只能单 host：用 docker swarm 跨 node 部署
- 大数据量（> 25GB）考虑 Redis Cluster 替代 Sentinel
