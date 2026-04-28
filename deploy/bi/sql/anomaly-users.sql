-- 异常用户检测：突发高消耗、可疑模式
-- 每 15 分钟跑一次，触发告警

WITH last_hour AS (
    SELECT
        user_id,
        SUM(quota) / 500000.0          AS spent_1h,
        COUNT(*)                       AS calls_1h,
        COUNT(DISTINCT model_name)     AS models_1h
    FROM logs
    WHERE created_at >= EXTRACT(EPOCH FROM NOW() - INTERVAL '1 hour')
      AND type = 2
    GROUP BY user_id
),
last_24h AS (
    SELECT
        user_id,
        SUM(quota) / 500000.0  AS spent_24h
    FROM logs
    WHERE created_at >= EXTRACT(EPOCH FROM NOW() - INTERVAL '24 hours')
      AND type = 2
    GROUP BY user_id
),
hist_avg AS (
    -- 30 天平均小时消耗
    SELECT
        user_id,
        SUM(quota) / 500000.0 / (30 * 24) AS avg_hourly_spent
    FROM logs
    WHERE created_at >= EXTRACT(EPOCH FROM NOW() - INTERVAL '30 days')
      AND created_at <  EXTRACT(EPOCH FROM NOW() - INTERVAL '1 hour')
      AND type = 2
    GROUP BY user_id
)
SELECT
    u.id,
    u.username,
    u.email,
    h.spent_1h,
    h.calls_1h,
    h.models_1h,
    d.spent_24h,
    a.avg_hourly_spent,
    -- 1h 消耗 vs 历史小时均值，超 10 倍触发
    CASE WHEN COALESCE(a.avg_hourly_spent, 0) > 0
         THEN h.spent_1h / a.avg_hourly_spent
         ELSE 999
    END                                        AS spike_ratio,
    -- 触发原因
    ARRAY_REMOVE(ARRAY[
        CASE WHEN h.spent_1h > 50 THEN 'high_spend_1h' END,
        CASE WHEN h.spent_1h > 10 * COALESCE(a.avg_hourly_spent, 0) AND a.avg_hourly_spent > 0
             THEN 'spike_10x' END,
        CASE WHEN h.calls_1h > 1000 THEN 'high_qps' END,
        CASE WHEN d.spent_24h > 200 THEN 'over_daily_cap' END,
        CASE WHEN u.quota < h.spent_1h * 500000 * 2 THEN 'balance_low' END
    ], NULL)                                   AS reasons
FROM last_hour h
JOIN users u ON u.id = h.user_id
LEFT JOIN last_24h d ON d.user_id = h.user_id
LEFT JOIN hist_avg a ON a.user_id = h.user_id
WHERE
    h.spent_1h > 50                                                 -- 1 小时 > $50
    OR h.calls_1h > 1000                                            -- 1 小时 > 1000 次
    OR (h.spent_1h > 10 AND COALESCE(a.avg_hourly_spent, 0) > 0
        AND h.spent_1h > 10 * a.avg_hourly_spent)                   -- 10x 突增
ORDER BY h.spent_1h DESC;
