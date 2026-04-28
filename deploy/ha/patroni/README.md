# Patroni + etcd + HAProxy + pgBouncer

## 拓扑

```
应用 → pgBouncer:6432 → HAProxy:5000 → 当前主库 (Patroni 自动选)
                       HAProxy:5001 → 任一从库（只读）
                                     ↑
                              etcd × 3 (DCS)
```

## 启动

```bash
cd deploy/ha/patroni
docker compose -f docker-compose.patroni.yml up -d

# 等 30s 让 etcd 选主，Patroni 选 PG 主
sleep 30

# 看集群状态
docker exec patroni1 patronictl -c /home/postgres/postgres.yml list

# 应该看到 Leader (patroni1) + Replica (patroni2)
```

## new-api 改连这套

把 `docker-compose.prod.yml` 里 new-api 的环境变量 `SQL_DSN` 指向 pgBouncer:

```yaml
SQL_DSN: postgresql://${PG_USER}:${PG_PASSWORD}@pgbouncer:6432/${PG_DB}
LOG_SQL_DSN: postgresql://${PG_USER}:${PG_PASSWORD}@pgbouncer:6432/${PG_LOG_DB}
```

只读分析（BI / 报表）连 5001 端口。

## Failover 演练

```bash
# 1. 看当前主
docker exec patroni1 patronictl -c /home/postgres/postgres.yml list

# 2. kill 主
docker stop patroni1

# 3. 立刻看：30s 内 Patroni 应该把 patroni2 promote 成主
watch docker exec patroni2 patronictl -c /home/postgres/postgres.yml list

# 4. 应用层应该自动切（HAProxy 检测到 health 变化）
# 测一下：curl http://api.example.com/api/status

# 5. 恢复 patroni1 → 自动变成 replica
docker start patroni1
```

**目标 RTO**：< 30s
**目标 RPO**：streaming replication 几乎 0（取决于 commit 时机）

## 备份策略

Patroni Spilo 镜像内置 wal-g 持续 WAL 归档：

```yaml
# Spilo 环境变量
WAL_G_S3_PREFIX: s3://your-bucket/wal-archive/
AWS_ACCESS_KEY_ID: ...
AWS_SECRET_ACCESS_KEY: ...
USE_WALG_BACKUP: "true"
USE_WALG_RESTORE: "true"
BACKUP_SCHEDULE: "0 4 * * *"
BACKUP_NUM_TO_RETAIN: 7
```

PITR (Point-In-Time Recovery) 能力：恢复到任意秒。

## 注意

- **生产环境 etcd 至少 3 节点**，跨可用区
- pgBouncer 用 transaction pool mode，注意应用层不能依赖 session 状态（new-api OK）
- 监控：Patroni `/health` `/replica` `/leader` 都暴露 HTTP，加 blackbox_exporter 探活
