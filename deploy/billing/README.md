# 计费 / 充值 / 对账

## 三层倍率

new-api 计算用户实际扣费 = `model_ratio × completion_ratio × group_ratio × tokens`

| 层级 | 控制对象 | 配置位置 | 默认 |
|---|---|---|---|
| `model_ratio` | 模型本身的输入价（相对参考价） | 系统设置 → 倍率设置 → 模型倍率 | 跟官方价对齐 |
| `completion_ratio` | output token 相对 input 的倍率 | 同上 → 补全倍率 | OpenAI 官方比例 |
| `group_ratio` | 用户分组的整体加价系数 | 同上 → 分组倍率 | 已在 `init-groups.sh` 设 |
| `channel_ratio` | 单渠道单独打折（可选） | 渠道编辑 → 倍率 | 1.0 |

**关键原则**：永远保留 30% 利润缓冲，绝不"按理论毛利招用户"。

## 推荐倍率（2026 行情）

参考 [`pricing.json`](./pricing.json)，按月 review 一次。

## 充值通道

`new-api` 内置三种：

1. **兑换码（Redemption Code）**：批量生成卖在万能宝/淘宝/TG 群
   - 管理后台 → 兑换码 → 批量生成
   - 参考 [`scripts/gen-redemption.sh`](./scripts/gen-redemption.sh)

2. **易支付 (epay)**：国内 USDT/支付宝/微信通道
   - 系统设置 → 支付设置 → 启用 epay
   - **跑路风险**：不要押大额，每天提

3. **Stripe / PayPal**：海外卡用户
   - 系统设置 → 支付设置 → 启用 Stripe
   - 主体合规：要有海外公司注册

强烈建议**至少配 2 个通道**（runbook 06 已说明）。

## 对账脚本

```bash
# 月度毛利报表
bash scripts/monthly-pnl.sh 2026-04

# 渠道亏本榜（成本估算 vs 用户消耗）
bash scripts/channel-pnl.sh

# 充值流水
bash scripts/topup-report.sh 2026-04

# 数据导出（财务/审计用）
bash scripts/export-finance.sh 2026-04
```

输出 CSV 到 `billing/reports/`，**不要把这些进 Git**（`.gitignore` 已加）。
