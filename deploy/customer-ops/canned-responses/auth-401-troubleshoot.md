# 401 Unauthorized 排查（标准回复）

变量：`{{user_name}}` `{{token_id}}` `{{request_id}}`

---

您好 {{user_name}}，

收到您的反馈，401 通常是**鉴权失败**。我们一起排查：

## 第 1 步：检查 Token 状态

我看了您的 Token #{{token_id}}：
- 状态：[启用 / 禁用 / 已过期]
- 余额：[XXX]
- IP 白名单：[启用 / 禁用]
- RPM/TPM 限制：[XXX]

【根据状态分支】

### A. Token 已禁用
您可以在「账户中心 → Token 管理」启用，或新建一个 Token。

### B. Token 已过期
请新建一个 Token。

### C. 余额为 0 或极少
请充值后重试。注意：401 可能因系统先扣费后报错，**这是正常的**。

### D. IP 白名单不匹配
您当前调用的 IP 可能不在白名单内。请：
1. 查看 [{{whatismyip_url}}] 获取您的真实出口 IP
2. 在 Token 设置里加进 IP 白名单（**含 CIDR 格式如 1.2.3.0/24**）

---

## 第 2 步：检查请求格式

请确认您的请求 header：

```
Authorization: Bearer sk-xxxxxxxxxxxxxxxxxxxxxxxx
Content-Type: application/json
```

**常见错误**：
- ❌ 没有 `Bearer ` 前缀
- ❌ Token 末尾有空格 / 换行
- ❌ 用了管理员 token（管理员 token 不能调 /v1）
- ❌ 复制错位（多复制了一个字符）

## 第 3 步：检查 base_url

| SDK | 默认 base_url | 需要改成 |
|---|---|---|
| OpenAI Python | https://api.openai.com/v1 | `https://api.example.com/v1` |
| Anthropic Python | https://api.anthropic.com | `https://api.example.com` |
| LangChain ChatOpenAI | OpenAI 默认 | 设 `base_url` 参数 |

## 第 4 步：从 Postman 直接试

下载我们的 [Postman 集合]([[postman_url]])，已预填好正确格式。如果 Postman 也 401，那是 Token 问题；如果 Postman OK 但您的代码 401，那是代码问题。

---

如果以上都试过仍 401，请提供：
- request_id（响应 header `X-Request-Id`）
- 请求时间（精确到分钟）
- 完整错误响应 body

我会深入排查。

祝好，
[[客服小 X]]
