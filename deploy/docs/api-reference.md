# API Reference

## 端点

| 协议 | 端点 | 说明 |
|---|---|---|
| OpenAI | `POST /v1/chat/completions` | 聊天补全 |
| OpenAI | `POST /v1/embeddings` | 嵌入向量 |
| OpenAI | `POST /v1/images/generations` | 图像生成 |
| OpenAI | `POST /v1/audio/transcriptions` | 语音转文字 |
| OpenAI | `POST /v1/audio/speech` | 文字转语音 |
| OpenAI | `GET /v1/models` | 模型列表 |
| Anthropic | `POST /v1/messages` | Messages API |
| Anthropic | `POST /v1/messages/count_tokens` | 计算 token 数 |
| Gemini | `POST /v1beta/models/{model}:generateContent` | 生成内容 |
| Gemini | `POST /v1beta/models/{model}:streamGenerateContent` | 流式生成 |

## 认证

所有请求必须含：

```http
Authorization: Bearer sk-xxxxxxxxxxxxxxxxxxxxxxxx
Content-Type: application/json
```

## 通用响应头

| Header | 说明 |
|---|---|
| `X-Request-Id` | 请求唯一 ID（提工单必附）|
| `X-RateLimit-Limit` | 当前限速档位 |
| `X-RateLimit-Remaining` | 剩余可用次数 |
| `X-RateLimit-Reset` | 重置时间戳 |
| `X-Latency-Ms` | 网关侧总耗时 ms |
| `X-Channel-Group` | 命中的渠道分组 |
| `X-Cache` | `HIT-L0` / `HIT-L1` / `MISS` |

## OpenAI: Chat Completions

### Request

```http
POST /v1/chat/completions
```

```json
{
  "model": "gpt-4o",
  "messages": [
    { "role": "system", "content": "You are a helpful assistant." },
    { "role": "user", "content": "Hello!" }
  ],
  "temperature": 0.7,
  "max_tokens": 1024,
  "stream": false,
  "tools": [...],
  "tool_choice": "auto",
  "user": "your-end-user-id"
}
```

### Response（非流式）

```json
{
  "id": "chatcmpl-abc123",
  "object": "chat.completion",
  "created": 1735056000,
  "model": "gpt-4o",
  "choices": [
    {
      "index": 0,
      "message": {
        "role": "assistant",
        "content": "Hello! How can I help you?"
      },
      "finish_reason": "stop"
    }
  ],
  "usage": {
    "prompt_tokens": 22,
    "completion_tokens": 9,
    "total_tokens": 31
  }
}
```

### Response（流式 SSE）

```
data: {"id":"chatcmpl-...","choices":[{"delta":{"content":"Hello"}}]}

data: {"id":"chatcmpl-...","choices":[{"delta":{"content":"!"}}]}

data: [DONE]
```

## Anthropic: Messages

### Request

```http
POST /v1/messages
anthropic-version: 2023-06-01
```

```json
{
  "model": "claude-sonnet-4-5",
  "max_tokens": 1024,
  "messages": [
    { "role": "user", "content": "Hello!" }
  ],
  "system": "You are a helpful assistant.",
  "stream": false
}
```

### Response

```json
{
  "id": "msg_abc",
  "type": "message",
  "role": "assistant",
  "content": [{ "type": "text", "text": "Hello!" }],
  "model": "claude-sonnet-4-5",
  "stop_reason": "end_turn",
  "usage": {
    "input_tokens": 12,
    "output_tokens": 7
  }
}
```

## Gemini: Generate Content

### Request

```http
POST /v1beta/models/gemini-2.0-flash:generateContent
```

```json
{
  "contents": [
    { "role": "user", "parts": [{ "text": "Hello!" }] }
  ],
  "generationConfig": {
    "temperature": 0.7,
    "maxOutputTokens": 1024
  }
}
```

### Response

```json
{
  "candidates": [
    {
      "content": {
        "role": "model",
        "parts": [{ "text": "Hello!" }]
      },
      "finishReason": "STOP"
    }
  ],
  "usageMetadata": {
    "promptTokenCount": 4,
    "candidatesTokenCount": 2,
    "totalTokenCount": 6
  }
}
```

## 幂等性

为避免网络重试导致的重复扣费，建议加 `Idempotency-Key` header（推荐用 UUID）：

```http
Idempotency-Key: 550e8400-e29b-41d4-a716-446655440000
```

同一 key 24 小时内重复请求**返回缓存的响应**且**不重复扣费**。

## 自定义 Header

| Header | 说明 |
|---|---|
| `X-Channel-Group` | 强制路由到指定分组（仅 admin token 可用）|
| `X-Cache-Skip` | 跳过 L0/L1 缓存 |
| `X-Trace-Id` | 您自定义的追踪 ID（会出现在我方日志中以便对账）|

## 速率限制

每个 Token 有独立 RPM/TPM 限制（详见账户中心）。
触发 429 时响应 header 含：

```http
Retry-After: 5
X-RateLimit-Type: rpm
X-RateLimit-Reset: 1735056060
```

## 错误响应

所有错误统一格式：

```json
{
  "error": {
    "message": "...",
    "type": "...",
    "code": "AITR-401-NOTOKEN",
    "param": "authorization",
    "request_id": "req_abc"
  }
}
```

详见 [errors.md](./error-codes.md)。
