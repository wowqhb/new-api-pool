# Email Adapter

抽象接口 [`base.py::EmailProvider`](./base.py)，三个实现：

| 实现 | 优势 | 劣势 |
|---|---|---|
| `cloudflare.py` | 自有域名 + catch-all + 永久邮箱 + 零成本 | 需要自有域名 + CF 账号 |
| `imap.py` | 任何 SMTP 服务（自建 / Gmail / Zoho 等）| 单邮箱，需要轮换 |
| `mailtm.py` | 临时邮箱，零配置 | 部分平台已封 + 邮箱寿命短 |

## 使用

```python
from adapters.email import get_provider

email = await get_provider().request_address(prefix="reg")
# 收信
code = await get_provider().wait_for(email, regex=r"verification code:\s*(\d{6})", timeout=120)
```

## CF Email Routing 配置（最佳实践）

1. 注册一个一次性域名（如 mailbox.example.com）
2. 在 Cloudflare DNS 加 MX 记录
3. 启用 Email Routing → Catch-all：转发到自己的真实邮箱
4. 在 CF API 创建 Token：`Account.Email Routing Rules: Edit`

我们这里收信走 IMAP（连真实邮箱），发件平台不重要。

## IMAP 注意

- Gmail 必须开"App Password"或 OAuth（密码登录已禁用）
- 自建邮箱（mailcow / Mail-in-a-Box）IMAP 默认 IDLE 支持
- imap-tools 的 `IDLE` 比每秒轮询省 100x 流量

## TempMail 注意

- mail.tm 公开 API：免费但**注册时被各平台 blacklist 概率极高**
- 建议**只用作降级备份**，不要主用

## 抗风控建议

- 每号一个**唯一邮箱地址**（哪怕 catch-all 全部转发到一个收件箱）
- 邮箱地址**不要按 `name+random@`** 模式（Google 等平台识别为同一账号）
- 用真实域名（不是 `tempmail.com` 这类）
- 邮箱注册时间 ≥ 30 天后才用（自有域名不存在这个问题）
