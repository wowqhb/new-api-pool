-- 缓存节省统计（默认 7 天）

WITH cache_stats AS (
    SELECT
        date_trunc('day', to_timestamp(created_at))      AS day,
        COUNT(*)                                          AS total_calls,
        COUNT(*) FILTER (WHERE cache_hit = 'L0')          AS l0_hits,
        COUNT(*) FILTER (WHERE cache_hit = 'L1')          AS l1_hits,
        COUNT(*) FILTER (WHERE cache_hit IS NULL OR cache_hit = '') AS misses,
        SUM(quota) FILTER (WHERE cache_hit = 'L0') / 500000.0 AS l0_billed_usd,
        SUM(quota) FILTER (WHERE cache_hit IS NULL OR cache_hit = '') / 500000.0 AS miss_billed_usd
    FROM logs
    WHERE created_at >= EXTRACT(EPOCH FROM NOW() - INTERVAL '7 days')
      AND type = 2
    GROUP BY day
)
SELECT
    day,
    total_calls,
    l0_hits,
    l1_hits,
    misses,
    -- 命中率
    ROUND((l0_hits + l1_hits)::numeric / NULLIF(total_calls, 0) * 100, 1) AS hit_rate_pct,
    -- 实际计费（命中按打折计费）
    l0_billed_usd,
    miss_billed_usd,
    -- 节省金额估算（命中本应按 miss 价计费）
    -- 估算：用 miss 的平均 quota / 调用 × 命中次数
    ROUND(
        ((miss_billed_usd / NULLIF(misses, 0)) * (l0_hits + l1_hits)
         - l0_billed_usd)::numeric, 2
    ) AS estimated_saved_usd
FROM cache_stats
ORDER BY day;
