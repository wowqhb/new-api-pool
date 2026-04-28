# 备份与恢复

> SQLite + data 目录就是全部状态。备份文件夹 = 备份整个站。
> 这一章给你**3 套备份方案**（手工 / cron / 增量）+ 完整的**恢复 / 灾难重建**流程。

---

## 1. 数据全在哪里

| 路径 | 内容 | 必须备份？ |
|---|---|---|
| `<REPO>/one-api.db` | SQLite 主库（用户 / 渠道 / 号池 / token / option） | ✅ 必须 |
| `<REPO>/one-api.db-wal` | SQLite WAL 日志（运行时存在） | ✅ 一起拷 |
| `<REPO>/one-api.db-shm` | SQLite 共享内存（运行时存在） | ✅ 一起拷 |
| `<REPO>/data/logs/` | 应用 + 巡检 + worker 日志 | ⚠️ 选备份（排查问题用） |
| `<REPO>/data/uploads/` | 用户头像 / 上传文件（如果业务有） | ⚠️ 选备份 |
| `<REPO>/` | 修改后的 Go + React 源码 | ✅ git 推到远程即视为备份 |
| 编译产物 `new-api-macos` | 二进制，~80MB | ❌ 重新编译即可 |

> **关键洞察**：备份 ≠ 拷 `one-api.db` 一个文件。SQLite 在 WAL 模式下，**未 checkpoint 的写入在 wal/shm 文件里**。直接拷 `one-api.db` 的瞬时状态可能少几条。

---

## 2. 方案 A：人工冷备份（停服 30 秒）

最稳，准生产用：

```bash
cd <REPO>

# 1. 关进程
pkill -f new-api-macos

# 2. 备份
mkdir -p backups
ts=$(date +%Y%m%d-%H%M%S)
cp one-api.db                   "backups/one-api.${ts}.db"
[ -f one-api.db-wal ] && cp one-api.db-wal "backups/one-api.${ts}.db-wal"
[ -f one-api.db-shm ] && cp one-api.db-shm "backups/one-api.${ts}.db-shm"
tar -czf "backups/data.${ts}.tgz" data/

# 3. 起服务
./start.command
```

每月一次足够。备份文件存 → S3 / OSS / Backblaze / 另一台机器 SCP。

---

## 3. 方案 B：热备份（不停服，推荐用脚本 cron）

利用 SQLite 自己的 `.backup` 命令，原子级一致：

```bash
sqlite3 <REPO>/one-api.db \
  ".backup '<REPO>/backups/one-api.$(date +%Y%m%d-%H%M%S).db'"
```

这条命令会在 sqlite 内部加 shared lock 拷贝，**不会丢 WAL 里的数据**，对在线 read/write 的影响 < 1s。

### crontab 推荐

```cron
# 每天 03:30 热备 + 保留最近 30 天
30 3 * * * cd <REPO> && \
  sqlite3 one-api.db ".backup 'backups/one-api.$(date +\%Y\%m\%d).db'" && \
  find backups -name 'one-api.*.db' -mtime +30 -delete

# 每周日 04:00 完整 data 目录归档
0 4 * * 0 cd <REPO> && \
  tar -czf backups/data.$(date +\%Y\%m\%d).tgz data/ && \
  find backups -name 'data.*.tgz' -mtime +90 -delete
```

