-- 按模型的毛利分析（默认 7 天）
-- 找出哪些模型在亏本，哪些在赚钱

WITH model_revenue AS (
    SELECT
        l.model_name,
        SUM(l.quota) / 500000.0    AS revenue_usd,
        COUNT(*)                    AS calls,
        SUM(l.prompt_tokens)        AS prompt_tokens,
        SUM(l.completion_tokens)    AS completion_tokens
    FROM logs l
    WHERE l.created_at >= EXTRACT(EPOCH FROM NOW() - INTERVAL '7 days')
      AND l.type = 2
    GROUP BY l.model_name
),
model_cost AS (
    SELECT
        model_name,
        SUM(cost_usd) AS cost_usd
    FROM upstream_billing
    WHERE recorded_at >= NOW() - INTERVAL '7 days'
    GROUP BY model_name
)
SELECT
    r.model_name,
    r.calls,
    r.prompt_tokens,
    r.completion_tokens,
    r.revenue_usd,
    COALESCE(c.cost_usd, 0)                                      AS cost_usd,
    r.revenue_usd - COALESCE(c.cost_usd, 0)                      AS profit_usd,
    CASE WHEN r.revenue_usd > 0
         THEN (r.revenue_usd - COALESCE(c.cost_usd, 0)) / r.revenue_usd * 100
         ELSE 0
    END                                                           AS margin_pct,
    -- 单次调用的平均
    CASE WHEN r.calls > 0
         THEN r.revenue_usd / r.calls
         ELSE 0
    END                                                           AS avg_revenue_per_call,
    CASE WHEN r.calls > 0
         THEN COALESCE(c.cost_usd, 0) / r.calls
         ELSE 0
    END                                                           AS avg_cost_per_call
FROM model_revenue r
LEFT JOIN model_cost c USING (model_name)
ORDER BY profit_usd DESC;
