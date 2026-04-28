# 信息不足请求补充（标准回复）

---

您好 {{user_name}}，

收到您的反馈！为了快速帮您定位问题，请补充以下信息：

## 必需信息

### 调用相关
- **`X-Request-Id`**：您的失败请求响应 header 里的 ID（每次响应都有）
- **失败时间**：精确到分钟，含时区（如 `2026-04-27 14:32 UTC+8`）
- **完整错误响应 body**（截图或粘贴文字）
- **使用的模型名**（如 `gpt-4o`）
- **base_url**（您配置的 API 地址）

### 代码片段
请贴一段**最小复现代码**（请脱敏 API Key，仅留前 4 后 4 位）：
```python
client = OpenAI(api_key="sk-xxxx...xxxx", base_url="...")
client.chat.completions.create(...)
```

### 客户端信息
- 操作系统（如 macOS 14 / Windows 11 / Linux）
- 客户端类型：浏览器 / 命令行 / SDK / 第三方应用
- SDK 版本：`pip show openai` / `npm list openai`

## 可选信息（有助于诊断）

- 是否使用代理（Cloudflare WARP / VPN / 公司网络）
- 是同一段时间所有调用都失败，还是偶发？
- 之前可以用，从什么时间开始失败？
- 同一账号其它 Token 调用是否正常？

## 为什么需要这些

- `request_id` 让我们直接定位到具体一次调用的全部内部日志
- 时间精确便于关联上游故障公告
- 代码片段帮助识别是否客户端问题（错误的 base_url / Token 多了空格）

填好后直接回复本工单即可。我们等您。

祝好，
[[客服小 X]]
