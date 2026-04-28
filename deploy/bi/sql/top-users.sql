-- Top 50 用户消耗（默认 30 天）
-- 帮助识别大客户、异常用户

SELECT
    u.id                                          AS user_id,
    u.username,
    u.email,
    u.user_group_id,
    g.name                                        AS group_name,
    u.created_time                                AS registered_at,
    SUM(l.quota) / 500000.0                       AS spent_usd,
    SUM(l.prompt_tokens + l.completion_tokens)    AS tokens,
    COUNT(*)                                      AS calls,
    COUNT(DISTINCT l.model_name)                  AS models_used,
    MIN(to_timestamp(l.created_at))               AS first_call_at,
    MAX(to_timestamp(l.created_at))               AS last_call_at,
    -- 用户余额（剩余可用）
    u.quota / 500000.0                            AS balance_usd,
    -- 是否高风险（消耗 / 余额比例 > 80%）
    CASE WHEN u.quota > 0
         THEN SUM(l.quota)::float / u.quota * 100
         ELSE 0
    END                                            AS spent_to_balance_ratio
FROM logs l
JOIN users u ON u.id = l.user_id
LEFT JOIN user_groups g ON g.id = u.user_group_id
WHERE l.created_at >= EXTRACT(EPOCH FROM NOW() - INTERVAL '30 days')
  AND l.type = 2
GROUP BY u.id, u.username, u.email, u.user_group_id, g.name, u.created_time, u.quota
ORDER BY spent_usd DESC
LIMIT 50;
