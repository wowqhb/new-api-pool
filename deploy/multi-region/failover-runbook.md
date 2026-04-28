# 区域故障切流 Runbook

> 所有切流操作要 **2 人确认**，至少一个是值班负责人。

## 场景 1：us-east 主网关全挂

### 触发
- Cloudflare LB 健康检查 us-east 全部 down
- Prom 报警 `up{region="us-east"}==0` 持续 3 分钟
- 用户工单激增

### 操作（< 5 分钟）

```bash
# 1. 确认其它 region 健康
curl -fsS https://api-eu.example.com/health
curl -fsS https://api-ap.example.com/health

# 2. 强制把 us-east pool 摘掉
deploy/multi-region/scripts/disable-pool.sh us-east

# 3. 验证流量已切走
curl -I https://api.example.com/health
# 应该看到 cf-ray header 来自 EU/AP

# 4. 状态页公告
deploy/multi-region/scripts/post-status.sh \
  "🟡 us-east region 故障，已切流到 eu-central，部分用户可能略有延迟"

# 5. Telegram 通报
```

### 后续
- 调查 us-east 故障根因（机房 / 网络 / 系统）
- 修复后**先内部验证**，再灰度切回 10% → 50% → 100%
- 写 RCA

## 场景 2：DB 主集群（us-east）整个不可用

### 触发
- Patroni 没有 leader > 1 分钟
- 所有写都失败
- 自动 failover 没起作用

### 操作（< 15 分钟）

```bash
# 1. 检查 Patroni 状态
ssh pg-1 "patronictl -c /etc/patroni.yml list"

# 2. 如果集群整体不可用（如 etcd 也挂），手动 promote eu-central 副本
ssh pg-eu-1 "pg_ctl promote -D /var/lib/postgresql/data"

# 3. 改 new-api 配置指向 eu 主库（紧急）
ansible all -i inventories/production.yml \
  -m lineinfile \
  -a "path=/opt/new-api/.env regexp='^SQL_DSN=' line='SQL_DSN={{eu_dsn}}'"

# 4. 重启所有 new-api 实例
ansible all -i inventories/production.yml \
  -m shell -a "cd /opt/new-api && docker compose restart new-api"

# 5. 公告 + 监控（写入将走跨区，会有 80ms+ 延迟）
```

### 后续
- 这是 P0 事件，必须 24h 内 RCA
- 演练频率提到月度
- 评估是否需要双 active 集群（昂贵）

## 场景 3：Cloudflare 整个被挡（罕见但发生过）

### 触发
- 全球用户都报 1xxx 错误
- Cloudflare 状态页 [cloudflarestatus.com](https://www.cloudflarestatus.com) 红
- 我们这边什么都做不了

### 操作

```bash
# 1. 切回直连域名（不走 CF）
deploy/multi-region/scripts/dns-direct.sh

# 这个脚本：
# - 把 api.example.com DNS 临时改到直 IP（绕过 CF proxy）
# - 拉起备用证书（Let's Encrypt 直签）
# - 给用户公告新 IP

# 2. 同时启动备用域名 api.example.io（不走 CF）

# 3. 公告：贴出三个备用 base_url，让用户挨个试

# 4. 等 Cloudflare 恢复，切回原配置
```

## 场景 4：国内访问全断

### 触发
- 国内监控点 5 分钟都 timeout
- 国内用户工单暴涨

### 操作

```bash
# 1. 紧急启用备用 TLD
deploy/multi-region/scripts/cn-failover.sh

# 这个脚本：
# - 启用 cn.example.cn / cn.example.io 等多个 HK 节点
# - 推送给国内用户群（Telegram 备份频道）

# 2. 状态页加 banner

# 3. 评估根因：DNS 污染 / IP 被墙 / 域名被墙
#    域名被墙 = 永久换，IP 被墙 = 换 HK 节点 IP

# 4. 准备公告：建议国内用户加 host / 用魔法上网工具
#    但**不要在文档里教翻墙**（合规）
```

## 场景 5：上游全部限流（OpenAI / Claude / Gemini 都 429）

### 触发
- 全部分组健康率 < 50%
- 主要是 429

### 操作

```bash
# 1. 立刻提升缓存命中率（启用更激进缓存）
deploy/cost-cache/scripts/aggressive-mode.sh

# 2. 启用 free 用户的"等待队列"模式
deploy/risk-control/scripts/enable-queue.sh --group free

# 3. VIP 优先走官方 Key
# 4. 第三方分组临时升级 priority

# 5. 通告用户：上游全网压力，我们排队中，请稍等
```

## 切流操作的 dos & don'ts

✅ **DO**
- 先看 Cloudflare / 上游状态页
- 确保至少另一个 region 健康再切
- 公告比技术修复更重要（用户不知道你在干啥就会跑）
- 切完后立刻看监控，1 小时内不离岗

❌ **DON'T**
- 不要在 Cloudflare 没确认的情况下盲目切 DNS（污染缓存）
- 不要同时改太多东西（一次只改一项）
- 不要在 P0 时跑回归测试（来不及）
- 不要忘记关闭"维护模式"

## 切流后必做

- [ ] 写时间线（精确到分钟）
- [ ] 保留所有日志 / metrics（48h 后可能被清）
- [ ] RCA 报告（24h 内）
- [ ] 改进项 + owner + 截止日期
- [ ] 复盘会
