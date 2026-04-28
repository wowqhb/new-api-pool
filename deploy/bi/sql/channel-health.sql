-- 渠道健康度（默认 24 小时）
-- 找出哑火、高错误率、慢响应渠道

SELECT
    c.id,
    c.name,
    c.type,
    c.group,
    c.status,
    c.priority,
    c.weight,

    -- 调用统计
    COUNT(l.id)                                                    AS calls_24h,
    COUNT(l.id) FILTER (WHERE l.type = 2)                          AS success_24h,
    COUNT(l.id) FILTER (WHERE l.type IN (3, 4))                    AS failures_24h,
    CASE WHEN COUNT(l.id) > 0
         THEN COUNT(l.id) FILTER (WHERE l.type = 2)::float / COUNT(l.id) * 100
         ELSE 0
    END                                                            AS success_rate,

    -- 延迟（new-api 日志里 use_time 是毫秒）
    AVG(l.use_time)                                                AS avg_rt_ms,
    PERCENTILE_CONT(0.5)  WITHIN GROUP (ORDER BY l.use_time)        AS p50_rt_ms,
    PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY l.use_time)        AS p95_rt_ms,
    PERCENTILE_CONT(0.99) WITHIN GROUP (ORDER BY l.use_time)        AS p99_rt_ms,

    -- 财务
    SUM(l.quota) / 500000.0                                         AS revenue_usd,

    -- 健康分（0-100，权重：成功率 50%、延迟 30%、近 1h 活跃 20%）
    LEAST(100,
        (CASE WHEN COUNT(l.id) > 0
              THEN COUNT(l.id) FILTER (WHERE l.type = 2)::float / COUNT(l.id) * 50
              ELSE 0 END) +
        (CASE WHEN AVG(l.use_time) < 2000 THEN 30
              WHEN AVG(l.use_time) < 5000 THEN 20
              WHEN AVG(l.use_time) < 10000 THEN 10
              ELSE 0 END) +
        (CASE WHEN COUNT(l.id) FILTER (WHERE l.created_at >= EXTRACT(EPOCH FROM NOW() - INTERVAL '1 hour')) > 0
              THEN 20 ELSE 0 END)
    )                                                              AS health_score,

    -- 标签
    CASE
        WHEN COUNT(l.id) = 0 THEN '哑火'
        WHEN COUNT(l.id) FILTER (WHERE l.type = 2)::float / NULLIF(COUNT(l.id), 0) < 0.5 THEN '高错误率'
        WHEN AVG(l.use_time) > 10000 THEN '响应过慢'
        WHEN c.status != 1 THEN '已禁用'
        ELSE '正常'
    END                                                            AS health_label

FROM channels c
LEFT JOIN logs l
    ON l.channel_id = c.id
   AND l.created_at >= EXTRACT(EPOCH FROM NOW() - INTERVAL '24 hours')
GROUP BY c.id, c.name, c.type, c.group, c.status, c.priority, c.weight
ORDER BY health_score ASC;  -- 最不健康的排前
