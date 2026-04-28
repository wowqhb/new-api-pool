# Runbook 05：主域名被墙 / 被劫持

**P1** · 影响：大陆用户 100% 不可达 · 目标 MTTR：30 分钟内切完备用域名

## 现象 / 触发

- 国内拨测掉零（[ITDOG](https://www.itdog.cn) 测一下立刻知道）
- 海外用户正常，大陆用户全部 timeout / DNS 劫持
- Telegram 群大量"打不开"反馈

## 前置准备（事前必做）

**这件事不是发生时才处理的，事前必须备好**：

- [ ] 至少注册 **3 个不同后缀的域名**（.com / .net / .org / .io 各一）
- [ ] 用 **不同注册商**（Cloudflare / Namecheap / Porkbun 至少 2 家）
- [ ] DNS 用 Cloudflare 之外再加一家（DNSPod / Hurricane Electric）
- [ ] Caddy 配置里**全部域名都注册好证书**，平时用主域名，备用静默
- [ ] 客户端 SDK 支持 **多 base_url 自动切换**（或提前公告）

## 应急流程

1. **确认是被墙不是 DNS 故障**：
   ```bash
   # 海外服务器解析
   dig api.your-domain.com @8.8.8.8

   # 国内服务器解析
   dig api.your-domain.com @114.114.114.114

   # 国内 ITDOG 拨测：https://www.itdog.cn/http
   ```
   如果国内 dig 不返或返垃圾 IP → 被墙/劫持。

2. **激活备用域名**：
   - Cloudflare DNS → 备用域名 → A 记录指向源站
   - Caddyfile 里启用备用域名站点（如果不在）
   - `docker compose exec caddy caddy reload`

3. **公告**：
   - 状态页：**主域名访问异常，请改用备用域名 api-bk.your-domain.com**
   - Telegram 频道：群发
   - 邮件群发付费用户（提前要有列表导出）

4. **客户端切流**：
   - 如果你提供了 SDK，让它从配置中心拉新 base_url
   - 没 SDK 的，文档里写"换成新的 base_url"

## 长期对策

- **DoH / DoT**：客户端接 [https://1.1.1.1/dns-query](https://1.1.1.1/dns-query)，绕过运营商 DNS 劫持
- **多域名轮询**：客户端内置 3-5 个域名，DNS 失败自动切下一个
- **国内反向加速**：阿里云 DCDN / 腾讯云 EO（要备案）
- **永远不要把所有用户绑死在 1 个域名上**

## 事后复盘

- 备用域名切流耗时：
- 用户流失：
- 是否需要做 DoH 客户端：
