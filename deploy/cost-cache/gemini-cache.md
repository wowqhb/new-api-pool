# Gemini Context Cache

Gemini 的 prompt cache 不像 Anthropic 那样在请求里直接标 `cache_control`，需要：

1. 显式调 [`cachedContents.create`](https://ai.google.dev/gemini-api/docs/caching) 创建一个缓存对象
2. 后续请求引用该 `cachedContent` 名

## 代价

- 创建：缓存内容的 token 一次性收 input 价 × 0.25 + 存储费 / hour
- 命中：免费 input
- 最低门槛：32k token（Gemini 2.5 Pro）/ 4k token（Flash）

## 适用场景

- 长系统提示（RAG / agentic 系统）
- 工具调用的长 schema
- 重复的代码上下文（IDE 集成）

## 实现思路

在 router-sidecar 中：

1. 检测 system message 长度 ≥ 4k token
2. SHA1 hash system + tools → 找现有缓存（Redis）
3. 没有 → 调 Gemini cachedContents.create → 存 Redis 映射
4. 改请求体把 system 删掉，加 `cachedContent: <name>`
5. 调 Gemini chat
6. 监控：缓存命中率、缓存 token 量、节省金额

## 参考实现框架

```python
import hashlib
import google.generativeai as genai

async def maybe_cache_system(payload, redis):
    system = payload.get("system") or ""
    tools = payload.get("tools") or []
    if estimate_tokens(system) < 4000:
        return payload

    h = hashlib.sha1(json.dumps([system, tools], sort_keys=True).encode()).hexdigest()
    cache_key = f"gemini_cache:{h}"

    cache_name = await redis.get(cache_key)
    if cache_name:
        cache_name = cache_name.decode()
    else:
        # 创建
        cache = await create_cached_content(
            model=payload["model"],
            system_instruction=system,
            tools=tools,
            ttl_seconds=3600,
        )
        cache_name = cache.name
        await redis.setex(cache_key, 3500, cache_name)  # 略小于 ttl

    payload.pop("system", None)
    payload.pop("tools", None)
    payload["cachedContent"] = cache_name
    return payload
```

## 注意

- ttl 到期后引用会 404，需要 catch 后重建
- 不同 model（pro / flash）缓存不可复用
- 多区域部署时 cachedContent 是 region-bound
