# Metabase 看板导入指南

## 部署 Metabase

```yaml
# docker-compose.bi.yml
services:
  metabase:
    image: metabase/metabase:latest
    container_name: metabase
    restart: unless-stopped
    ports:
      - "127.0.0.1:3033:3000"
    volumes:
      - ./metabase-data:/metabase-data
    environment:
      - MB_DB_FILE=/metabase-data/metabase.db
      - JAVA_TIMEZONE=Asia/Shanghai
```

```bash
docker compose -f docker-compose.bi.yml up -d
# 访问 http://your-server:3033 完成初始化
# 反代加 SSO（Cloudflare Access）
```

## 数据源配置

**重要**：连只读副本，绝不连主库！

```
Display name:     production-readonly
Type:             PostgreSQL
Host:             pg-readonly.internal
Port:             5432
Database name:    new_api
Username:         bi_readonly
Password:         <vault://bi_readonly_password>
SSL:              require
Schedules:        ☑ 每小时刷新元数据
```

创建 `bi_readonly` 角色：

```sql
-- 在主库跑
CREATE ROLE bi_readonly WITH LOGIN PASSWORD 'xxx';
GRANT CONNECT ON DATABASE new_api TO bi_readonly;
GRANT USAGE  ON SCHEMA public TO bi_readonly;
GRANT SELECT ON ALL TABLES IN SCHEMA public TO bi_readonly;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT ON TABLES TO bi_readonly;
```

## 推荐看板（5 个）

### Dashboard 1: 经营总览
- Card 1: GMV 趋势（30 天折线，from `gmv-trend.sql`）
- Card 2: 毛利率（30 天）
- Card 3: DAU 趋势
- Card 4: Top 10 用户当月消耗（柱图）
- Card 5: 模型营收占比（饼图）

### Dashboard 2: 号池健康
- Card 1: 各分组活跃 / 总数（柱图）
- Card 2: 不健康渠道列表（表格，from `channel-health.sql`）
- Card 3: 7 天注册成功率（折线）
- Card 4: 单号成本 vs 收益散点
- Card 5: 平均生命周期分布（直方）

### Dashboard 3: 财务
- Card 1: 收入 / 成本 / 毛利（30 天柱叠加）
- Card 2: 按模型毛利（from `profit-by-model.sql`）
- Card 3: 上游成本占比（饼图）
- Card 4: 退款金额 + 比例
- Card 5: 收款 vs 充值漏斗

### Dashboard 4: 用户分析
- Card 1: 留存 cohort 矩阵（from `cohort-retention.sql`）
- Card 2: LTV 分布（直方）
- Card 3: 充值漏斗（from `funnel-payment.sql`）
- Card 4: 异常用户（实时表）
- Card 5: 流失预测（活跃 → 不活跃）

### Dashboard 5: 性能与缓存
- Card 1: API p50/p95/p99 趋势
- Card 2: 错误率分类
- Card 3: 缓存命中率（from `cache-savings.sql`）
- Card 4: 缓存节省金额（柱图）
- Card 5: 上游延迟对比

## 自动推送

Metabase 支持 Email Subscriptions：

```
Dashboard → ⋯ → Subscriptions
  → Email
  → To: ceo@example.com, ops@example.com
  → Schedule: 每天 9:00
  → Format: PDF + CSV 附件
```

## 备份 Metabase

```bash
# 每周备份 metabase.db
docker exec metabase tar czf /tmp/mb-backup.tar.gz /metabase-data
docker cp metabase:/tmp/mb-backup.tar.gz ./backups/metabase-$(date +%Y%m%d).tar.gz
```

## 性能优化

如果数据量大（> 100M 行 logs）：

1. 在 PG 上建物化视图：
   ```sql
   CREATE MATERIALIZED VIEW mv_daily_summary AS
   SELECT date_trunc('day', to_timestamp(created_at)) AS day, ...
   FROM logs
   GROUP BY day;

   -- 每小时刷新
   CREATE EXTENSION pg_cron;
   SELECT cron.schedule('refresh-mv', '0 * * * *',
       'REFRESH MATERIALIZED VIEW CONCURRENTLY mv_daily_summary');
   ```

2. 让 Metabase 查 mv_* 而不是原表
