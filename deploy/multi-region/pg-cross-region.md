# 跨区域 PG 副本

## 拓扑

```
us-east (主)                 eu-central (备)
┌──────────┐                 ┌──────────┐
│ pg-1 R/W │ ── stream ────> │ pg-eu-1  │ (读 only)
│ pg-2 RO  │                 │ pg-eu-2  │
│ pg-3 RO  │                 └──────────┘
└──────────┘                       ↑
                                   │ (failover 时 promote)
                                   │
                              read here in EU
```

- **主集群**：3 节点 Patroni（us-east），etcd HA
- **跨区副本**：1-2 节点（eu-central），通过 streaming replication
- **延迟**：约 80-100ms 复制延迟（异步）
- **不允许**：跨区同步副本（性能不可接受）

## 配置主集群对外允许复制

`/etc/postgresql/16/main/pg_hba.conf`:

```
# 跨区副本认证（仅允许复制账号 + IP 白名单）
hostssl  replication    repuser    <eu-vpn-cidr>     scram-sha-256
```

`/etc/postgresql/16/main/postgresql.conf`:

```
wal_level = replica
max_wal_senders = 10
max_replication_slots = 10
hot_standby = on
hot_standby_feedback = on
synchronous_commit = on  # 主内同步，跨区异步
```

主集群创建复制 slot：

```sql
SELECT pg_create_physical_replication_slot('eu_replica');
```

## 跨区副本启动

在 eu-central 节点：

```bash
# 1. base backup（占用大约几小时取决于库大小）
pg_basebackup -h <us-vpn-ip> -U repuser -D /var/lib/postgresql/data \
              -P -X stream --create-slot --slot=eu_replica

# 2. 配置 standby
cat > /var/lib/postgresql/data/standby.signal << EOF
EOF

cat >> /var/lib/postgresql/data/postgresql.conf << EOF
primary_conninfo = 'host=<us-vpn-ip> port=5432 user=repuser password=xxx application_name=eu_replica sslmode=require'
primary_slot_name = 'eu_replica'
hot_standby = on
EOF

# 3. 启动
systemctl start postgresql
```

## 网络

- 用 [Tailscale](https://tailscale.com/) / Wireguard / IPSec 在 us-east 与 eu-central 之间建私网
- 不要走公网（流量大易被墙、加密强度自己保证）
- 推荐 Tailscale，10 分钟搞定，免费额度足够

## 用 pgbouncer 分流读写

每个 region 跑一个 pgbouncer：

```ini
# /etc/pgbouncer/pgbouncer.ini (eu-central)
[databases]
new_api_rw = host=<us-vpn-ip> port=5432 dbname=new_api  ; 写走 us
new_api_ro = host=localhost port=5432 dbname=new_api    ; 读走本地副本

[pgbouncer]
pool_mode = transaction
max_client_conn = 1000
default_pool_size = 50
```

new-api 配置（双 DSN）：

```bash
SQL_DSN=postgres://user@pgbouncer-eu:6432/new_api_rw   # 写
LOG_SQL_DSN=postgres://user@pgbouncer-eu:6432/new_api_ro  # 日志只读副本
```

## Failover：promote eu 副本

仅在 us 主集群整个挂时执行：

```bash
# 1. 确认 us 真的不可用（否则 split-brain）
ssh pg-1.us "patronictl list" || echo "确认挂"

# 2. promote eu
ssh pg-eu-1 "pg_ctl promote -D /var/lib/postgresql/data"

# 3. 验证
ssh pg-eu-1 "psql -c 'SELECT pg_is_in_recovery()'"  # 应返回 f

# 4. 切 new-api 配置指向 eu 主库（所有 region 都走跨区写）
ansible all -i inventories/production.yml -m lineinfile \
  -a "path=/opt/new-api/.env regexp='^SQL_DSN=' line='SQL_DSN=postgres://user@<eu-vpn-ip>:5432/new_api'"

ansible all -i inventories/production.yml -m shell \
  -a "cd /opt/new-api && docker compose restart new-api"

# 5. 等 us 修复后，把它作为 eu 的副本反向跑（数据回填）
```

## Failback（回切到 us）

```bash
# 1. 确保 us 集群已修复且无数据丢失
# 2. 把 us 节点作为 eu 的副本起来（pg_basebackup from eu）
# 3. 等同步完成
# 4. 在低峰时段切流：
#    a. 短暂只读模式（new-api 维护页）
#    b. promote us 节点
#    c. 把 eu 重新作为 us 副本
#    d. 改 SQL_DSN 回 us
#    e. 恢复 R/W
# 5. 总切流时间约 10 分钟
```

## 监控

Prom 抓 `pg_replication_lag_bytes` 与 `pg_replication_lag_seconds`：

```yaml
# alertmanager
- alert: ReplicationLagHigh
  expr: pg_replication_lag_seconds > 30
  for: 5m
  annotations:
    summary: "EU 副本落后 us 主库 > 30s"
    runbook: deploy/multi-region/pg-cross-region.md
```

## 备份

- **不要只依赖跨区副本作为备份**——副本会同步删除！
- 单独跑 [pgBackRest](https://pgbackrest.org/) 或 wal-g 到 S3：
  - us-east：每天 full + 持续 WAL → S3 us-east-1
  - eu-central：每周 full → S3 eu-central-1（异地）
- PITR 能力：理论上恢复到任意时间点（保留 7-30 天 WAL）
- 每月做一次"恢复演练"——拉 backup 到测试机能起来

## 数据合规

如果 EU 用户数据**只能存 EU**（GDPR）：

- 不能用单库跨区副本，必须**分库**
- 用户表加 `region` 字段，按用户所在地路由到对应库
- 详见 [`legal/data-residency.md`](../legal/data-residency.md)

## 常见坑

- **副本落后过多**自动断开：调大 `wal_keep_size = 4GB`
- **复制 slot 占满磁盘**：副本挂了不删 slot 主库 WAL 不清，主库爆盘
  → 加监控 `pg_replication_slots.active=false` 超 1h 告警
- **VPN 重连**：tailscale 重连会断 TCP，pg streaming 需要重连
  → 接受，10s 内自动恢复
- **网络分区**：us 和 eu 都觉得自己活着→ split brain
  → 必须**人工**确认 us 死透了再 promote
