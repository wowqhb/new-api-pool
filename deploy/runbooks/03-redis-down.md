# Runbook 03：Redis 不可用

**P1** · SLA 影响：性能下降但服务不全停 · 目标 MTTR：≤ 10 分钟

## 现象 / 触发

- `RedisDown` 告警
- 限流失效（用户能突破单 token RPM）
- 缓存命中率掉零，上游消耗暴涨

## 影响

new-api 配了 `MEMORY_CACHE_ENABLED=true`，Redis 挂了不会全停，但：
- **多实例间缓存不一致**（每个实例独立内存缓存）
- **限流退化为单实例本地**（用户可以分别打两个实例 → 总 QPS 翻倍）
- **多实例间的渠道状态、token 余额等会有延迟同步问题**

所以是 P1 不是 P0，但要尽快修。

## 第一时间动作

```bash
docker compose -f docker-compose.prod.yml ps redis
docker compose -f docker-compose.prod.yml logs --tail 200 redis

# 简单重启
docker compose -f docker-compose.prod.yml restart redis
sleep 10
docker exec new-api-redis redis-cli -a "$(grep REDIS_PASSWORD .env | cut -d= -f2)" ping
```

## 如果 AOF 损坏

```bash
# 进入容器
docker exec -it new-api-redis sh

# 修复 AOF
redis-check-aof --fix /data/appendonly.aof

# 退出，重启
exit
docker compose -f docker-compose.prod.yml restart redis
```

## 如果 Redis 卷彻底完蛋

```bash
# 直接干掉卷重建（缓存层无状态，丢失可接受）
docker compose -f docker-compose.prod.yml stop redis
docker volume rm new-api-prod_redis_data
docker compose -f docker-compose.prod.yml up -d redis
```

⚠️ Redis 数据全丢的影响：
- 缓存重新预热（首次请求慢）
- 限流计数从零开始（用户可能"白嫖"一波，可接受）
- 渠道选择缓存重建（new-api 启动会自动同步）

## 长期改进

部署 Redis Sentinel 3 节点：见 todo `ha`。

## 事后复盘模板

- Redis 不可用时长：
- 期间限流失效是否被利用（看日志）：
- 缓存丢失带来的额外上游消耗：$
- 是否触发上线 Sentinel：
