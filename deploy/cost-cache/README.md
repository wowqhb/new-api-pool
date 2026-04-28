# 成本优化与缓存

## 三层缓存

```
请求 → L0 完全相同 → L1 语义相似 → L2 上游 prompt cache → 真实调用
```

| 层 | 命中率 | 节省 |
|---|---|---|
| L0 完全相同 | 5-15% | 100% |
| L1 语义相似 | 10-25% | 90%（embedding 成本）|
| L2 上游 prompt cache | 20-50% (system msg 长场景) | 50-90%（Anthropic）/ 50%（OpenAI）|

## L0：完全相同（new-api 内置）

只要在 `.env` 里：

```bash
CACHE_REDIS=true
CACHE_TTL=3600
```

new-api 会自动按请求 body 哈希缓存。

## L1：语义缓存（这一目录）

实现：
- 收到请求 → 提取最后一条 user message
- 调 embedding 模型获取向量
- Redis Vector Search 查近邻
- 距离 < threshold（如 0.05）→ 直接返回缓存的响应
- miss 才转给上游

```bash
cd deploy/cost-cache
docker compose -f docker-compose.cache.yml up -d

# 改 router-sidecar 把请求先经过 semantic-cache
```

详见 [`semantic-cache/`](./semantic-cache/)。

## L2：上游 Prompt Cache

每家上游协议不同，封装在请求改写中间件里：

### Anthropic

在请求中加 `cache_control` 字段：

```json
{
  "model": "claude-sonnet-4",
  "system": [
    {
      "type": "text",
      "text": "<长系统提示>",
      "cache_control": {"type": "ephemeral"}
    }
  ],
  "messages": [...]
}
```

每次缓存命中省 90% input cost。

### OpenAI

GPT-4 自动 prompt cache（自动命中，无需配置）。

通过响应头 `x-prompt-tokens-cached` 看命中：

```python
# 在 router-sidecar/middleware.py 统计
def parse_cache_hit(headers):
    return int(headers.get("x-prompt-tokens-cached", 0))
```

### Gemini

通过 `cachedContent` API 显式创建 cache，然后引用：

```json
{
  "cachedContent": "projects/.../cachedContents/abc123",
  "contents": [...]
}
```

实现复杂，详见 [`gemini-cache.md`](./gemini-cache.md)。

## 监控

加到 Prometheus：

- `semantic_cache_hits_total{layer="l0|l1|l2"}`
- `semantic_cache_savings_usd_total`

加到 Grafana：每日缓存命中率与节省金额。

## 实现位置

直接放进 router-sidecar 中间件链：

```
请求 → L0 (Redis hash lookup) → L1 (embedding + RediSearch) → L2 (rewrite for upstream cache) → upstream
```
