-- 每日早报 SQL（PG）
-- 输出今日（昨天）核心指标，配合 daily-report.sh 用

WITH params AS (
    SELECT
        date_trunc('day', NOW() - INTERVAL '1 day') AS day_start,
        date_trunc('day', NOW())                    AS day_end,
        date_trunc('day', NOW() - INTERVAL '2 days') AS prev_start,
        date_trunc('day', NOW() - INTERVAL '1 day')  AS prev_end
),
yesterday AS (
    SELECT
        COUNT(*)                            AS req_count,
        SUM(prompt_tokens)                  AS prompt_tokens,
        SUM(completion_tokens)              AS completion_tokens,
        SUM(quota) / 500000.0               AS gmv_usd,  -- quota 单位 1/500000 USD
        COUNT(DISTINCT user_id)             AS dau,
        COUNT(*) FILTER (WHERE type = 2)    AS success_count
    FROM logs, params
    WHERE created_at >= EXTRACT(EPOCH FROM day_start)
      AND created_at <  EXTRACT(EPOCH FROM day_end)
),
prev_day AS (
    SELECT
        COUNT(*)                AS req_count,
        SUM(quota) / 500000.0   AS gmv_usd,
        COUNT(DISTINCT user_id) AS dau
    FROM logs, params
    WHERE created_at >= EXTRACT(EPOCH FROM prev_start)
      AND created_at <  EXTRACT(EPOCH FROM prev_end)
),
upstream_cost AS (
    SELECT SUM(cost_usd) AS cost
    FROM upstream_billing, params
    WHERE recorded_at >= day_start
      AND recorded_at <  day_end
),
new_users AS (
    SELECT COUNT(*) AS n
    FROM users, params
    WHERE created_time >= EXTRACT(EPOCH FROM day_start)
      AND created_time <  EXTRACT(EPOCH FROM day_end)
),
paying AS (
    SELECT COUNT(DISTINCT user_id) AS n
    FROM logs, params
    WHERE created_at >= EXTRACT(EPOCH FROM day_start)
      AND created_at <  EXTRACT(EPOCH FROM day_end)
      AND quota > 0
),
channels AS (
    SELECT
        COUNT(*) FILTER (WHERE status = 1)             AS active,
        COUNT(*)                                       AS total,
        COUNT(*) FILTER (WHERE created_time >= EXTRACT(EPOCH FROM (SELECT day_start FROM params))) AS new_today,
        COUNT(*) FILTER (WHERE status = 2 AND updated_time >= EXTRACT(EPOCH FROM (SELECT day_start FROM params))) AS disabled_today
    FROM channels
),
refunds AS (
    SELECT COALESCE(SUM(amount), 0) / 500000.0 AS refund_usd
    FROM topups, params
    WHERE status = 'refunded'
      AND updated_at >= day_start
      AND updated_at <  day_end
)
SELECT
    -- 财务
    yesterday.gmv_usd                                                            AS gmv,
    upstream_cost.cost                                                           AS upstream_cost,
    yesterday.gmv_usd - COALESCE(upstream_cost.cost, 0)                          AS gross_profit,
    CASE WHEN yesterday.gmv_usd > 0
         THEN (yesterday.gmv_usd - COALESCE(upstream_cost.cost, 0)) / yesterday.gmv_usd * 100
         ELSE 0
    END                                                                          AS gross_margin_pct,
    refunds.refund_usd                                                           AS refunds,

    -- 增长
    yesterday.dau                                                                AS dau,
    new_users.n                                                                  AS new_users,
    paying.n                                                                     AS paying_users,
    CASE WHEN prev_day.dau > 0
         THEN (yesterday.dau - prev_day.dau)::float / prev_day.dau * 100
         ELSE 0
    END                                                                          AS dau_growth_pct,

    -- API
    yesterday.req_count                                                          AS api_requests,
    CASE WHEN yesterday.req_count > 0
         THEN yesterday.success_count::float / yesterday.req_count * 100
         ELSE 100
    END                                                                          AS success_rate,

    -- 号池
    channels.active                                                              AS active_channels,
    channels.total                                                               AS total_channels,
    channels.new_today                                                           AS new_channels,
    channels.disabled_today                                                      AS disabled_channels,

    -- 环比
    CASE WHEN prev_day.gmv_usd > 0
         THEN (yesterday.gmv_usd - prev_day.gmv_usd) / prev_day.gmv_usd * 100
         ELSE 0
    END                                                                          AS gmv_growth_pct
FROM yesterday, prev_day, upstream_cost, new_users, paying, channels, refunds;
