# Runbook 02：Postgres 数据库不可用

**P0** · SLA 影响：100% · 目标 MTTR：≤ 15 分钟

## 现象 / 触发

- `PostgresDown` 告警
- new-api 日志大量 `connection refused` / `dial tcp` 错误
- 全部新请求 5xx

## 第一时间动作

1. **确认 Postgres 容器状态**：
   ```bash
   docker compose -f docker-compose.prod.yml ps postgres
   docker compose -f docker-compose.prod.yml logs --tail 200 postgres
   ```

2. **判断故障类型**：

   | 现象 | 可能原因 | 操作 |
   |---|---|---|
   | 容器 `Restarting` 循环 | 配置错 / 数据损坏 | 看日志，看下面 "数据损坏处理" |
   | 容器 `Exited` | OOM / 磁盘满 | 看 `dmesg`，扩资源后重启 |
   | 容器 `Up` 但连不上 | 端口/网络问题 | 重建网络：`docker compose down && docker compose up -d` |
   | 磁盘满 | 日志库膨胀 | 看下面 "磁盘满处理" |

3. **简单恢复尝试**（90% 故障靠这步搞定）：
   ```bash
   docker compose -f docker-compose.prod.yml restart postgres
   sleep 30
   docker compose -f docker-compose.prod.yml ps
   ```

## 数据损坏处理

```bash
# 1. 停掉 new-api（避免再写）
docker compose -f docker-compose.prod.yml stop new-api-1 new-api-2

# 2. 用最新备份恢复（验证模式先）
bash scripts/restore.sh ./backups/newapi-最新时间戳.sql.gz.enc verify

# 3. 验证 OK 后用 overwrite 模式覆盖
bash scripts/restore.sh ./backups/newapi-最新时间戳.sql.gz.enc overwrite

# 4. 启动 new-api
docker compose -f docker-compose.prod.yml start new-api-1 new-api-2
```

⚠️ **数据丢失窗口 = 最近备份到现在的时间**。如果备份是凌晨 3 点，现在是中午，你会丢失 9 小时的用户消耗记录。**事后必须做对账。**

## 磁盘满处理

```bash
# 看哪占空间
docker exec new-api-postgres du -sh /var/lib/postgresql/data
df -h

# 临时清日志库（new-api 调用日志在独立库 newapi_logs）
docker exec -it new-api-postgres psql -U newapi -d newapi_logs -c "
  TRUNCATE TABLE logs RESTART IDENTITY;
"

# 清 Docker 旧镜像/卷
docker system prune -af --volumes
```

## 升级到主从（事后改进）

如果这次故障是因为没有主从：今天就部署 [Patroni](https://github.com/zalando/patroni) 或用 PG 的物理流复制做主从。Runbook 升级版会加 `pg_promote` 切流的步骤。

## 状态页 + 公告

- 故障期间：状态页 "数据库故障，正在恢复"
- 恢复后：补一个 RCA 简报（可发可不发，看用户群体）

## 事后复盘模板

- 故障类型：(数据损坏/OOM/磁盘满/其它)
- 数据丢失：从 ___ 到 ___，约 ___ 条记录
- 是否需要给用户补偿：是/否
- 是否需要做主从：（强烈建议）
