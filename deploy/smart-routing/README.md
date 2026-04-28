# 智能调度 sidecar

new-api 自带的 priority + weight 是**静态**的。这个 sidecar 实现：

1. **自适应权重**：每分钟根据真实 RT/成功率调整 weight
2. **阶梯回退**：classifier 决定是否需要大模型，先小后大
3. **跨分组重试**：official → claude-oauth → gemini-free
4. **请求改写**：注入 prompt cache 头、改 model 名等

## 架构

```
用户 → Caddy → smart-router (Python/FastAPI) → new-api → 上游
              │
              └── 读 new-api logs DB 算分 → 写 new-api API 改 weight
                  读语义缓存 → 命中直接返回
                  调 classifier 模型 → 决定路由
```

## 模式

### 模式 1：仅自适应权重（最简单）

不动 new-api 数据流，只**定时**调 new-api `/api/channel` 改 weight。

```bash
cd deploy/smart-routing
docker compose up -d weight-tuner

# 每分钟计算一次得分，写回 new-api
```

### 模式 2：sidecar 透明代理

把 sidecar 放 Caddy 和 new-api 中间：

```caddyfile
api.example.com {
    reverse_proxy /v1/* smart-router:8080  # 智能路由
    reverse_proxy /* new-api-1:3000 new-api-2:3000  # 其它直通
}
```

sidecar 把请求加工后转发给 new-api。

## 算法

### Adaptive Weight

```python
score = (
    success_rate ** 2          # 成功率（平方放大差距）
    * (1 / max(rt_p95, 0.5))   # RT 倒数（避免除零）
    * (1 - concurrency / max_concurrency)  # 拥挤惩罚
)

# 归一化为 0-100 weight
new_weight = int(score / max_score * 100)
new_weight = max(1, min(100, new_weight))   # 防 0 防过大
```

每分钟跑，跨多个时间窗口取移动平均，避免抖动。

### Cascading Fallback

```python
async def route_with_fallback(request, user_group):
    chain = build_fallback_chain(user_group, request.model)
    # vip 链: official → claude-oauth → gemini-free
    # default 链: claude-oauth → official → gemini-free → third-party
    # free 链: gemini-free → third-party

    for group in chain:
        try:
            resp = await call_new_api(request, group=group)
            if resp.status_code == 200:
                return resp
            if resp.status_code in (401, 403):  # 渠道死了
                continue
            if resp.status_code in (429, 502, 503, 504):  # 上游死了
                continue
            return resp  # 4xx 用户错误，不要重试
        except Exception as e:
            log.warn("group %s failed: %s", group, e)

    return error_response(503, "All upstream groups failed")
```

### Cost Cascade（小模型当 router）

```python
async def cascade_routing(request):
    # 用 gpt-4o-mini 评估这个 prompt 复杂度
    classifier_resp = await call_classifier(
        prompt=request.messages[-1].content,
        prompt="Rate the complexity 1-10. Output a single digit. ..."
    )
    complexity = int(classifier_resp.text.strip())

    if complexity < 4:
        request.model = "gemini-2.5-flash"   # 便宜
    elif complexity < 7:
        request.model = request.model        # 用户原选
    else:
        request.model = upgrade_model(request.model)  # 升级

    return await call_new_api(request)
```

权衡：
- 节省 30-50% 成本
- 增加 200-500ms 延迟（classifier 调用）
- 不适合 streaming（用户感知延迟）

## 实现

详见 [`weight-tuner/`](./weight-tuner/) 和 [`router-sidecar/`](./router-sidecar/)。
