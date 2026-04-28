# BIN 测试 SOP

> 在批量采购虚拟卡前，**强制**做 BIN 测试。一张试卡的成本远低于 50 张废卡。

## 测试流程

### 1. 单卡试绑（24h 观察期）

| 步骤 | 操作 | 通过条件 |
|---|---|---|
| 1 | 准备样卡 1 张，入金 $20 | 余额可见 |
| 2 | 注册全新邮箱（catch-all） | 注册成功 |
| 3 | 注册全新 Anthropic/OpenAI 账号 | 邮箱验证通过 |
| 4 | 上传卡到 Billing → 加 $5 信用 | 扣款成功 |
| 5 | 调 1 次 `/v1/chat/completions` | 200 响应 + 计费 |
| 6 | 等 24 小时不操作 | 账号未被锁、卡未拒付 |
| 7 | 第 25 小时再调 1 次 API | 仍 200 |

**全部通过** → 该 BIN 通过测试，登记到 [vendor-list.md](./vendor-list.md)
**任一失败** → 该 BIN 标记为 **黑名单**，不批量买

### 2. 黑名单 BIN 累积

每个失败 BIN 记录：
- BIN（前 6 位）
- 失败步骤
- 失败时间
- 是否其它平台也封

> 经验：被 OpenAI 封的 BIN，3 周内通常 Claude 也会跟进封。

### 3. 通过期限

每张卡的"通过 BIN"也不是永久有效。**每周用一张新卡复测**，发现拒付率上升 → BIN 黑名单。

## 自动化测试脚本

可以用 Python 脚本调 OpenAI/Claude billing API 做扣费试探（**仅限自有账号**）：

```python
# tools/bin_smoke.py（请勿对未授权账号执行）
import httpx, sys

def test_charge(api_key, amount=0.5):
    """对自有账号触发一次最小金额扣费。失败抛异常。"""
    r = httpx.post(
        "https://api.openai.com/v1/dashboard/billing/credit_grants",
        headers={"Authorization": f"Bearer {api_key}"},
    )
    # ... 平台 API 不同，详见各厂家文档
```

## 重要提醒

- **自动化批量绑卡** 90% 概率触发反欺诈 → 风控复审 → 卡冻结
- **绑卡环节务必人工**，仅 BIN 测试自动化即可
- **同一 IP 绑多张卡** 也是高危信号 → 每号一 IP（住宅）+ 每卡一手机
