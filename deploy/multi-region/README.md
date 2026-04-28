# 多区域部署

> 解决：① 海外节点低延迟跑注册 / 主网关 ② 国内用户加速访问 ③ 单区故障兜底。

## 区域规划

| 区域 | 角色 | 推荐 IDC | 用途 |
|---|---|---|---|
| **us-east** | 主网关（primary）| Hetzner / Vultr Ashburn / Linode Newark | 主网关，对接 US 上游 |
| **eu-central** | 备网关（standby）| Hetzner Falkenstein | 容灾 + 欧洲用户 |
| **ap-southeast** | 边缘加速 | Vultr Tokyo / SG | 国内 / 东亚用户 |
| **upstream-iso** | 注册流水线 | 完全独立 IDC（如 OVH FR）| 注册号流水线，与主网关物理隔离 |
| **cn-edge**（可选）| 国内边缘 | Aliyun HK / 腾讯云 HK | 国内用户兜底（不走 GFW）|

> 国内**绝对不放主网关**——封一次域名整盘损失。HK 节点也只做加速 / 兜底。

## 网络拓扑

```mermaid
flowchart TB
    Users[全球用户]
    Users --> CF[Cloudflare 智能解析<br/>+ Argo Smart Routing]
    CF -->|US 用户| USGW[us-east 主网关]
    CF -->|EU 用户| EUGW[eu-central 备网关]
    CF -->|亚太用户| APGW[ap-southeast 加速节点]
    CF -.cn 解析失败|HKGW[hk 兜底]

    USGW --> PG_US[(PG 主集群<br/>us-east)]
    EUGW --> PG_EU[(PG 只读副本<br/>eu-central)]
    APGW --> PG_US
    HKGW --> APGW

    PG_US -.async replica.-> PG_EU

    USGW <-->|metrics + logs| Mon[Prom + Loki<br/>us-east]
    EUGW --> Mon
    APGW --> Mon

    UpstreamReg[upstream-iso<br/>注册流水线] -->|API 注入| USGW
    UpstreamReg -.- 物理/账号/资金完全隔离
```

## 区域职责

### us-east（主）
- new-api 网关 4-6 实例
- PG Patroni 主集群（3 节点）
- Redis Sentinel
- 管理后台（admin.example.com 走 Cloudflare Access）
- 监控（Prom / Grafana / Loki）
- **几乎所有上游 API 调用源 IP 都从这**（OpenAI / Anthropic / Google 不友好的国内 IP）

### eu-central（备）
- new-api 网关 2 实例（warm standby）
- PG 异步副本（streaming replication）
- 平时承 EU 用户流量；US 故障切流到这
- 不放 admin

### ap-southeast（加速）
- 仅 Caddy / Nginx + 协议转换
- **不存任何用户数据**（DB 都打回 us-east）
- TLS 终止在边缘
- 用 [Cloudflare Argo Tunnel](https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/) 或自建 Wireguard 回中心

### upstream-iso（注册流水线）
- 独立 VPC、独立账号实体、独立支付主体
- 出网用住宅代理，绝不与主网关共用 IP
- 通过 mTLS + 独立 API key 调主网关 `/api/channel`
- 单向：流水线 → 主网关；主网关绝不访问流水线

### cn-edge（兜底，可选）
- 国内 / HK CN2 节点
- 仅做反代到 ap-southeast
- 备用域名（不一样的注册商，不一样的 TLD）
- DNS 走 Cloudflare（关注被劫持）+ 备用 DNSPod

## DNS / 流量调度

### 智能解析（Cloudflare Geo Steering）

```
api.example.com    →  CNAME edge.cf.example.com
edge.cf.example.com:
  US/CA/SA → us-east 直接 IP
  EU/AF    → eu-central 直接 IP
  AS/OC    → ap-southeast Argo IP
  fallback → us-east
```

### 健康检查 + 故障切流

- Cloudflare Load Balancer 监听 `/api/status`，30s 一次
- 单区域 3 次失败自动从池里摘除
- 摘除后流量自动落到次优 region

### 国内兜底链

```
1. cn-edge.example.com  （Cloudflare → HK 节点）
2. cn-bk.example.cn     （阿里云 → HK 节点，备用 TLD）
3. cn-direct.example.io （直 IP，无 CDN）
```

文档里给用户列三条，挨个试。

## 数据一致性

### 跨区域写

- **只在 us-east 写**（主库）
- 其它 region 的 new-api 实例 `SQL_DSN` 指向 us-east（VPN/专线）
- 接受**写延迟 ~100ms**（亚太到 us-east），换取强一致

### 跨区域读

- EU / AP 实例可以读本地 PG 副本（异步流复制）
- 用 [pgbouncer](https://www.pgbouncer.org/) 把读走副本，写走主库

### Redis 不跨区

- 每 region 自己一套 Sentinel
- new-api 内存缓存 + Redis 缓存都是本地的
- Redis 数据丢了无伤大雅（重新 build cache）

## 跨区域延迟（基线）

| 路径 | 延迟 | 备注 |
|---|---|---|
| US-EU | 80-100 ms | 同步副本不可行，只能异步 |
| US-AP | 130-180 ms | 必须异步，写延迟用户能感知 |
| EU-AP | 200-250 ms |  |
| HK-上海 | 30-50 ms | 国内骨干 |
| HK-华北 | 50-80 ms |  |
| HK-华西/华南 | 30-60 ms |  |

## 各区域成本估算（小规模）

| 区域 | 月成本 | 配置 |
|---|---|---|
| us-east | $200 | 2× 4C/8G + DB 3× 4C/16G + Redis 3× 2C/4G |
| eu-central | $80 | 2× 4C/8G + 1× DB replica |
| ap-southeast | $50 | 1× 4C/8G 反代 |
| upstream-iso | $100 | 1× 8C/16G + 住宅代理 $50/月 |
| cn-edge | $40 | 1× HK 2C/4G |
| Cloudflare LB | $10 | 标准 plan |
| **合计** | **~$480/月** | 不含上游成本 |

## 部署顺序

1. us-east 先建好，全功能跑通
2. eu-central 起 standby + DB 副本，演练 failover
3. ap-southeast 加边缘
4. upstream-iso 独立建
5. cn-edge 最后（看市场需求）

## 故障切流演练

- 月度：DNS 切走 us-east 流量，eu-central 接手 30 分钟
- 季度：完全停 us-east 1 小时，验证 eu-central 全功能
- 恢复后：把流量逐步切回（先 10% / 50% / 100%）

## 法律考量

- 各区域**收款主体不要混**：us 公司收 us 流量、eu 公司收欧元
- GDPR：EU 用户数据**只能存 EU**（PG 副本 + 日志路由）
- PIPL：国内用户数据如要存，必须存国内
- DMCA：us 主体接 DMCA 通知；eu 主体接 GDPR 删除请求

详见 [`legal/data-residency.md`](../legal/data-residency.md)（如未来需要分主体）。

## 相关文件

- [`dns-config.md`](./dns-config.md) DNS 与 Cloudflare 配置详解
- [`failover-runbook.md`](./failover-runbook.md) 区域故障切流操作手册
- [`pg-cross-region.md`](./pg-cross-region.md) 跨区域 PG 副本设置
- [`edge-acceleration.md`](./edge-acceleration.md) Argo Tunnel / Wireguard 边缘加速
