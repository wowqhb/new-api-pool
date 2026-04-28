# 回滚 SOP

## 黄金原则

> **先回滚，后排查。** 用户体感比根因分析重要。

## 触发条件（任一即触发）

- 错误率 > 5% 持续 3 分钟
- p95 > 10s 持续 5 分钟
- 关键功能（鉴权 / 计费 / 路由）报错
- 数据库写入失败
- 客服 P0 工单 ≥ 3 单 / 30 分钟

## 回滚动作（按耗时从短到长）

### 1. 切流到上一版本（< 1 分钟）

```bash
# CI/CD 脚本一键回滚
bash deploy/cicd/scripts/rollback.sh

# 或在 GitHub Actions 触发 deploy-prod.yml workflow_dispatch，填入上一 tag
```

### 2. 配置回滚（< 5 分钟）

如果是配置（不是镜像）问题：

```bash
# 通过 Git revert 上一个 PR
git revert HEAD
git push

# 等 CI 自动部署 staging → 通过后再人工触发 prod
# 紧急情况下也可手动 sync：
deploy/scripts/sync-channels-from-git.sh --revision HEAD~1
```

### 3. 数据库 schema 回滚（5-30 分钟，最危险）

```bash
# 用 Atlas / sqitch / 自建 migration 工具
atlas migrate down --env production --to {previous_version}

# 注意：必须配套回滚代码，否则代码会查不到字段
```

> ⚠️ schema 回滚极其危险，**永远先在 staging 演练 ≥ 1 次**。

### 4. 上游渠道隔离（< 1 分钟）

如果是某分组渠道全挂：

```bash
# 暂时禁用一个分组
deploy/scripts/group-disable.sh --group official

# 或路由强制切到另一分组
deploy/scripts/route-override.sh --from official --to claude-oauth
```

## 回滚后必做

1. **公告**：状态页 + Telegram + 用户邮件
2. **保留现场**：把回滚前 30 分钟日志、metrics、错误样本 dump 到对象存储
3. **复盘**：48h 内出 RCA（root cause analysis）

## RCA 报告模板

```markdown
# RCA：YYYY-MM-DD - {问题简述}

## 影响
- 时间窗：HH:MM - HH:MM (X 分钟)
- 受影响用户：~XXX 人
- 经济损失：$XX（退款 + 流失）

## 时间线（精确到分钟）
- HH:MM 部署开始
- HH:MM Prom 错误率告警
- HH:MM 值班响应
- HH:MM 决定回滚
- HH:MM 回滚完成
- HH:MM SLO 恢复

## 根因
（如果还在查，写"调查中"）

## 改进项（带 owner + 截止日期）
- [ ] @xxx by 2026-MM-DD：…
- [ ] @yyy by 2026-MM-DD：…
```

## 演练频率

- 月度：staging 自动回滚演练（CI cron）
- 季度：生产模拟回滚（在维护窗口内）
- 重大版本前：必须演练
