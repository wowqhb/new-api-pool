# Python 完整示例

## 安装

```bash
pip install openai anthropic google-genai
```

## 环境变量

```bash
export AITR_BASE_URL="https://api.example.com"
export AITR_API_KEY="sk-xxxxxxxxxxxxxxxxxxxxxxxx"
```

## 1. OpenAI 协议（推荐，最稳）

### 基础调用

```python
import os
from openai import OpenAI

client = OpenAI(
    api_key=os.environ["AITR_API_KEY"],
    base_url=f"{os.environ['AITR_BASE_URL']}/v1",
)

resp = client.chat.completions.create(
    model="gpt-4o-mini",
    messages=[{"role": "user", "content": "用 1 句话解释熵增定律"}],
    temperature=0.5,
)
print(resp.choices[0].message.content)
print(f"用了 {resp.usage.total_tokens} tokens")
```

### 流式

```python
stream = client.chat.completions.create(
    model="gpt-4o-mini",
    messages=[{"role": "user", "content": "讲个长故事"}],
    stream=True,
)
for chunk in stream:
    if delta := chunk.choices[0].delta.content:
        print(delta, end="", flush=True)
```

### Function Calling

```python
tools = [{
    "type": "function",
    "function": {
        "name": "get_weather",
        "description": "Get current weather of a city",
        "parameters": {
            "type": "object",
            "properties": {"city": {"type": "string"}},
            "required": ["city"],
        },
    },
}]

resp = client.chat.completions.create(
    model="gpt-4o",
    messages=[{"role": "user", "content": "北京天气如何？"}],
    tools=tools,
)
tool_call = resp.choices[0].message.tool_calls[0]
print(tool_call.function.name, tool_call.function.arguments)
```

### Vision

```python
import base64
with open("img.png", "rb") as f:
    b64 = base64.b64encode(f.read()).decode()

resp = client.chat.completions.create(
    model="gpt-4o",
    messages=[{
        "role": "user",
        "content": [
            {"type": "text", "text": "图里是什么？"},
            {"type": "image_url", "image_url": {"url": f"data:image/png;base64,{b64}"}},
        ],
    }],
)
print(resp.choices[0].message.content)
```

### 错误处理 + 重试

```python
import time
from openai import OpenAI, RateLimitError, APIConnectionError, APIStatusError

def call_with_retry(client, **kwargs):
    for attempt in range(5):
        try:
            return client.chat.completions.create(**kwargs)
        except RateLimitError:
            wait = min(2 ** attempt, 30)
            print(f"429, wait {wait}s")
            time.sleep(wait)
        except APIConnectionError:
            time.sleep(2 ** attempt)
        except APIStatusError as e:
            if e.status_code >= 500:
                time.sleep(2 ** attempt)
                continue
            raise
    raise RuntimeError("max retries exceeded")
```

## 2. Anthropic 协议

```python
from anthropic import Anthropic

client = Anthropic(
    api_key=os.environ["AITR_API_KEY"],
    base_url=os.environ["AITR_BASE_URL"],
)

resp = client.messages.create(
    model="claude-sonnet-4-5",
    max_tokens=1024,
    messages=[{"role": "user", "content": "解释一下 RAG"}],
)
print(resp.content[0].text)
```

### Streaming

```python
with client.messages.stream(
    model="claude-sonnet-4-5",
    max_tokens=1024,
    messages=[{"role": "user", "content": "讲个长故事"}],
) as stream:
    for text in stream.text_stream:
        print(text, end="", flush=True)
```

## 3. LangChain

```python
from langchain_openai import ChatOpenAI
from langchain.schema import HumanMessage

llm = ChatOpenAI(
    api_key=os.environ["AITR_API_KEY"],
    base_url=f"{os.environ['AITR_BASE_URL']}/v1",
    model="gpt-4o-mini",
    temperature=0,
)

print(llm.invoke([HumanMessage(content="hi")]).content)
```

## 4. 异步 / 高并发

```python
import asyncio
from openai import AsyncOpenAI

async def call(client, prompt):
    resp = await client.chat.completions.create(
        model="gpt-4o-mini",
        messages=[{"role": "user", "content": prompt}],
    )
    return resp.choices[0].message.content

async def main():
    client = AsyncOpenAI(
        api_key=os.environ["AITR_API_KEY"],
        base_url=f"{os.environ['AITR_BASE_URL']}/v1",
    )
    tasks = [call(client, f"{i} 的平方") for i in range(20)]
    results = await asyncio.gather(*tasks)
    for r in results:
        print(r)

asyncio.run(main())
```

> ⚠️ 高并发请关注 RPM/TPM 限制；触发 429 请用上面的退避策略。

## 5. 嵌入向量

```python
resp = client.embeddings.create(
    model="text-embedding-3-small",
    input=["hello world", "你好世界"],
)
for emb in resp.data:
    print(len(emb.embedding))  # 1536
```

## 6. 实用：缓存 + 幂等

```python
import uuid

resp = client.chat.completions.create(
    model="gpt-4o-mini",
    messages=[{"role": "user", "content": "hi"}],
    extra_headers={
        "Idempotency-Key": str(uuid.uuid4()),
        "X-Trace-Id": "my-job-001",
    },
)
print(resp.headers.get("X-Cache"))  # HIT-L0 / HIT-L1 / MISS
```
