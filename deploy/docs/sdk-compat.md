# SDK / 客户端适配表

> **核心原则**：本服务兼容 OpenAI / Anthropic / Google 三套官方 SDK 协议。
> 多数情况只需改 `base_url`/`api_base` 即可。

## 协议矩阵

| 客户端 | 协议 | base_url | 备注 |
|---|---|---|---|
| OpenAI Python/JS | OpenAI | `https://api.example.com/v1` | 完美兼容 |
| Anthropic Python/JS | Anthropic | `https://api.example.com` | 通过我们的兼容层 |
| Google Generative AI | Gemini | `https://api.example.com/v1beta` | 部分功能（Tool）有限制 |
| Vertex AI SDK | ❌ | — | Vertex 用 Google IAM，我们不支持 |

## 知名客户端配置

### 桌面 GUI 客户端

| 客户端 | 系统 | 配置位置 | base_url |
|---|---|---|---|
| **Cherry Studio** | macOS/Win/Linux | 设置 → 自定义 OpenAI | `https://api.example.com` |
| **NextChat** | Web/桌面 | 设置 → API Provider → OpenAI | `https://api.example.com` |
| **LobeChat** | Web/桌面 | 设置 → 语言模型 → OpenAI | `https://api.example.com/v1` |
| **Open WebUI** | Web | Settings → Connections | `https://api.example.com/v1` |
| **AnythingLLM** | 桌面 | LLM Preference → OpenAI | `https://api.example.com/v1` |
| **Chatbox** | 桌面 | Settings → AI Provider → OpenAI API | `https://api.example.com/v1` |
| **Jan** | 桌面 | Settings → OpenAI | `https://api.example.com/v1` |

### 编辑器 / IDE 集成

| 客户端 | 配置位置 | base_url |
|---|---|---|
| **Cursor** | Settings → Models → Override OpenAI Base URL | `https://api.example.com/v1` |
| **Continue.dev** | `~/.continue/config.json` → models[].apiBase | `https://api.example.com/v1` |
| **Cline / Roo Code** | API Provider: OpenAI Compatible | `https://api.example.com/v1` |
| **Copilot Chat** | ❌（Microsoft 强制 Azure，无法替换）| — |
| **Aider** | `--openai-api-base https://api.example.com/v1` | |
| **Codeium** | ❌ 不支持自定义 endpoint | — |

### 框架

| 框架 | 配置 |
|---|---|
| **LangChain** | `ChatOpenAI(base_url="https://api.example.com/v1", api_key="sk-...")` |
| **LlamaIndex** | `OpenAI(api_base="https://api.example.com/v1", ...)` |
| **AutoGen** | `config_list=[{"model": "gpt-4o", "base_url": "...", "api_key": "..."}]` |
| **CrewAI** | 内部用 LiteLLM，配 LiteLLM 的 base |
| **Semantic Kernel** | `KernelBuilder().AddOpenAIChatCompletion(endpoint=...)` |

### 路由 / 多模型工具

| 工具 | 配置 |
|---|---|
| **LiteLLM** | `--api_base https://api.example.com/v1` |
| **OpenRouter** | ❌ 不能套用 |
| **One-API / new-api（你的源版）** | 用我们的 key 直接调，不要再嵌一层 |

### 命令行 / 脚本

```bash
# 在全局 env 设一次，所有 OpenAI Python 自动用
export OPENAI_BASE_URL="https://api.example.com/v1"
export OPENAI_API_KEY="sk-xxx"

# 验证
python -c "from openai import OpenAI; print(OpenAI().models.list())"
```

## 协议转换说明

我们把 Anthropic / Google 协议都**双向兼容**到 OpenAI 协议：

```
您的客户端              我们网关          上游
─────────              ─────────         ─────────
OpenAI 格式  ────────→  → OpenAI 上游：直传
                       → Anthropic 上游：协议转换
                       → Gemini 上游：协议转换

Anthropic 格式 ──────→  → Anthropic 上游：直传
                       → OpenAI 上游：协议转换

Gemini 格式  ────────→  → Gemini 上游：直传
                       → OpenAI 上游：协议转换
```

> 💡 协议转换有少量损失（如 OpenAI 的 `function_call` ↔ Anthropic `tool_use`），具体差异见各模型说明。

## 已知不兼容

| 功能 | 是否支持 | 备注 |
|---|---|---|
| OpenAI Assistants API（v1）| ❌ | 复杂依赖，建议用 chat.completions |
| OpenAI Realtime API（WebSocket）| ⚠️ Beta | 仅部分上游，详见 `realtime.md` |
| Anthropic Vision | ✅ | base64 / URL 都支持 |
| Anthropic Computer Use | ⚠️ Beta | 部分模型 |
| Gemini Multimodal Live | ❌ | 上游接口不稳定，暂不开放 |
| Gemini Embeddings | ✅ | OpenAI 协议路由到 Gemini embedding |
| Function Calling / Tool Use | ✅ | 跨协议兼容 |
| Stream | ✅ | OpenAI / Anthropic / Gemini 都支持 |
| 图片输入 | ✅ | 自动转换为目标模型协议 |

## 故障排查清单

调不通的优先级：
1. **base_url 是否正确**（含 `/v1` ？大小写？）
2. **api_key 格式**（Bearer 前缀？多空格？）
3. **模型名称**（`gpt-4o` vs `gpt-4-o` 还是 `gpt-4-turbo`？）
4. **响应 status code** + body
5. **`X-Request-Id`**（提工单时附）
6. 切到 Postman 集合复测（排除 SDK 问题）

如以上都对仍 fail → [/docs/errors](./error-codes.md) 对照错误码 → 提工单。
