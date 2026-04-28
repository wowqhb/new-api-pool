# BI 与运营分析

> 没有数据驱动的运营 = 拍脑袋。这一章给你完整的报表 SQL + 看板模板。

## 工具栈

- **数据源**：PG 只读副本（绝对不连主库做 BI 查询）
- **BI 工具**：[Metabase](https://www.metabase.com/) 自建（推荐）或 [Superset](https://superset.apache.org/)
- **看板自动推送**：每日早 9 点 Telegram + 邮件
- **数据延迟**：T-1（昨天的 0 点到 24 点）

## 核心看板

### 1. 经营总览（CEO 早报）

每天 9 点推送：

```
📊 AITransfer 早报 - 2026-04-27
━━━━━━━━━━━━━━━━━━━━━━

💰 今日 / 昨日
   GMV         $1,250 ↑ 8%
   毛利        $580 ↑ 10%
   毛利率      46.4%
   退款        $12

👥 用户
   DAU         1,240 ↑ 5%
   新增        45
   付费用户    320
   流失        8

🔌 API
   请求量      2.4M (-3%)
   成功率      99.2% (-0.3%)
   p95         1.8s (+200ms)

🏊 号池
   活跃渠道    156 / 200
   今日新增    12
   今日离池    3

⚠️ 关注
   • 异常用户：user_xxx 1h 消耗 $35
   • 渠道劣化：channel_yyy 成功率掉到 75%
   • Gemini Free 池容量低于预警线 (80%)
```

### 2. 业务大盘（Grafana 接 PG）

- 实时 RPS / RT / 错误率
- 7 天趋势
- 按模型 / 用户分组 / 渠道分组拆分

### 3. 财务报表（Metabase）

- GMV 日 / 周 / 月
- 毛利 / 毛利率（按模型）
- Top 10 用户消耗
- LTV（用户生命周期价值）
- 充值漏斗
- 退款 / 争议金额

### 4. 号池健康（Metabase）

- 各分组活跃 / 总数
- 平均生命周期（注册 → 失效）
- 单号产出（KWh）
- 注册成功率
- 单号成本 vs 收益

## SQL 文件

- [`sql/daily-report.sql`](./sql/daily-report.sql) 每日早报
- [`sql/gmv-trend.sql`](./sql/gmv-trend.sql) GMV 趋势
- [`sql/profit-by-model.sql`](./sql/profit-by-model.sql) 模型毛利
- [`sql/top-users.sql`](./sql/top-users.sql) Top 用户
- [`sql/anomaly-users.sql`](./sql/anomaly-users.sql) 异常用户
- [`sql/channel-health.sql`](./sql/channel-health.sql) 渠道健康
- [`sql/upstream-cost.sql`](./sql/upstream-cost.sql) 上游成本
- [`sql/cohort-retention.sql`](./sql/cohort-retention.sql) 用户留存
- [`sql/cache-savings.sql`](./sql/cache-savings.sql) 缓存节省
- [`sql/funnel-payment.sql`](./sql/funnel-payment.sql) 支付漏斗

## 自动推送脚本

- [`scripts/daily-report.sh`](./scripts/daily-report.sh) 早报推送（Telegram + 邮件）
- [`scripts/weekly-summary.sh`](./scripts/weekly-summary.sh) 周报
- [`scripts/anomaly-alert.sh`](./scripts/anomaly-alert.sh) 异常实时告警

cron：

```cron
0 9 * * *   /opt/bi/scripts/daily-report.sh        # 每日 9 点
0 10 * * 1  /opt/bi/scripts/weekly-summary.sh      # 每周一 10 点
*/15 * * * * /opt/bi/scripts/anomaly-alert.sh      # 每 15 分钟扫异常
```
