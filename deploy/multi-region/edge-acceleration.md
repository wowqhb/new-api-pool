# 边缘加速

> 让亚太 / 国内用户访问速度接近本地，不修改主网关架构。

## 方案对比

| 方案 | 复杂度 | 成本 | 抗 GFW | 推荐度 |
|---|---|---|---|---|
| Cloudflare Argo | 低 | $5/月 + 流量 | ✅ | ⭐⭐⭐⭐⭐ |
| Cloudflare Tunnel | 低 | 免费 | ✅ | ⭐⭐⭐⭐ |
| 自建 Wireguard + Caddy | 中 | $50/月 | ⚠️ | ⭐⭐⭐ |
| 阿里云 GA / 腾讯云加速 | 中 | $200+/月 | ✅ | ⭐⭐⭐ |
| Akamai / Fastly | 高 | $$$ | ✅ | 大客户用 |

我们用：**Cloudflare Argo（默认）+ 自建 Wireguard（兜底）**。

## 方案 1：Cloudflare Argo Smart Routing

最简单：在 Cloudflare 控制台启用 Argo，自动加速。

```
Dashboard → Traffic → Argo → On
```

效果：
- 平均延迟降低 30%
- 国内用户走 cf 香港 PoP，1ms 内到达
- 自动避开拥塞链路
- $5/月固定 + $0.10/GB 流量

## 方案 2：自建 Wireguard 边缘 → us-east

适合不想依赖 Cloudflare 的场景。

### 拓扑

```
国内用户 → HK 边缘节点 (Caddy + WG)  ─wg─>  us-east 主网关
                ↓
         (本地 cache 命中可直接返回)
```

### HK 边缘节点配置

`/etc/wireguard/wg0.conf`:
```
[Interface]
PrivateKey = <hk-private-key>
Address = 10.99.0.2/24
ListenPort = 51820

[Peer]
PublicKey = <us-public-key>
Endpoint = <us-public-ip>:51820
AllowedIPs = 10.99.0.1/32
PersistentKeepalive = 25
```

`/etc/caddy/Caddyfile`:
```
api-hk.example.com {
    reverse_proxy https://10.99.0.1:443 {
        header_up Host {http.request.host}
        header_up X-Forwarded-For {http.request.remote.host}
        transport http {
            tls
            tls_insecure_skip_verify  # 内网走 wg，可关 TLS 校验
        }
    }

    encode gzip zstd

    # 健康检查（Cloudflare LB 用）
    handle /health {
        respond "OK" 200
    }

    # 简单 cache 静态接口
    @cache_static {
        method GET
        path /v1/models /v1/dashboard*
    }
    handle @cache_static {
        cache {
            ttl 60s
        }
        reverse_proxy https://10.99.0.1:443 {
            transport http { tls; tls_insecure_skip_verify }
        }
    }
}
```

### 优势
- 完全自主控制
- 可在边缘做协议转换、缓存、限流
- WG 比 Argo 还低 5-10ms（直连专线）

### 劣势
- 需要自己搞节点
- 一个 HK 节点单点
- 如要 HA，需多节点 + Anycast IP

## 方案 3：Cloudflare Tunnel（zero-trust）

不暴露源 IP，源站不需要公网 IP：

```bash
# 在 us-east 网关上跑 cloudflared
cloudflared tunnel create api-prod
cloudflared tunnel route dns api-prod api.example.com
cloudflared tunnel run api-prod
```

优点：源站完全藏起来（连 IP 都泄漏不了）
缺点：所有流量经 Cloudflare，cf 挂全挂

## Cache 策略（边缘做）

- **/v1/models**：cache 60s（模型列表稳定）
- **/api/status**：cache 5s
- **/api/pricing**：cache 1h
- **/v1/chat/completions**：**绝不缓存**（响应内容动态）
- **/v1/embeddings**：cache 1h（同输入同输出）

Caddy 用 [Souin](https://github.com/darkweak/souin) 插件做 HTTP cache。

## 流式（SSE）支持

- 边缘代理必须支持 SSE
- Caddy 默认支持
- Cloudflare 需要确认 origin response 是 `text/event-stream`，否则会被 buffer
- 测试：`curl -N https://api-hk.example.com/v1/chat/completions -d '{"stream":true,...}'`

## 国内 ICP 备案

- 国内云 + 公开服务必须备案（HK 节点不需要）
- 备案流程 2-4 周，需企业资质
- **如果不备案**：用 HK 节点 + Cloudflare 完全可以服务国内用户
- 不要在国内大陆放主域名 A 记录

## 监控

边缘节点也要监控：

```yaml
# Prom 抓 caddy metrics
- job_name: caddy-edge
  static_configs:
    - targets: ['edge-hk-1:2019']

# 关键指标
caddy_http_requests_total{server="api-hk"}    # QPS
caddy_http_request_duration_seconds_bucket    # 延迟分布
caddy_http_responses_status_codes_total       # 状态码分布
```

## 用户文档

在 quickstart 里告诉用户根据地区选 base_url：

```python
base_url_table = {
    "default":   "https://api.example.com/v1",       # 全球
    "asia":      "https://api-hk.example.com/v1",    # 亚太加速
    "cn-backup": "https://cn.example.cn/v1",          # 国内兜底
}
```

或不强制选，cf LB 自动 geo route。
