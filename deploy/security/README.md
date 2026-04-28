# 安全加固

号池服务最大的财务风险来自**密钥泄漏**和**未授权访问**。这里覆盖：

1. 网络层：Cloudflare / SSH / 防火墙
2. 应用层：管理后台 2FA / API 域名隔离
3. 密钥管理：Vault / 密钥轮换
4. 审计：操作日志 / 入侵检测

## 检查清单

- [ ] 已跑 [`scripts/ssh-harden.sh`](./scripts/ssh-harden.sh)
- [ ] 已部署 [`vault/docker-compose.vault.yml`](./vault/docker-compose.vault.yml)
- [ ] 上游 Key 已迁入 Vault（不再明文进 DB）
- [ ] 管理后台单独域名 `admin.example.com` 走 Cloudflare Access
- [ ] Cloudflare Authenticated Origin Pulls 已开
- [ ] fail2ban 已装并配 [`fail2ban/jail.local`](./fail2ban/jail.local)
- [ ] crontab 已加密钥轮换提醒（季度）
- [ ] 备份加密 + 异地（已在 `scripts/backup.sh`）

## 网络拓扑

```
Internet
    ↓
Cloudflare（WAF + Rate Limit + Bot Fight）
    ↓ Authenticated Origin Pulls
Caddy（only allow CF IPs in firewall）
    ↓
new-api-1, new-api-2 (内网)
    ↓
postgres / redis (内网，无公网)
```

## 密钥分级

| 等级 | 物 | 存放 | 轮换 |
|---|---|---|---|
| **L0 极端敏感** | DB master 密码、`CRYPTO_SECRET`、Vault root token | Vault + 密码管理器（1Password Business） | 半年 |
| **L1 敏感** | 上游 API Key、OAuth refresh、Stripe secret | Vault | 季度 |
| **L2 一般** | new-api `SESSION_SECRET`、Redis 密码 | .env（加密磁盘） + Git-crypt | 半年 |
| **L3 公开** | Caddy CSP、Prometheus 配置 | Git 明文 | - |

## 文档清单

- [`ssh.md`](./ssh.md)：SSH 加固完整步骤
- [`vault.md`](./vault.md)：Vault 部署与上游 Key 迁移
- [`cloudflare.md`](./cloudflare.md)：Cloudflare WAF/Access 配置
- [`key-rotation.md`](./key-rotation.md)：季度密钥轮换 SOP
- [`audit-log.md`](./audit-log.md)：审计日志规范
