# Cloudflare 配置

## DNS

- `api.example.com` → 服务器 IP，**Proxied (橙云)**
- `admin.example.com` → 服务器 IP，**Proxied**
- `status.example.com` → 状态页（Uptime Kuma 服务器），Proxied
- `metrics.example.com` → Grafana（仅内部，加 Cloudflare Access）

## SSL/TLS

- Mode: **Full (strict)**
- Edge Certificate: Always Use HTTPS, Min TLS 1.2, Auto HTTPS Rewrites
- HSTS: Enable, Max Age 12 months, Include subdomains, Preload

## Authenticated Origin Pulls

```
SSL/TLS → Origin Server → Authenticated Origin Pulls → Enable
```

服务器 Caddy 改成只接受 Cloudflare 客户端证书的连接（参考 `caddy/Caddyfile`）：

```caddyfile
{
    # 全局开 client_auth
    servers {
        listener_wrappers {
            tls_client_auth {
                mode require_and_verify
                trusted_ca_cert_file /etc/caddy/cf-origin-pull-ca.pem
            }
        }
    }
}
```

CA 证书在 [Cloudflare 文档](https://developers.cloudflare.com/ssl/origin-configuration/authenticated-origin-pull/) 下载。

## WAF Rules

| 规则 | 动作 |
|---|---|
| `(http.host eq "admin.example.com") and (ip.geoip.country ne "CN" and ip.geoip.country ne "HK" and ip.geoip.country ne "US")` | Block |
| `(http.request.uri.path matches "^/api/(v1|v2)/.*") and not ssl` | Block |
| `not http.request.headers["user-agent"][0]` | Managed Challenge |
| `http.user_agent contains "curl"` and `http.request.uri.path eq "/v1/chat/completions"` | Allow（合法用户用 curl） |
| Bot Fight Mode | On |
| Super Bot Fight (付费) | On (block AI scrapers) |

## Rate Limiting Rules（按 IP）

| 路径 | 阈值 | 动作 |
|---|---|---|
| `admin.example.com/*` | 30/min | Block 1h |
| `api.example.com/api/login` | 10/min | Block 10min |
| `api.example.com/v1/*` | 600/min（按 IP）| Challenge |

**注意**：v1 路径是付费 API，有用户的合法高频调用，不要设太低。

## Cloudflare Access（管理后台）

```
Access → Applications → Add Application → Self-hosted
Subdomain: admin
Path: *
Identity providers: Google / GitHub / OTP-via-email
Policy: Allow if email in @example.com 或 specific email list
Session duration: 24h
Require MFA: Yes
```

这一步把 admin 域名变成"必须先过 Cloudflare 登录才能到 Caddy"，比 IP 白名单灵活。

## Page Rules / Cache

- `api.example.com/*` → Cache Level: **Bypass**（API 不缓存）
- `admin.example.com/*` → Bypass
- `status.example.com/*` → Standard（公开状态页可以缓存）

## DDoS / Bot Protection（付费）

- Pro 套餐已含 Advanced DDoS
- Argo Smart Routing：海外用户加速 30%（贵 5$/月起）
- Magic Transit：超大流量场景（按需）
