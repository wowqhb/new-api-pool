# 5 分钟快速上手 / Quickstart

> 我们的 API 与 OpenAI / Anthropic / Google 官方 SDK **完全兼容**，**只需改 `base_url` 即可**。

## 第 1 步：注册 + 充值 + 拿 Token

1. 注册账号 [{{auth_url}}]
2. 充值（USDT / 信用卡 / 兑换码）
3. 「账户中心 → API Token」 → "新建" → 复制 `sk-xxxx...`

## 第 2 步：选择 SDK

### Python（OpenAI 兼容）

```bash
pip install openai
```

```python
from openai import OpenAI

client = OpenAI(
    api_key="sk-xxx",                       # 你的 Token
    base_url="https://api.example.com/v1",  # 改这里！
)

resp = client.chat.completions.create(
    model="gpt-4o",
    messages=[{"role": "user", "content": "你好"}],
)
print(resp.choices[0].message.content)
```

### Python（Anthropic 兼容）

```bash
pip install anthropic
```

```python
from anthropic import Anthropic

client = Anthropic(
    api_key="sk-xxx",
    base_url="https://api.example.com",  # 不带 /v1
)

resp = client.messages.create(
    model="claude-sonnet-4-5",
    max_tokens=1024,
    messages=[{"role": "user", "content": "你好"}],
)
print(resp.content[0].text)
```

### Node.js（OpenAI 兼容）

```bash
npm install openai
```

```typescript
import OpenAI from "openai";

const client = new OpenAI({
  apiKey: "sk-xxx",
  baseURL: "https://api.example.com/v1",
});

const resp = await client.chat.completions.create({
  model: "gpt-4o",
  messages: [{ role: "user", content: "你好" }],
});
console.log(resp.choices[0].message.content);
```

### curl

```bash
curl https://api.example.com/v1/chat/completions \
  -H "Authorization: Bearer sk-xxx" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "gpt-4o",
    "messages": [{"role":"user","content":"你好"}]
  }'
```

### LangChain

```python
from langchain_openai import ChatOpenAI

llm = ChatOpenAI(
    api_key="sk-xxx",
    base_url="https://api.example.com/v1",
    model="gpt-4o",
)
print(llm.invoke("你好").content)
```

## 第 3 步：流式输出

```python
stream = client.chat.completions.create(
    model="gpt-4o",
    messages=[{"role": "user", "content": "讲个长故事"}],
    stream=True,
)
for chunk in stream:
    if chunk.choices[0].delta.content:
        print(chunk.choices[0].delta.content, end="", flush=True)
```

## 第 4 步：错误处理

```python
from openai import OpenAIError, RateLimitError, APIConnectionError
import time

for attempt in range(3):
    try:
        resp = client.chat.completions.create(...)
        break
    except RateLimitError:
        time.sleep(2 ** attempt)
    except APIConnectionError:
        time.sleep(2 ** attempt)
    except OpenAIError as e:
        print(f"业务错误：{e}")
        break
```

完整错误码 → [errors.md](./error-codes.md)

## 常见客户端配置

| 客户端 | base_url 配置 |
|---|---|
| **Cherry Studio** | 设置 → 自定义 OpenAI 服务 → API Host: `https://api.example.com` |
| **NextChat** | 设置 → API Provider → Base URL: `https://api.example.com` |
| **LobeChat** | 设置 → 语言模型 → OpenAI → API 代理：`https://api.example.com/v1` |
| **Open WebUI** | Settings → Connections → OpenAI API: `https://api.example.com/v1` |
| **Cline / Roo Code (VSCode)** | Settings → API Provider OpenAI Compatible: `https://api.example.com/v1` |
| **Cursor** | Settings → Models → Override OpenAI Base URL: `https://api.example.com/v1` |
| **Continue.dev** | config.json → `apiBase: "https://api.example.com/v1"` |
| **LiteLLM** | `--api_base https://api.example.com/v1` |

详细 → [sdk-compat.md](./sdk-compat.md)

## 下一步

- [模型清单与价格](./models.md)
- [错误码字典](./error-codes.md)
- [API 完整参考](./api-reference.md)
- [Postman 集合](./postman/)
- [示例代码](./examples/)
