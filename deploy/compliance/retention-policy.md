# 数据保留策略

## 总原则

- **最小化保留**：只在合理目的范围内保留
- **明示保留期**：在隐私政策里写清楚
- **自动到期清理**：cron 跑，不靠人工
- **法律需求例外**：财务/审计相关延长

## 自动清理 cron

```
# /etc/cron.d/aitransfer-retention

# 每天 03:00 清理过期日志
0 3 * * * postgres /opt/aitransfer/scripts/retention-clean.sh logs

# 每天 03:30 IP 段模糊化
30 3 * * * postgres /opt/aitransfer/scripts/retention-clean.sh ip-anonymize

# 每周日 04:00 清理过期备份
0 4 * * 0 root /opt/aitransfer/scripts/retention-clean.sh backups

# 每月 1 号 05:00 注销满 30 天的账号清理
0 5 1 * * postgres /opt/aitransfer/scripts/retention-clean.sh deleted-users
```

## 数据生命周期

```
注册
  ↓
活跃使用 ─── 全字段保留
  ↓
30 天不活跃 ─── 标记 dormant
  ↓
180 天不活跃 + 余额 0 ─── 邮件提醒
  ↓
365 天不活跃 + 余额 0 ─── 软删除（status=deleted）
  ↓
软删除 + 30 天 ─── 硬删除（除财务记录留 7 年）
```

## 保留期对照表

| 数据 | 默认 | 法律延长 | 删除方式 |
|---|---|---|---|
| 用户帐号（活跃）| 永久 | - | 用户主动删 |
| 用户帐号（注销）| 30 天 buffer | - | UPDATE → 邮箱/用户名匿名化，但 user_id 保留以维护财务关联 |
| 登录记录 | 90 天 | 1 年（中国）| DELETE |
| API 调用日志（元数据）| 90 天 | - | DELETE |
| API 调用日志（内容）| **0 天 / 24 小时** | - | 默认不存 |
| 充值订单 | 7 年 | 5-10 年（财务/税务）| 永久（合规需要）|
| 退款记录 | 7 年 | 同上 | 永久 |
| 兑换码 | 已使用永久（财务）| - | - |
| 备份（每日）| 30 天 | - | DELETE |
| 备份（月度归档）| 5 年 | - | DELETE |
| 系统审计日志 | 1 年 | - | DELETE |
| Cloudflare WAF 日志 | 1 年 | - | DELETE |
| Loki 应用日志 | 7 天 | - | 自动 retention |

## 注销账号的"匿名化"

注销不能立刻硬删（财务/审计要留），先匿名化保留 user_id：

```sql
UPDATE users SET
  username = 'deleted_' || id,
  email = 'deleted_' || id || '@example.invalid',
  phone = NULL,
  display_name = '已注销',
  github_id = NULL,
  wechat_id = NULL,
  status = 99,  -- deleted
  deleted_at = NOW()
WHERE id = ?;

-- token 全部禁用
UPDATE tokens SET status = 3 WHERE user_id = ?;
```

财务关联（`topups.user_id`、`logs.user_id`）保留，但通过 `users.username='deleted_X'` 与人解绑。

## 备份策略

- 每日全量：`scripts/backup.sh`，加密 + 异地（已实现）
- 月度归档：每月 1 号备份永久保留 5 年
- 备份保留检查：每月 1 号自动 verify 一次（restore 到临时库）

```bash
# 已经在 deploy/scripts/backup.sh，加月度逻辑：
if [[ $(date +%d) -eq 01 ]]; then
    cp "$out" "$ARCHIVE_DIR/monthly-$(date +%Y-%m).tar.gz.enc"
fi
```
