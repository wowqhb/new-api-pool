# 本地部署

> 当前主力部署形态。一台 Mac / Linux + 一个 binary + 一个 SQLite，能撑到内测期 ≤ 50 用户。

## 1. 标准启动

```bash
cd <REPO>
./start.command
```

`start.command` 做的事：
1. 检查 binary 大小（< 50 MB 视为残缺，拒绝启动）
2. `chmod +x` + `xattr -d com.apple.quarantine` 去 macOS 隔离属性
3. 5 秒延迟后用 `open` 命令拉起浏览器到 `http://localhost:3000`
4. 创建 `data/` 和 `logs/` 目录
5. `exec ./new-api-macos --port 3000 --log-dir ./logs`

`exec` 让 binary 直接接管当前 shell pid，`Ctrl+C` 即停。

## 2. 端口与监听

默认端口 3000，改法：

```bash
# 命令行参数（推荐）
./new-api-macos --port 8080

# 环境变量
PORT=8080 ./new-api-macos
```

监听地址为 `0.0.0.0`，**局域网其它机器也能访问**——内测可以方便点对点调试，但本机如果直接挂公网，记得：
- 改 root 密码
- 关闭注册（设置 → 通用 → 关闭注册）
- 加防火墙白名单 / Caddy 反代 + Cloudflare

## 3. 数据存放

| 类型 | 默认路径 | 备份建议 |
|---|---|---|
| 业务库 (SQLite) | `<REPO>/one-api.db` | 每天 `cp` 一份到外置盘 |
| 上传 / 缓存 | `data/` | 同上 |
| 应用日志 | `logs/oneapi-*.log` | rotate by date，保留 7 天即可 |
| 启动 stdout/stderr | 终端 | macOS Console.app 不会留 |

详细备份策略：[06-operations/backup-restore.md](../06-operations/backup-restore.md)。

## 4. 升级流程

> 本仓库**自维护，不再 merge 上游**。所有升级 = 自编译 + 替换 binary。

### 4.1 标准升级

```bash
cd <REPO>

# 1. 拉最新源码（如果是远端）/ 切到目标 commit
# git pull origin master  

# 2. 编译
(cd web && bun install && bun run build)
go build -o new-api-macos .

# 3. 备份当前运行体
cd <REPO>
cp new-api-macos new-api-macos.backup-$(date +%Y%m%d-%H%M%S)
sqlite3 one-api.db ".backup 'one-api.db.backup-$(date +%Y%m%d-%H%M%S)'"

# 4. 替换 binary
cp <REPO>/new-api-macos ./new-api-macos

# 5. 重启
pkill new-api-macos; sleep 1
./start.command
```

### 4.2 蓝绿升级（零停机）

```bash
# 1. 编新 binary
cd <REPO>
go build -o new-api-macos .

# 2. 跑在 3001 端口验证
cp new-api-macos <REPO>/new-api-macos.next
cd <REPO>
./new-api-macos.next --port 3001 --log-dir ./logs &

# 3. 烟测 3001
curl http://localhost:3001/api/status
curl http://localhost:3001/api/pool/overview -H "Authorization: Bearer ADMIN_TOKEN"

# 4. ok 后切端口（这里简单做法：杀旧的、改名启动）
pkill -f "new-api-macos --port 3000" 
mv new-api-macos.next new-api-macos
./start.command
```

如果用 Caddy 反代，可在 Caddy 层切 upstream，更稳。

### 4.3 回滚

```bash
cd <REPO>
pkill new-api-macos
cp new-api-macos.backup-YYYYMMDD-HHMMSS new-api-macos
# 如要恢复 DB
cp one-api.db.backup-YYYYMMDD-HHMMSS one-api.db
./start.command
```

> 数据库只回滚有破坏性 schema 变更时才需要。一般小 bug fix 不要回滚 DB，避免丢期间数据。

## 5. 多实例 / 多账户

需要在同一台机器跑两份隔离环境（如：自己用 + 给朋友试），最简单：

```bash
# 复制整个运行体目录
cp -r <REPO> <STAGING_REPO>     # 或 git clone <REPO_URL> <STAGING_REPO>

# 改启动脚本里的端口
sed -i '' 's/--port 3000/--port 3100/' <STAGING_REPO>/start.command

cd <STAGING_REPO>
./start.command
```

两套数据完全独立。

## 6. 开机自启（macOS launchd）

写一个 plist：`~/Library/LaunchAgents/com.kevin.newapi.plist`

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>            <string>com.kevin.newapi</string>
  <key>ProgramArguments</key>
  <array>
    <string><REPO>/new-api-macos</string>
    <string>--port</string><string>3000</string>
    <string>--log-dir</string><string><REPO>/logs</string>
  </array>
  <key>WorkingDirectory</key> <string><REPO></string>
  <key>RunAtLoad</key>        <true/>
  <key>KeepAlive</key>        <true/>
  <key>StandardOutPath</key>  <string><REPO>/logs/launchd.out.log</string>
  <key>StandardErrorPath</key><string><REPO>/logs/launchd.err.log</string>
</dict>
</plist>
```

加载：
```bash
launchctl load ~/Library/LaunchAgents/com.kevin.newapi.plist
launchctl list | grep newapi
```

卸载：`launchctl unload ~/Library/LaunchAgents/com.kevin.newapi.plist`

## 7. Linux systemd（如果搬到 VPS）

`/etc/systemd/system/new-api.service`：

```ini
[Unit]
Description=New API (pool fork)
After=network.target

[Service]
User=newapi
WorkingDirectory=/opt/new-api
ExecStart=/opt/new-api/new-api-linux --port 3000 --log-dir /opt/new-api/logs
Restart=on-failure
RestartSec=5
StandardOutput=append:/var/log/new-api/stdout.log
StandardError=append:/var/log/new-api/stderr.log

[Install]
WantedBy=multi-user.target
```

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now new-api
sudo systemctl status new-api
sudo journalctl -u new-api -f
```

> Linux 上需要重新编：`GOOS=linux GOARCH=amd64 go build -o new-api-linux .`。

## 8. 健康检查

```bash
# 基本存活
curl http://localhost:3000/api/status

# 号池总览（需 admin token）
TOKEN="<管理员 token>"
curl http://localhost:3000/api/pool/overview \
  -H "Authorization: Bearer $TOKEN"

# 工作 worker 状态
curl http://localhost:3000/api/pool/worker/status \
  -H "Authorization: Bearer $TOKEN"
```

返回 200 + JSON 即正常。如果一直 502 / 连不上，看 `logs/oneapi-*.log` 最后 50 行。