> macOS 用 `crontab -e` 编辑；如果走 `launchd`，参考 [`03-deployment/local.md`](../03-deployment/local.md#auto-startup) 的 launchd 套路。

---

## 4. 方案 C：异地增量（Postgres 化以后）

如果迁到 Postgres（参考 [`03-deployment/production.md`](../03-deployment/production.md)）：

- **wal-g / pgBackRest**：WAL 流式备份到 S3，RPO 1-5 分钟
- **pg_dump 每日**：逻辑备份，能跨大版本恢复
- **物理快照**：云盘 EBS / OSS 每日快照

公式：
- RPO（最多丢多久数据） = WAL 推送间隔
- RTO（恢复要多久） = base backup 拉取 + WAL 重放

---

## 5. 恢复 / 灾难重建

### 场景 A：原机数据库损坏

```bash
cd <REPO>

pkill -f new-api-macos

mv one-api.db one-api.db.broken
[ -f one-api.db-wal ] && mv one-api.db-wal one-api.db-wal.broken
[ -f one-api.db-shm ] && mv one-api.db-shm one-api.db-shm.broken

cp backups/one-api.YYYYMMDD.db one-api.db

./start.command
```

启动后第一件事：**进后台 → 渠道管理 → 全部 ✅ 测试**，确认连通性没掉。

### 场景 B：换台新机器从零拉起来

```bash
# 在新机器上：
# 1. 装 Go 1.26+ + Bun（详见 02-development/setup.md）
# 2. 拉源码
git clone <自己的 fork URL> ~/AITRANSFER/new-api-src
cd ~/AITRANSFER/new-api-src/web && bun install && bun run build
cd .. && go build -o ../new-api/new-api-macos
mkdir -p ~/AITRANSFER/new-api && cd ~/AITRANSFER/new-api

# 3. 把备份拷过来
scp old-server:<REPO>/backups/one-api.YYYYMMDD.db ./one-api.db
scp old-server:<REPO>/backups/data.YYYYMMDD.tgz - | tar -xzf -

# 4. 起
./start.command
```

5 分钟内业务复活。

### 场景 C：要回到几小时前（误操作 / 误删 channel）

只能恢复到最近一次备份点（这就是为什么至少要日备 + 周备）。

```bash
pkill -f new-api-macos
cp backups/one-api.YYYYMMDD.db one-api.db   # 选要回到的那天
./start.command
```

> 要做"回到几分钟前"必须迁 Postgres + WAL 流复制。SQLite 单机做不到。

---

## 6. 备份完整性自检（脚本）

```bash
#!/bin/bash
# verify-backup.sh — 用临时副本启动 + curl 自检
set -e
B=$1
TMPDIR=$(mktemp -d)
trap "rm -rf $TMPDIR" EXIT

cp "$B" "$TMPDIR/one-api.db"
cd "$TMPDIR"
PORT=43210 SQL_DSN="" <REPO>/new-api-macos \
  --port 43210 > startup.log 2>&1 &
PID=$!
sleep 6

curl -sf http://localhost:43210/api/status > /dev/null \
  && echo "✅ $B 可启动 + /api/status 200" \
  || { echo "❌ $B 备份损坏"; cat startup.log; }

kill $PID 2>/dev/null || true
```

把它丢 cron 月度跑一次，备份坏了立刻知道。

---

## 7. 备份要含哪些"非数据"东西

不能只备份数据库——**配置 + 编译环境 + 文档**也算。

```text
backups/
├── one-api.20260428.db                 ← SQLite 全量
├── data.20260428.tgz                   ← logs / uploads
├── source-snapshot.20260428.tgz        ← git bundle 整个 new-api-src
├── env-snapshot.20260428.txt           ← cat /etc/environment + go version + bun --version
└── docs-snapshot.20260428.tgz          ← 整个 docs/ 目录（这本文档）
```

灾难场景：硬盘炸了 + 远程仓库被删 + 老板还想恢复 → 你需要靠 `source-snapshot` 重建源码。

```bash
cd new-api-src
git bundle create ../backups/source-snapshot.$(date +%Y%m%d).bundle --all
```

---

## 8. 不要做的事

- ❌ **不要**直接 `cp one-api.db` 在服务运行中（会少几条 WAL 数据），用 `sqlite3 .backup`
- ❌ **不要**把备份和原库放同一块磁盘（磁盘炸 = 一锅端）
- ❌ **不要**只备份本周 / 本月一次（误操作 24h 后才发现 → 永远丢了）
- ❌ **不要**忘记验证备份能启动（很多人备了 3 年发现都打不开）
- ❌ **不要**把备份明文留在服务器上（含 channel.key 全量明文）→ 加密或离线存
