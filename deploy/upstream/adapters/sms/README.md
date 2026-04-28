# SMS Adapter

抽象接口 [`base.py::SMSProvider`](./base.py)，两个实现：

| 实现 | 适用 | 备注 |
|---|---|---|
| `sms_activate.py` | sms-activate.io / 5sim 系（API 完全相同）| 主选 |
| `smsman.py` | sms-man.com（备用）| 见 https://sms-man.com/api |

## 国家代码（sms-activate）

| 代码 | 国家 | 用法 |
|---|---|---|
| 0 | 俄罗斯 | 便宜，多平台已封 |
| 6 | 印尼 | 便宜，Google 偶尔可 |
| 22 | 印度 | 便宜，Google 难度大 |
| 89 | 越南 | 偶尔可用 |
| 187 | USA | 贵但稳，Google/Apple 友好 |
| 12 | 美国（实卡）| 最贵但通过率最高 |

参考：https://sms-activate.io/api2

## 服务代码

- `go` Google
- `tg` Telegram
- `wa` WhatsApp
- `ot` 任意（用于不在列表的平台）

## 使用流程

```python
from adapters.sms import get_provider

sms = get_provider()
order = await sms.request_phone(service="go", country="183")  # Russia for Google
print(order.phone)  # +7xxxxxxx
code = await sms.wait_for(order.id, timeout=300)
await sms.release(order.id)  # 用完归还（避免重复扣费）
```

## 抗风控建议

- **国家选择**：风控严的目标（如 Google）→ 用印度尼西亚 / 越南
- **不要重复使用**：同一手机号一年内多次注册 = 黑名单
- **接码失败立即释放**：sms-activate 提供 `setStatus action=8` 退款
- **预算硬上限**：单号成本超 $0.5 直接放弃

## 价格参考（2026-Q2，sms-activate）

| 国家 | Google | OpenAI | Telegram |
|---|---|---|---|
| Russia | $0.10 | $0.30 | $0.05 |
| India | $0.20 | $0.50 | $0.08 |
| USA | $1.00 | $1.50 | $0.30 |
| Indonesia | $0.18 | 缺货 | $0.10 |

价格波动大，每周 review。
