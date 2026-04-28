# 审计日志规范

## 应该被审计的事件

### 管理员操作（new-api 后台）

- 用户管理：增/删/改/封禁/解封
- 渠道管理：创建/编辑/删除/启用/禁用
- 兑换码：批量生成/导出
- 系统设置：倍率/分组/限速等任一改动
- 登录：成功/失败/2FA 失败
- 退款：每次手动退款

### 系统级

- SSH 登录（成功/失败）
- sudo 命令
- Docker 容器启停
- 配置文件修改（用 auditd / inotify）

### 数据访问

- DB 直连查询（应该极少，记录每次）
- 备份导出 / 解密
- Vault 密钥读取

## 实施

### new-api 应用层

`new-api` 自带操作日志（管理员动作进 logs 表 type=4 等），但默认日志比较简陋。

强烈建议补上一个**审计 sidecar**：拦截 `/api/admin/*` 和 `/api/channel/*` 的写请求，落到独立的审计表：

```go
// 简化伪代码（middleware）
func AuditMiddleware(c *gin.Context) {
    if c.Request.Method != "GET" && strings.HasPrefix(c.Request.URL.Path, "/api/") {
        body, _ := io.ReadAll(c.Request.Body)
        // PII 脱敏后写审计 DB
        AuditDB.Insert(AuditLog{
            UserID:   GetCurrentUserID(c),
            Method:   c.Request.Method,
            Path:     c.Request.URL.Path,
            Body:     RedactPII(string(body)),
            IP:       c.ClientIP(),
            UA:       c.GetHeader("User-Agent"),
            Status:   c.Writer.Status(),
            ResponseLen: c.Writer.Size(),
            Time:     time.Now(),
        })
        c.Request.Body = io.NopCloser(bytes.NewBuffer(body))
    }
    c.Next()
}
```

### 系统级（auditd）

```bash
sudo apt install auditd

# /etc/audit/rules.d/99-aitransfer.rules
-w /etc/ssh/sshd_config -p wa -k ssh_config
-w /root -p rwxa -k root_dir
-w /home/ops -p wa -k ops_home
-w /etc/sudoers -p rw -k sudoers
-w /etc/sudoers.d/ -p rw -k sudoers
-w /var/log/auth.log -p wa -k auth_log

-a always,exit -F arch=b64 -S execve -F euid=0 -k root_exec
-a always,exit -F arch=b64 -S unlink -S rename -F dir=/var/lib/docker/volumes/ -k docker_data

sudo augenrules --load
sudo systemctl restart auditd
```

### 集中化（Loki）

- new-api audit logs → Loki label `service=audit`
- /var/log/audit/audit.log → promtail 抓 → Loki label `host=xxx,service=auditd`
- Grafana 加一个"管理员行为"看板（按动作 / 用户 / 时段聚合）

## 保留期

| 类型 | 至少保留 | 加密 |
|---|---|---|
| 财务（充值/消耗/退款）| 5-7 年 | ✅ |
| 管理员操作 | 2 年 | ✅ |
| 系统级（auditd）| 1 年 | ✅ |
| 用户对话 prompt/response | **不存或 ≤ 24h** | ✅ |
| Cloudflare WAF 日志 | 1 年（Logpush 到 R2）| ✅ |

## 异常检测

定期跑（每天 cron）：

```bash
bash scripts/audit-anomaly.sh
```

检测：
- 非营业时段的管理员操作
- 单管理员 1h 内 > 100 次操作
- 删大量数据的操作
- Vault 异常读取
- SSH 来源 IP 突变（地理位置）

异常 → Telegram 告警 + 暂时锁该管理员账号
