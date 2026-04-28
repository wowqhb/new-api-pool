-- 上游成本分析（默认 30 天）
-- 计算每个渠道分组、每个上游 API 的实际成本

WITH cost_by_group AS (
    SELECT
        c.group                                                  AS channel_group,
        COUNT(l.id)                                              AS calls,
        SUM(l.prompt_tokens)                                     AS prompt_tokens,
        SUM(l.completion_tokens)                                 AS completion_tokens,
        SUM(l.quota) / 500000.0                                  AS revenue_usd,
        COALESCE(SUM(b.cost_usd), 0)                             AS upstream_cost_usd
    FROM logs l
    JOIN channels c ON c.id = l.channel_id
    LEFT JOIN upstream_billing b ON b.log_id = l.id
    WHERE l.created_at >= EXTRACT(EPOCH FROM NOW() - INTERVAL '30 days')
      AND l.type = 2
    GROUP BY c.group
)
SELECT
    channel_group,
    calls,
    prompt_tokens,
    completion_tokens,
    revenue_usd,
    upstream_cost_usd,
    revenue_usd - upstream_cost_usd                AS gross_profit_usd,
    CASE WHEN revenue_usd > 0
         THEN (revenue_usd - upstream_cost_usd) / revenue_usd * 100
         ELSE 0
    END                                            AS margin_pct,
    -- 单次调用平均
    revenue_usd  / NULLIF(calls, 0)                AS avg_revenue_per_call,
    upstream_cost_usd / NULLIF(calls, 0)           AS avg_cost_per_call,
    -- 1k token 成本
    upstream_cost_usd / NULLIF(prompt_tokens + completion_tokens, 0) * 1000 AS cost_per_1k_tokens
FROM cost_by_group
ORDER BY revenue_usd DESC;
