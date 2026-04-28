# Captcha Adapter

抽象接口 [`base.py::CaptchaSolver`](./base.py)，三个实现：

| 实现 | 覆盖 | 价格（每千次）|
|---|---|---|
| `capsolver.py` | reCAPTCHA v2/v3, hCaptcha, Cloudflare Turnstile, AWS WAF | $0.50-2 |
| `twocaptcha.py` | 同上 | $1-3 |
| `nopecha.py` | 同上 + LLM 用 prompt | 价格活动 |

**主用 CapSolver**，备用 2Captcha（API 几乎相同）。

## 类型

| 平台 | 类型 | 我们用的 task type |
|---|---|---|
| Google | reCAPTCHA v2 | `ReCaptchaV2TaskProxyLess` |
| Google | reCAPTCHA v3 | `ReCaptchaV3TaskProxyLess` (注意：很多场景需要 enterprise) |
| Cloudflare | Turnstile | `AntiTurnstileTaskProxyLess` |
| 通用 | hCaptcha | `HCaptchaTaskProxyLess` |

## 使用

```python
from adapters.captcha import get_provider

solver = get_provider()
token = await solver.solve_recaptcha_v2(
    site_url="https://accounts.google.com/signup",
    site_key="6LdVABcjAAAAAOcq...",
)
# 把 token 填到 g-recaptcha-response 隐藏字段，或用 JS dispatch
```

## 抗风控建议

- **不要每次都用同一 IP 调 captcha 服务**（CapSolver 自己也有风控）
- v3 验证码的 score 关键 → 需要传 `pageAction` 与场景一致
- Cloudflare Turnstile 频繁失败 → 切换到带 proxy 的 task 类型

## 失败统计

- 单次解码失败率 > 30% 切备用平台
- 单平台连续 100 次失败 → 暂停该平台 1 小时
