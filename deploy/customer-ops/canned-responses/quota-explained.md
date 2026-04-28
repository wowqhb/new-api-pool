# 429 速率限制 / 配额（标准回复）

---

您好，

429 错误来自**速率限制**或**配额耗尽**。错误响应里 `X-RateLimit-*` 头会指明具体原因：

- `X-RateLimit-Type: rpm` - 每分钟请求数超限
- `X-RateLimit-Type: tpm` - 每分钟 token 数超限
- `X-RateLimit-Type: daily` - 当日消费上限
- `X-RateLimit-Type: upstream` - 上游平台返回的 429（不在我方控制）

## 您当前的限速

| Token #{{token_id}} | 限制 |
|---|---|
| RPM | {{rpm}} |
| TPM | {{tpm}} |
| 日消费上限 | ${{daily_cap}} |

## 解决方法

### A. 我们方限制
- **方案 1**: 升级用户分组（VIP 限速更宽松，详见 [/pricing]）
- **方案 2**: 创建多个 Token 分摊调用（不同业务用不同 Token）
- **方案 3**: 客户端做指数退避：`429 → wait 1s → wait 2s → wait 4s ...`
- **方案 4**: 降级到更便宜的模型（gpt-4o → gpt-4o-mini，更高 TPM）

### B. 上游限制
如果是**上游 429**（`X-RateLimit-Type: upstream`），表示 OpenAI/Anthropic 自己拒绝了我们：
- 通常是上游账号暂时被 burst protect → 系统会自动切换到其它通道，不需您处理
- 极少数情况整个分组被限：调用会改路由到下一个分组
- 如持续 429 超过 5 分钟，**请回复并附 request_id**，我们排查渠道健康

## 客户端正确处理 429

```python
import time
from openai import OpenAI, RateLimitError

client = OpenAI(api_key="sk-...", base_url="https://api.example.com/v1")

for attempt in range(5):
    try:
        resp = client.chat.completions.create(
            model="gpt-4o",
            messages=[{"role": "user", "content": "hi"}],
        )
        break
    except RateLimitError as e:
        wait = 2 ** attempt
        print(f"429, wait {wait}s")
        time.sleep(wait)
```

## 主动监控你的用量

「账户中心 → 用量记录」可以看到：
- 每分钟调用次数 / token 数
- 异常突增（可能是代码 bug）
- Top 5 消费时段

如果看到非预期的高用量，立即检查您的代码（重试循环、并发数过高等）。

---

如还需协助请直接回复，附上 request_id。

祝好。
