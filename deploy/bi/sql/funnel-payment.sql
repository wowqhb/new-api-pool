-- 支付漏斗（默认 30 天）
-- 注册 → 验证邮箱 → 创建 token → 首次调用 → 充值

WITH funnel AS (
    SELECT
        u.id,
        u.created_time,
        EXISTS(SELECT 1 FROM users WHERE id = u.id AND email_verified = true) AS verified,
        EXISTS(SELECT 1 FROM tokens WHERE user_id = u.id) AS has_token,
        EXISTS(SELECT 1 FROM logs WHERE user_id = u.id AND type = 2) AS made_call,
        EXISTS(SELECT 1 FROM topups WHERE user_id = u.id AND status = 'paid') AS paid
    FROM users u
    WHERE u.created_time >= EXTRACT(EPOCH FROM NOW() - INTERVAL '30 days')
)
SELECT
    'registered'    AS step, COUNT(*)                        AS users, 100.0 AS pct
FROM funnel
UNION ALL
SELECT
    'verified',     COUNT(*) FILTER (WHERE verified),
    COUNT(*) FILTER (WHERE verified)::float / NULLIF(COUNT(*), 0) * 100
FROM funnel
UNION ALL
SELECT
    'created_token', COUNT(*) FILTER (WHERE has_token),
    COUNT(*) FILTER (WHERE has_token)::float / NULLIF(COUNT(*), 0) * 100
FROM funnel
UNION ALL
SELECT
    'first_call',    COUNT(*) FILTER (WHERE made_call),
    COUNT(*) FILTER (WHERE made_call)::float / NULLIF(COUNT(*), 0) * 100
FROM funnel
UNION ALL
SELECT
    'paid',          COUNT(*) FILTER (WHERE paid),
    COUNT(*) FILTER (WHERE paid)::float / NULLIF(COUNT(*), 0) * 100
FROM funnel;
