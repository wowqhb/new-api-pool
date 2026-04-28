# SOP：月度对账

每月 1 号跑，3 号前完成，4 号经营会议汇报。

## 输入

- 各上游账单：OpenAI / Anthropic / Google / 第三方供应商
- new-api 内部数据：用户消耗 / 充值流水 / 兑换码使用
- 财务流水：收款主体银行/Stripe/支付宝对账

## 自动跑的部分

```bash
cd deploy/

# 月度毛利
bash billing/scripts/monthly-pnl.sh 2026-04

# 渠道对账
bash billing/scripts/channel-pnl.sh 30

# 充值对账
bash billing/scripts/topup-report.sh 2026-04

# 完整财务包（加密 ZIP）
bash billing/scripts/export-finance.sh 2026-04
```

## 人工部分

### 1. 上游账单核对

每个上游分别对：

| 上游 | 数据来源 | 核对点 |
|---|---|---|
| OpenAI | platform.openai.com/usage | 我们 logs 里 official 分组 OpenAI 渠道总 token |
| Anthropic | console.anthropic.com/settings/usage | 我们 logs 里 official 分组 Anthropic 渠道总 token |
| Google AI | aistudio.google.com → API | 各 Gemini Free Key 真实用量 |
| 第三方 | 供应商后台 | 第三方分组消耗 |

**容许偏差 ≤ 2%**（计费时点差异），超出找根因。

### 2. 收入侧核对

| 来源 | 数据 | 核对点 |
|---|---|---|
| 兑换码 | `redemptions` 表 status=2 | 收款方水流 |
| epay 充值 | `topups` 表 method=epay | epay 后台流水 |
| Stripe | `topups` 表 method=stripe | Stripe Dashboard |

**充值成功 != 真实到账**，要看银行实收。退款/拒付要扣回。

### 3. 毛利率

```
毛利 = 用户消耗 quota × $0.000002 - 上游真实成本 - 基础设施成本（服务器/CDN/工具）

毛利率 = 毛利 / 用户消耗
```

健康线：

- 毛利率 < 20%：警报（号池效率低或定价低）
- 毛利率 20-50%：正常
- 毛利率 > 50%：可能定价过高，留意流失

### 4. 渠道亏本榜

`billing/scripts/channel-pnl.sh` 输出对比上游账单，标红亏损渠道：

- 亏 < 30 天：观察
- 亏 30-90 天：调整 weight
- 亏 > 90 天：直接下架

### 5. 用户侧异常

- Top 3 消耗用户：是否合理（VIP 客户 vs 异常）
- 投诉 / 退款金额：占总收入百分比（健康 < 2%）
- 流失：30 天未活跃用户数

## 输出

- 月度经营报告（Notion / Confluence）
- 数据保留：[`billing/reports/finance-YYYY-MM.tar.gz.enc`](../billing/reports/) 永久存
- 上传到对象存储 + 异地备份（合规要求 5-7 年）

## 异常 → 立刻动作

- 毛利率突降 → 查倍率配置 / 第三方涨价 / 渠道亏损
- 上游账单 vs 内部偏差 > 5% → 暂停该分组 + 排查计费
- 退款率突升 → 客服复盘 + 风控调整
