# DNS 与 Cloudflare 配置

## 域名规划

| 域名 | 用途 | 注册商 |
|---|---|---|
| `example.com` | 主域名 | Cloudflare Registrar |
| `example.io` | 备用 TLD（应对屏蔽） | Namesilo |
| `example.cn` | 国内备案兜底 | 阿里云 |
| `example.app` | 第三备 | Porkbun |

> 不同注册商，避免一锅端。

## DNS 记录（Cloudflare）

```
# 用户 API
api.example.com        CNAME    api-lb.example.com (通过 Load Balancer)
api-staging            A         <staging-ip>
api-canary             A         <canary-ip>

# 管理后台（独立子域）
admin.example.com      A         <us-east-ip>     proxied=true (Cloudflare Access)

# 边缘
edge-ap.example.com    A         <ap-ip>          proxied=true (Argo)
edge-eu.example.com    A         <eu-ip>          proxied=true

# 国内兜底
cn.example.com         A         <hk-ip>          proxied=true
cn.example.cn          A         <aliyun-hk>      proxied=false (国内备案要求)

# 状态页
status.example.com     A         <kuma-ip>        proxied=true

# 文档
docs.example.com       CNAME     <vitepress-pages>

# upstream（不公开！只 VPN 内部访问）
internal.example.com   A         <bastion-ip>     proxied=false   # 只允许办公网/VPN
```

## Cloudflare Load Balancer 配置

```yaml
# Cloudflare Pool: api-pool
pools:
  - name: us-east
    origins:
      - name: gw-1, address: <us-gw1>, weight: 1, enabled: true
      - name: gw-2, address: <us-gw2>, weight: 1, enabled: true
    monitor:
      type: HTTPS
      method: GET
      path: /api/status
      expected_codes: 200
      interval: 30s
      retries: 2
      timeout: 5s

  - name: eu-central
    origins:
      - name: gw-eu1, address: <eu-gw1>, weight: 1, enabled: true
    monitor: { ...同上 }

  - name: ap-southeast
    origins:
      - name: gw-ap1, address: <ap-gw1>, weight: 1, enabled: true
    monitor: { ...同上 }

# Load Balancer
load_balancer:
  name: api-lb.example.com
  default_pool: us-east
  fallback_pool: eu-central

  steering_policy: geo

  region_pools:
    WNAM: us-east     # 北美西
    ENAM: us-east     # 北美东
    SAM: us-east      # 南美
    EU: eu-central    # 欧洲
    AF: eu-central
    ME: eu-central
    APAC: ap-southeast
    OC: ap-southeast

  pop_pools:
    HKG: ap-southeast  # 香港 PoP
    NRT: ap-southeast
    SIN: ap-southeast
    LAX: us-east
    EWR: us-east
    FRA: eu-central

  session_affinity: ip_cookie
  session_affinity_ttl: 3600
  proxied: true
```

## Argo Smart Routing

- 启用 [Cloudflare Argo](https://www.cloudflare.com/products/argo-smart-routing/)
- 平均延迟降低 30%，丢包重路由
- 适合亚太用户回 us-east

## Cloudflare 安全配置

### WAF 规则
```
1. 屏蔽常见漏扫 UA：
   (http.user_agent contains "nikto") or
   (http.user_agent contains "sqlmap") or
   (http.user_agent contains "nmap")
   → Block

2. /admin 仅允许办公网：
   (http.host eq "admin.example.com") and (ip.src ne {OFFICE_IP})
   → Cloudflare Access challenge

3. 限速：单 IP /v1/* 1000 req/min
   → Rate limit
```

### Page Rules
- `admin.example.com/*` Cache: bypass、SSL: Strict
- `api.example.com/v1/chat/completions` Cache: bypass（动态）
- `docs.example.com/*` Cache: standard

### Bot Fight
- 默认开 Bot Fight Mode
- 对 `api.example.com/v1/*` 关闭 super bot fight（避免误杀 SDK）
- 对 admin 开

## 故障切流操作

### 把 us-east 整个摘掉
```bash
# 通过 cf API
curl -X PATCH "https://api.cloudflare.com/client/v4/accounts/${ACCT}/load_balancers/pools/${POOL_ID}" \
  -H "Authorization: Bearer ${CF_TOKEN}" \
  -H "Content-Type: application/json" \
  --data '{"enabled":false}'
```

### 切到备用 TLD
```bash
# 让用户改 base_url 即可，不需要改 DNS
# 文档里始终列两个备用 base_url
```

## 国内访问探测

每分钟从国内多 IDC 探测 `api.example.com`：

```bash
# 探测脚本（在国内某 VPS 跑）
endpoints=(
  "https://api.example.com/health"
  "https://cn.example.com/health"
  "https://cn.example.cn/health"
  "https://cn-bk.example.io/health"
)

for ep in "${endpoints[@]}"; do
    rt=$(curl -o /dev/null -s -w "%{time_total}" "$ep" --max-time 10 || echo "timeout")
    echo "$ep $rt"
done

# 全部 timeout 触发告警 → 立刻发布备用域名给用户
```

## TLS 证书

- 主域 `*.example.com` 用 Cloudflare Universal SSL（自动）
- 备用域名各自申请 Let's Encrypt（cf API DNS-01 challenge 自动续）
- 证书 7 天前过期告警

## 注意事项

- 改 DNS 后等 ≥ TTL（建议 60s 平时，故障切流前提前调到 60s）
- Cloudflare Origin IP 不要泄漏，否则 DDoS 直击源站
- 国内用户**不要直接给 Cloudflare 域名**（被墙概率高），给 HK 反代域名
