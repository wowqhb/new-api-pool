# 卡源对比清单

> ⚠️ 价格、可用性、BIN 通过率每月波动大，本表仅 2026-Q2 参考。**必须自行 BIN 测试**。

## 顶级推荐（通过率 + 价格平衡）

### OneKey Card

- 官网：https://card.onekey.so
- KYC：钱包签名（无人工 KYC）
- BIN：多个 Mastercard BIN
- 价格：$0.99 单卡费 + $1 起充
- 充值：USDT (TRC20/ERC20) → 卡余额
- 通过率：
  - OpenAI: ★★★★
  - Anthropic: ★★★★
  - Google Cloud: ★★★
  - DigitalOcean/AWS: ★★

#### 特点
- 单账户最多 5 张卡（避免风控信号）
- 余额 $5 起步，单笔最低 $0.5
- **BIN 多变是优势**也是劣势：每 1-2 月会换 BIN，新 BIN 通过率重新洗牌
- API 接口完整（可写自动化补卡脚本）

### Bybit Card

- 官网：https://www.bybit.com/en/products/card
- KYC：交易所 KYC（中级 KYC 即可）
- BIN：固定（部分上游已加白名单）
- 价格：免年费、免开卡费
- 充值：从 Bybit 现货账户划转
- 通过率：
  - OpenAI: ★★★（部分 BIN 已封）
  - Anthropic: ★★★★
  - Stripe 商户: ★★★★
- 适合：中国用户已有 Bybit 账号

## 备选

### Wildcard

- 官网：https://wildcard.so
- KYC：美国地址 + SSN
- 通过率最高（号称等同实卡）
- 单卡 $4.99/月
- 适合：少量高价值号（VIP 池）

### Capital One Visa Gift Card

- 通过率高（实体礼品卡 BIN）
- 不能续费、不能调整余额
- 适合：测试 / 一次性充值
- 国内难买

### dCard

- 有跳过 KYC 选项
- 单卡 $5+
- 部分 BIN 已封
- 备用

## 黑名单（不要买）

- ❌ 国内招商/工行虚拟卡（拒付率 99%）
- ❌ Revolut（KYC 后但 BIN 已封 OpenAI/Claude）
- ❌ 任何"代充"二次倒卖卡（来源不明，跑路风险）
- ❌ 群里的"包过 BIN" 卖卡群（90% 是钓鱼）

## 采购建议

| 月需求 | 建议组合 |
|---|---|
| < 10 张 | OneKey 单源 |
| 10-50 张 | OneKey 8 + Bybit 2 |
| 50-200 张 | OneKey 6 + Bybit 2 + Wildcard 2 |
| 200+ 张 | 必须找专业代理（不在本文件讨论范围）|

> 💡 永远保持**至少 2 个不同发卡方**，单源被封时仍有备份。

## 余额监控

参考 [balance-tracker.sh](./balance-tracker.sh)，每周二跑一次：
- 列出余额 < $5 的卡 → 补金告警
- 列出连续 3 个月零扣费的卡 → 闲置告警（可释放）
- 列出连续 2 次拒付的卡 → 进黑名单

## 退役流程

卡余额低于 $1 或拒付 2 次：
1. 解绑所有上游账号（避免续费失败）
2. 提取剩余余额（OneKey/Bybit 都支持）
3. 在 Vault 里把 `card/<id>` 标记为 `retired`
4. 30 天后从 Vault 删除（KYC 数据合规）
