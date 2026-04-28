-- 用户留存（cohort 分析）
-- 计算每周注册的用户在第 1/2/4/8/12 周还活跃的比例

WITH user_cohorts AS (
    SELECT
        u.id                                                AS user_id,
        date_trunc('week', to_timestamp(u.created_time))    AS cohort_week
    FROM users u
    WHERE u.created_time >= EXTRACT(EPOCH FROM NOW() - INTERVAL '12 weeks')
),
user_activity AS (
    SELECT DISTINCT
        user_id,
        date_trunc('week', to_timestamp(created_at))        AS active_week
    FROM logs
    WHERE created_at >= EXTRACT(EPOCH FROM NOW() - INTERVAL '12 weeks')
      AND type = 2
)
SELECT
    c.cohort_week,
    COUNT(DISTINCT c.user_id) AS cohort_size,

    COUNT(DISTINCT a1.user_id) FILTER (
        WHERE a1.active_week = c.cohort_week + INTERVAL '1 week'
    ) AS week_1,
    COUNT(DISTINCT a2.user_id) FILTER (
        WHERE a2.active_week = c.cohort_week + INTERVAL '2 weeks'
    ) AS week_2,
    COUNT(DISTINCT a4.user_id) FILTER (
        WHERE a4.active_week = c.cohort_week + INTERVAL '4 weeks'
    ) AS week_4,
    COUNT(DISTINCT a8.user_id) FILTER (
        WHERE a8.active_week = c.cohort_week + INTERVAL '8 weeks'
    ) AS week_8,
    COUNT(DISTINCT a12.user_id) FILTER (
        WHERE a12.active_week = c.cohort_week + INTERVAL '12 weeks'
    ) AS week_12,

    -- 百分比
    ROUND(COUNT(DISTINCT a1.user_id) FILTER (
        WHERE a1.active_week = c.cohort_week + INTERVAL '1 week'
    )::numeric / NULLIF(COUNT(DISTINCT c.user_id), 0) * 100, 1) AS retention_w1_pct,
    ROUND(COUNT(DISTINCT a4.user_id) FILTER (
        WHERE a4.active_week = c.cohort_week + INTERVAL '4 weeks'
    )::numeric / NULLIF(COUNT(DISTINCT c.user_id), 0) * 100, 1) AS retention_w4_pct
FROM user_cohorts c
LEFT JOIN user_activity a1  ON a1.user_id  = c.user_id
LEFT JOIN user_activity a2  ON a2.user_id  = c.user_id
LEFT JOIN user_activity a4  ON a4.user_id  = c.user_id
LEFT JOIN user_activity a8  ON a8.user_id  = c.user_id
LEFT JOIN user_activity a12 ON a12.user_id = c.user_id
GROUP BY c.cohort_week
ORDER BY c.cohort_week DESC;
