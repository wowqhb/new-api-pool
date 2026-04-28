# 风控配置

对外付费场景下，**没有风控就是给薅羊毛党免费送钱**。这里覆盖三层：

1. **令牌级**：单 API Token 的 RPM/TPM/IP/过期/最大消耗
2. **用户级**：日消耗上限、模型白名单、注册控制
3. **系统级**：邀请码、IP 日志、关键告警阈值

## 一键应用

```bash
bash scripts/apply-defaults.sh
bash scripts/gen-invite-codes.sh 100      # 生成 100 个邀请码
```

## 默认风控档位（按用户分组）

参考 [`limits.json`](./limits.json)。每个 `default` 用户初始默认：

| 项 | 值 | 备注 |
|---|---|---|
| 单令牌 RPM | 60 | 60 次/分钟 |
| 单令牌 TPM | 200,000 | 20w token/分钟 |
| 用户日消耗上限 | 5,000,000 quota（≈ $10）| 防被刷 |
| 单令牌过期 | 365 天 | 强制定期刷新 |
| 单令牌最大消耗 | 10,000,000 quota（≈ $20）| 单 token 总额封顶 |
| IP 限制 | 关闭 | 用户主动开 |

`free` 用户更狠：日上限 $1，限模型，关注册。

## 关键告警（已经在 Prometheus rules 配了）

- 单用户 1h 输出 > 5M tokens（防刷）→ `business.yml` 已加
- 渠道连续失败 → `gateway.yml` 已加
- 系统级：在 `business.yml` 加单用户日消耗 > $50 立即冻结的规则

## 注册策略

强烈推荐：**关闭公开注册 + 邀请码**。

```bash
# 已经在 init-groups.sh 关掉公开注册
# 现在批量发邀请码
bash scripts/gen-invite-codes.sh 50
```

## 应急冻结

当用户出问题（疑似刷号、异常活动）：

```bash
# 冻结单个用户
bash scripts/freeze-user.sh <username|email>

# 冻结某 IP 段所有用户的 token（可疑 ASN）
bash scripts/freeze-by-ip.sh 1.2.3.0/24
```
