# SOP：号池容量预警

## 三个核心指标

每周一手动跑（或 cron 自动）：

```bash
bash sop/scripts/capacity-check.sh
```

输出：

| 指标 | 健康 | 警告 | 危险 |
|---|---|---|---|
| **可用容量比** = 当前可用 / 上周高峰 | ≥ 2.0× | 1.5-2.0× | < 1.5× |
| **本周到期号数** | 0 | < 10 | ≥ 10 |
| **失败率（按分组）** | < 5% | 5-15% | > 15% |
| **应急号池储备** | ≥ 30% 总容量 | 10-30% | < 10% |

## 容量计算

```sql
-- 各分组当前可用渠道数 vs 总配额
SELECT
  "group" AS channel_group,
  COUNT(*) FILTER (WHERE status = 1) AS active,
  COUNT(*) FILTER (WHERE status = 2) AS auto_disabled,
  COUNT(*) FILTER (WHERE status = 3) AS manual_disabled,
  COUNT(*) AS total
FROM channels
WHERE "group" IS NOT NULL
GROUP BY "group"
ORDER BY "group";

-- 上周高峰 QPS（找出"我们到底能撑多大"）
SELECT
  date_trunc('hour', created_at) AS hour,
  COUNT(*) AS reqs
FROM logs
WHERE created_at > NOW() - INTERVAL '7 days' AND type = 2
GROUP BY 1
ORDER BY reqs DESC
LIMIT 10;
```

## 补号策略

按"号的半衰期"反推每周补号量：

| 来源 | 半衰期 | 月损耗率 | 月补号需求（每 100 号当前在用）|
|---|---|---|---|
| Gemini Free | 1-3 周 | 60% | ≥ 60 个 |
| Claude OAuth | 1-3 月 | 25% | ≥ 25 个 |
| Official Key | 6-12 月 | 5% | ≥ 5 个 |
| Third-party | 1-2 月 | 40% | ≥ 40 个 |

**补号上线时间 ≥ 损耗 + 1 周 buffer**，否则永远赶不上消耗。

## 应急号池

平时不放出来，权重设 0，专门留给：
- 主号池大批失效
- 突发流量（流量峰值 > 容量 80%）
- 灰度发布的备份

应急启动条件：

- `RecentFailureRate > 30%` 持续 30 分钟
- 主分组可用渠道 < 一半
- 任何 P1 上游故障

启动操作：

```bash
# 把应急分组的 weight 从 0 改回 50
UPDATE channels SET weight = 50 WHERE "group" = 'gemini-free-emergency';
```
