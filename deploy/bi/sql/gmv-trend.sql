-- GMV 趋势（默认 30 天）
-- 输出每日 GMV、毛利、毛利率，可以接 Metabase 做折线图

SELECT
    date_trunc('day', to_timestamp(l.created_at)) AS day,
    SUM(l.quota) / 500000.0                       AS gmv_usd,
    COALESCE((
        SELECT SUM(cost_usd)
        FROM upstream_billing
        WHERE date_trunc('day', recorded_at) = date_trunc('day', to_timestamp(l.created_at))
    ), 0)                                          AS upstream_cost_usd,
    SUM(l.quota) / 500000.0 - COALESCE((
        SELECT SUM(cost_usd)
        FROM upstream_billing
        WHERE date_trunc('day', recorded_at) = date_trunc('day', to_timestamp(l.created_at))
    ), 0)                                          AS gross_profit_usd,
    COUNT(*)                                       AS api_calls,
    COUNT(DISTINCT l.user_id)                      AS dau,
    SUM(l.prompt_tokens + l.completion_tokens)     AS tokens
FROM logs l
WHERE l.created_at >= EXTRACT(EPOCH FROM NOW() - INTERVAL '30 days')
  AND l.type = 2  -- success only
GROUP BY day
ORDER BY day;
