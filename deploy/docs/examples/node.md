# Node.js / TypeScript 完整示例

## 安装

```bash
npm install openai @anthropic-ai/sdk
```

## 环境变量

```bash
export AITR_BASE_URL=https://api.example.com
export AITR_API_KEY=sk-xxxxxxxxxxxxxxxxxxxxxxxx
```

## 1. OpenAI 协议

### 基础

```typescript
import OpenAI from "openai";

const client = new OpenAI({
  apiKey: process.env.AITR_API_KEY!,
  baseURL: `${process.env.AITR_BASE_URL}/v1`,
});

const resp = await client.chat.completions.create({
  model: "gpt-4o-mini",
  messages: [{ role: "user", content: "Hello" }],
});
console.log(resp.choices[0].message.content);
```

### 流式

```typescript
const stream = await client.chat.completions.create({
  model: "gpt-4o-mini",
  messages: [{ role: "user", content: "讲个长故事" }],
  stream: true,
});
for await (const chunk of stream) {
  process.stdout.write(chunk.choices[0].delta.content || "");
}
```

### Function Calling

```typescript
const resp = await client.chat.completions.create({
  model: "gpt-4o",
  messages: [{ role: "user", content: "北京天气如何？" }],
  tools: [{
    type: "function",
    function: {
      name: "get_weather",
      description: "Get current weather",
      parameters: {
        type: "object",
        properties: { city: { type: "string" } },
        required: ["city"],
      },
    },
  }],
});

const call = resp.choices[0].message.tool_calls?.[0];
console.log(call?.function.name, call?.function.arguments);
```

### Vision

```typescript
import { readFileSync } from "fs";
const b64 = readFileSync("img.png").toString("base64");

const resp = await client.chat.completions.create({
  model: "gpt-4o",
  messages: [{
    role: "user",
    content: [
      { type: "text", text: "图里是什么？" },
      { type: "image_url", image_url: { url: `data:image/png;base64,${b64}` } },
    ],
  }],
});
console.log(resp.choices[0].message.content);
```

### 重试 / 错误处理

```typescript
async function callWithRetry(fn: () => Promise<any>, max = 5): Promise<any> {
  for (let i = 0; i < max; i++) {
    try {
      return await fn();
    } catch (e: any) {
      const status = e?.status;
      if (status === 429 || (status >= 500 && status < 600)) {
        await new Promise(r => setTimeout(r, Math.min(2 ** i * 1000, 30_000)));
        continue;
      }
      throw e;
    }
  }
  throw new Error("max retries exceeded");
}

const resp = await callWithRetry(() =>
  client.chat.completions.create({
    model: "gpt-4o-mini",
    messages: [{ role: "user", content: "hi" }],
  })
);
```

## 2. Anthropic 协议

```typescript
import Anthropic from "@anthropic-ai/sdk";

const anthropic = new Anthropic({
  apiKey: process.env.AITR_API_KEY!,
  baseURL: process.env.AITR_BASE_URL,
});

const resp = await anthropic.messages.create({
  model: "claude-sonnet-4-5",
  max_tokens: 1024,
  messages: [{ role: "user", content: "解释 RAG" }],
});
console.log((resp.content[0] as any).text);
```

## 3. LangChain.js

```typescript
import { ChatOpenAI } from "@langchain/openai";

const llm = new ChatOpenAI({
  apiKey: process.env.AITR_API_KEY,
  configuration: { baseURL: `${process.env.AITR_BASE_URL}/v1` },
  modelName: "gpt-4o-mini",
});

const resp = await llm.invoke("Hello");
console.log(resp.content);
```

## 4. 浏览器使用（注意安全）

> ⚠️ **不要在浏览器代码里直接放 sk- key**！这会被任何用户提取。
> 浏览器只能调你**自有后端**，由后端代理到我们的 API。

后端示例（Express）：

```typescript
import express from "express";
import OpenAI from "openai";

const app = express();
app.use(express.json());

const client = new OpenAI({
  apiKey: process.env.AITR_API_KEY!,
  baseURL: `${process.env.AITR_BASE_URL}/v1`,
});

app.post("/api/chat", async (req, res) => {
  // 1. 鉴权你的用户（你的应用层）
  // 2. 调我们的 API
  const resp = await client.chat.completions.create({
    model: "gpt-4o-mini",
    messages: req.body.messages,
  });
  res.json(resp);
});

app.listen(3000);
```

## 5. Edge / Cloudflare Workers

```typescript
import OpenAI from "openai";

export default {
  async fetch(req: Request, env: Env): Promise<Response> {
    const client = new OpenAI({
      apiKey: env.AITR_API_KEY,
      baseURL: `${env.AITR_BASE_URL}/v1`,
    });

    const body = await req.json<any>();
    const resp = await client.chat.completions.create({
      model: "gpt-4o-mini",
      messages: body.messages,
    });
    return Response.json(resp);
  },
};
```

## 6. 异步并发

```typescript
const tasks = Array.from({ length: 20 }, (_, i) =>
  client.chat.completions.create({
    model: "gpt-4o-mini",
    messages: [{ role: "user", content: `${i}+${i}=` }],
  })
);
const results = await Promise.all(tasks);
results.forEach(r => console.log(r.choices[0].message.content));
```

注意 RPM/TPM 限制，避免一次发太多。
