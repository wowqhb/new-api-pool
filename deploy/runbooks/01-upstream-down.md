# Runbook 01：主上游 API 全挂

**P0** · SLA 影响：100% · 目标 MTTR：≤ 10 分钟

## 现象 / 触发

- `UpstreamDown` 告警同时点亮（OpenAI + Anthropic + Google 至少 2 家）
- `NewApiHighErrorRate` 5xx 错误率 > 50%
- 用户大量反馈"全挂了"

## 第一时间动作（5 分钟内）

1. **确认是上游问题还是自己问题**：
   ```bash
   # 直接从服务器探测一下
   curl -I --max-time 10 https://api.openai.com/v1/models
   curl -I --max-time 10 https://api.anthropic.com/v1/messages
   curl -I --max-time 10 https://generativelanguage.googleapis.com/v1beta/models
   ```
   - 如果三家全 timeout：本机/机房出网问题（看第 2 步）
   - 如果某家 5xx：上游真的挂了（看第 3 步）

2. **机房出网问题**：
   - 联系机房 / 切到备用机房
   - 临时切到可用 region 的备用节点（如果有）

3. **上游真的挂了**：
   - 看 [status.openai.com](https://status.openai.com) / [status.anthropic.com](https://status.anthropic.com) / [status.cloud.google.com](https://status.cloud.google.com)
   - **强制路由切到还活着的厂商**：
     ```bash
     # 在管理后台 → 渠道，把挂掉厂商的所有渠道临时禁用
     # 或者 SQL 直接禁用整个分组
     docker exec -it new-api-postgres psql -U newapi -d newapi -c "
       UPDATE channels SET status = 2 WHERE \"group\" LIKE '%openai%';
     "
     ```
   - 如果是 Claude 挂了，把所有 Claude 模型在网关层做模型映射临时改成 GPT 等价模型（管理后台 → 模型重定向）

4. **状态页 + 公告**（5 分钟必发）：
   - 状态页改"部分服务受影响"
   - Telegram 频道发公告："XX 上游正在维护，已自动切换备用，部分模型可能不可用"

## 排查继续

```bash
# 看渠道实时调用
curl -s http://127.0.0.1:9090/api/v1/query?query='sum%20by%20(channel)%20(rate(newapi_llm_request_total{status%3D~"5.."}[5m]))' | jq

# 看具体错误
docker compose -f docker-compose.prod.yml logs --tail 500 new-api-1 | grep -i "error\|fail" | tail -50
```

## 上游恢复后

- 确认探活全绿
- 把临时禁用的渠道恢复（按 group 批量启用）
- 状态页改"正常"
- Telegram 公告恢复

## 事后复盘模板

- 触发时间：
- 发现时间：
- 恢复时间：
- 根因：
- 受影响用户数：
- 损失（金额/口碑）：
- 改进项：
- 责任值班：
