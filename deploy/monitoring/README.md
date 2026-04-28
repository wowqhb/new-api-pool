# 监控栈

完整可观测性：Prometheus + Grafana + Loki + Promtail + Alertmanager + 各 exporter。

## 启动

在 `deploy/` 目录下：

```bash
# 用两个 compose 文件叠加，监控栈会复用主栈的 internal 网络
docker compose \
  -f docker-compose.prod.yml \
  -f monitoring/docker-compose.monitoring.yml \
  up -d

# 看状态
docker compose \
  -f docker-compose.prod.yml \
  -f monitoring/docker-compose.monitoring.yml \
  ps
```

## 访问

监控服务都只监听 `127.0.0.1`，要外网访问请通过 SSH 隧道或 Caddy 反代加 IP 白名单：

```bash
# SSH 隧道（推荐）
ssh -L 3001:127.0.0.1:3001 -L 9090:127.0.0.1:9090 -L 9093:127.0.0.1:9093 user@server
```

然后浏览器：
- Grafana：`http://127.0.0.1:3001` 用 `.env` 里的 `GRAFANA_ADMIN_USER` / `GRAFANA_ADMIN_PASSWORD`
- Prometheus：`http://127.0.0.1:9090`
- Alertmanager：`http://127.0.0.1:9093`

## 内置看板

启动后 Grafana 会自动加载 `New API/New API 总览` 看板，包含：

- QPS / 5xx 错误率 / p95 延迟 / 并发数（4 个核心指标卡）
- 状态码分布趋势
- 延迟分位趋势（p50/p95/p99）
- Token 消耗趋势（按模型）
- TTFT p95（按模型）
- 渠道请求量 Top 20
- 上游探活状态

更多看板可在 Grafana 里手动建，或丢 JSON 进 `monitoring/grafana/dashboards/`。

## 告警规则

`monitoring/rules/` 下三组：

- `gateway.yml`：网关层（实例存活、错误率、延迟、并发、TTFT）
- `infra.yml`：基础设施（CPU/内存/磁盘、PG、Redis、上游探活）
- `business.yml`：业务（渠道大批失败、用户异常消耗、TTFT 全面恶化、备份过期）

按 P0/P1/P2 分级，全部走 Telegram。**P0 收到立刻人响应**，其它走值班轮换。

## 自定义

- 改采集频率：`prometheus.yml` 的 `scrape_interval`
- 改保留：Prometheus `--storage.tsdb.retention.time`、Loki `retention_period`
- 加上游探活：`prometheus.yml` 的 `blackbox_upstream` job 加 target
- 改告警阈值：`rules/*.yml` 直接改，`docker compose exec prometheus kill -HUP 1` 热加载

## 排错

```bash
# Prometheus 抓得到 metrics 吗
docker exec new-api-prometheus wget -qO- http://new-api-1:3000/metrics | head

# 告警规则有没有加载
curl http://127.0.0.1:9090/api/v1/rules | jq '.data.groups[].name'

# Alertmanager 测试 Telegram 是否通
docker exec new-api-alertmanager amtool alert add test severity=P2 \
  --alertmanager.url=http://localhost:9093

# Loki 接收日志了吗
docker exec new-api-loki wget -qO- http://localhost:3100/ready
```
