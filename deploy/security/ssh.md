# SSH 加固

## 目标

- 禁密码登录，只允许密钥
- 改默认端口（防扫描）
- 限制登录用户
- fail2ban 防暴破
- 双因子（可选，TOTP）

## 一键脚本

```bash
sudo bash scripts/ssh-harden.sh
```

执行前**必须**确保：

1. 你已经用 SSH key 能成功登录服务器（**否则改完就锁外面**）
2. 当前 shell 在 root 或 sudoer 用户上
3. **同时开第二个 SSH 会话**，作为"保命"窗口

## 配置（/etc/ssh/sshd_config 关键项）

```sshconfig
Port 23456                       # 改默认端口
Protocol 2
PermitRootLogin no               # 不允许 root 直接登录
PasswordAuthentication no        # 禁密码
PubkeyAuthentication yes
ChallengeResponseAuthentication no
UsePAM yes
AllowUsers ops admin             # 白名单用户
MaxAuthTries 3
LoginGraceTime 30
ClientAliveInterval 300
ClientAliveCountMax 2
X11Forwarding no
AllowTcpForwarding local         # 用于 Vault local proxy
AllowAgentForwarding no
```

## 防火墙（ufw）

```bash
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow 23456/tcp comment 'SSH custom'
sudo ufw allow 80/tcp comment 'HTTP for cert renew'
sudo ufw allow 443/tcp comment 'HTTPS'
# 内网 docker 不需要在 ufw 开
sudo ufw --force enable
sudo ufw status verbose
```

## TOTP 双因子（可选）

```bash
sudo apt install libpam-google-authenticator
google-authenticator    # 每个用户跑一次，扫码进 Authy / 1Password

# /etc/pam.d/sshd 加：
# auth required pam_google_authenticator.so

# /etc/ssh/sshd_config 改：
# ChallengeResponseAuthentication yes
# AuthenticationMethods publickey,keyboard-interactive
```

## 日志监控

```bash
# /var/log/auth.log 重要事件接 Loki / Promtail
# 已经在 monitoring/loki/promtail-config.yml 默认抓 /var/log/syslog
```

告警关键词：
- `Failed password`（应该非常少，因为禁密码）
- `Invalid user`（爆破）
- `Accepted publickey for ...`（成功登录，记录到审计）
