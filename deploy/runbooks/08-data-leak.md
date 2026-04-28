# Runbook 08：疑似数据泄漏

**P0** · 影响：用户信任 / 法律责任 · 目标：1 小时内完成第一阶段处置

## 触发场景（任一即触发）

- 安全工单："我的 token 在不该出现的地方"
- 监控发现异常活动：单一 IP 请求大量不同用户的 admin API
- 收到勒索邮件 / 威胁
- 上游通知 "你们的 Key 被滥用"
- Web shell / 不明 SSH 登录被发现

## 第一阶段：止血（1 小时内）

1. **隔离系统**：
   ```bash
   # 立即吊销所有用户 Token（强制重新登录）
   docker exec new-api-postgres psql -U newapi -d newapi -c "
     UPDATE tokens SET status = 3 WHERE status = 1;
     -- 强制所有用户重置 session
     UPDATE users SET access_token = NULL;
   "

   # 把对外 API 域名暂时关掉（管理后台还能进来处理）
   # 修改 Caddyfile 把 API 域名 reverse_proxy 改成 respond "503"
   # 或者直接：
   docker compose -f docker-compose.prod.yml stop new-api-1 new-api-2
   ```

2. **保留现场**：
   ```bash
   # 立刻 dump 数据库 + 抓所有日志快照
   bash scripts/backup.sh
   tar -czf evidence-$(date +%s).tar.gz logs/ data/
   # 拷贝到隔离的取证机器
   ```

3. **轮换所有密钥**：
   - 上游 Key：所有官方 Key、第三方 Key、OAuth refresh token 全部上去重新签
   - `CRYPTO_SECRET`：⚠️ 如果数据库被偷了，要换 → 需要重新录入所有上游 Key
   - 服务器：SSH key 重新生成、`fail2ban` 永久封可疑 IP
   - 域名/Cloudflare API Token：全部重置

4. **通知所有受影响用户**：
   - 邮件群发：发生了什么、影响范围、用户应该做什么（改密码/检查异常请求）
   - 状态页：公开声明（不公开会更糟）
   - 发现 24h 内必须发，**这是法律义务**（GDPR 等）

## 第二阶段：调查根因（24-72 小时）

1. **入侵路径分析**：
   ```bash
   # SSH 登录历史
   last -F | head -50
   journalctl -u sshd --since "7 days ago" | grep -i "accepted\|invalid"

   # 容器内异常
   docker exec new-api-1 ps aux
   docker exec new-api-1 ss -tlnp

   # 数据库异常查询
   docker exec new-api-postgres psql -U newapi -d newapi -c "
     SELECT query, calls, total_exec_time FROM pg_stat_statements
     ORDER BY calls DESC LIMIT 50;
   "
   ```

2. **日志取证**：把所有 logs/ 备份到独立机器（不要在被入侵机器上分析）

3. **找到注入点**：
   - new-api 漏洞 / 0-day → 先升级
   - 被偷的密钥 → 全部轮换（已做）
   - 内鬼 → 收回所有人的服务器/数据库权限，单独调查

## 第三阶段：报告（一周内）

- 内部：完整事故报告，时间线、根因、改进项、责任
- 外部：用户公告（信息透明 vs 公关 trade-off，咨询律师）
- 监管：根据司法管辖区，可能需要在 72h 内向监管报备（GDPR 强制）

## 法律 / 公关

- **不要**自己回复勒索（容易被讹）
- **不要**销毁证据（即使害怕被追责）
- 立即联系：法律顾问 / 公司高管 / 必要时报警
- 保留所有沟通记录

## 事后改进项（必做）

- [ ] 部署 WAF + IDS（如 [CrowdSec](https://www.crowdsec.net/)）
- [ ] 数据库静态加密（PG TDE 或 LUKS）
- [ ] 启用 PG audit logging
- [ ] 上 Vault 管密钥（事前的话能减少损失）
- [ ] 限制管理后台访问（IP 白名单 + 2FA + Cloudflare Access）
- [ ] 定期渗透测试（季度一次）
- [ ] 定期密钥轮换（季度一次）
