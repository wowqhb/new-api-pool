-- 首次启动时自动执行（仅在数据卷为空时生效）
-- 创建主库和日志库（new-api 支持把日志写到独立库，防主库膨胀）

SELECT 'CREATE DATABASE newapi_logs'
WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'newapi_logs')\gexec

-- 性能调优常见扩展（按需）
\c newapi
CREATE EXTENSION IF NOT EXISTS pg_stat_statements;

\c newapi_logs
CREATE EXTENSION IF NOT EXISTS pg_stat_statements;
