# Git 规范

## 分支策略

```
main           ←  生产分支，永远可发布
develop        ←  集成分支（可选，小团队可省）
feature/*      ←  功能分支
hotfix/*       ←  紧急修复
release/*      ←  发版分支（可选）
```

- `main` 受保护：必须 PR + ≥1 reviewer + CI 全绿
- 不允许 force push 到 `main`
- tag 只在 `main` 上打

## 提交规范（Conventional Commits）

```
<type>(<scope>): <subject>

<body>

<footer>
```

### Type

| type | 含义 | 触发 release |
|---|---|---|
| feat | 新功能 | minor |
| fix | bug 修复 | patch |
| perf | 性能优化 | patch |
| refactor | 重构 | - |
| docs | 文档 | - |
| test | 测试 | - |
| chore | 杂项 | - |
| ci | CI | - |
| BREAKING CHANGE | 不兼容变更 | major |

### Scope

| scope | 含义 |
|---|---|
| gateway | new-api 网关代码 |
| sidecar | 智能路由 sidecar |
| upstream | 上游流水线 |
| billing | 计费 |
| risk | 风控 |
| docs | 用户文档 |
| ops | 运维 / Ansible |
| ci | CI/CD |
| deps | 依赖 |

### 示例

```
feat(gateway): 添加 Anthropic 协议跨调用 OpenAI 模型

通过新增 protocol-rewrite 中间件，自动将
/v1/messages 请求转换为 /v1/chat/completions 格式。

Closes #123
```

```
fix(billing): 修复 cached_input 计费错按 input 走

上游已支持 cached input 半价，之前未识别 cache_creation 字段
导致用户多扣费 2x。已加 migration 退还 7 天内多扣的 quota。

Refs: #456
Migration: deploy/migrations/2026-04-25-refund-cache.sql
```

## PR 规范

- 标题：直接用 commit type
- 描述模板（仓库根 `.github/PULL_REQUEST_TEMPLATE.md` 自动注入）：
  ```markdown
  ## 改了什么
  ## 为什么改
  ## 怎么验证
  ## 风险
  ## 回滚方法
  ## Checklist
  - [ ] 加了测试
  - [ ] 文档更新
  - [ ] 影响计费的已通过财务 review
  - [ ] 影响 schema 的有 migration + rollback
  ```

## Tag 与 release

- tag 命名：`v{major}.{minor}.{patch}`（SemVer）
- 仅 `main` 分支打 tag
- 打 tag 自动触发 `deploy-prod.yml`
- changelog 自动从 commits 生成（`git-cliff` 或 `release-please`）

## 配置 / 数据变更（非代码）

| 类型 | 路径 | 同步方式 |
|---|---|---|
| 渠道 | `deploy/channels/*.json` | `sync-channels-from-git.sh` cron |
| 价格 | `deploy/billing/pricing.json` | `apply-pricing.sh` 手动 / CI |
| 限速 | `deploy/risk-control/limits.json` | `apply-defaults.sh` cron |
| Prom 配置 | `deploy/monitoring/prom/*.yml` | hot-reload via SIGHUP |
| Grafana | `deploy/monitoring/grafana/dashboards/*.json` | `dashboard-sync.sh` |
