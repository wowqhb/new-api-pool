# Runbook 04：Cloudflare 误拦 / 触发挑战

**P1** · 影响：部分用户 / 区域无法访问 · 目标 MTTR：≤ 15 分钟

## 现象 / 触发

- 用户反馈"打不开"或"被要求做验证"
- Caddy 入站日志正常（说明请求没到源站）
- Cloudflare Analytics 看到大量 challenge / block

## 第一时间动作

1. **登录 Cloudflare 看 Analytics → Security**：
   - 是否触发了某条 WAF 规则
   - 是否 Bot Fight Mode 太激进
   - 是否 Rate Limiting Rules 拦了正常用户

2. **临时降级**（5 分钟止血）：
   - Bot Fight Mode → 关
   - Security Level → Medium 或 Essentially Off
   - Under Attack Mode → 关（如果之前手抖开了）
   - 受影响 WAF Rule → Disable / 改成 Log only

3. **如果是误拦特定 IP 段**：
   - Security → WAF → Tools → IP Access Rules
   - 加白名单：用户 IP 段 → Allow

## 如果 Cloudflare 自身挂了

历史上发生过几次。备用方案：

```bash
# 1. 把 DNS 切到不走 Cloudflare 的备用域名（提前要在另一家 DNS 注册备用域）
# 例：api2.your-domain.com 直连源站 IP

# 2. 在 Caddyfile 临时加上备用域
# 假设源站 IP 已经允许 0.0.0.0/0:443（你应该有备用证书）
# 改 Caddyfile 加：
#   api2.your-domain.com { reverse_proxy ... }
docker compose -f docker-compose.prod.yml exec caddy caddy reload --config /etc/caddy/Caddyfile

# 3. Telegram 公告改用备用域
```

⚠️ 长期靠 Cloudflare 但没有备用域名的人迟早出事。**至少有 1 个备用域名 + 直连方案。**

## 中国大陆访问问题

Cloudflare 在国内不稳定（不同省份/运营商不同）。如果你大陆用户多：

- Plan A：国内备用域名走 阿里云/腾讯云 国内 CDN（要 ICP 备案）
- Plan B：CloudFront 美西节点 + Cloudflare 配合
- Plan C：直接用国内云商的反向加速（如腾讯云 EO、阿里云 DCDN）

每月做一次国内可用性测试（拨测：[ITDOG](https://www.itdog.cn) / [boce.com](https://www.boce.com)）。

## 事后复盘

- 是哪条 Cloudflare 规则拦了正常用户？
- 怎么避免下次同类事故？（先 Log only 1 周再 Block）
