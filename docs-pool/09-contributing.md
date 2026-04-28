# 贡献协作约定

> 这是私人 fork，但仍建议按"团队规范"来写代码——半年后接手的就是另一个自己。

---

## 1. 在动手之前

### 1.1 确认你要做的事属于哪一类

| 类别 | 例子 | 流程 |
|---|---|---|
| **bug 修复** | "调上游必现 401" | 直接修 → 写 commit → 进 changelog |
| **小改进** | 加一个字段 / 改 UI 文案 | 直接改 → commit → 文档同步 |
| **新功能** | 加一个新菜单 / 新表 | 先写 ADR → 跟自己达成共识 → 再写代码 |
| **破坏性变更** | 改 API 形状 / 删表 | 先写 ADR → 备份现网 db → 写迁移脚本 → 改文档 → commit |

### 1.2 总览以下文档（5 分钟）

- [`05-architecture/decisions.md`](./05-architecture/decisions.md) — 已经决定过的事，别重新讨论
- [`02-development/coding-standards.md`](./02-development/coding-standards.md) — 风格统一
- [`07-reference/changelog.md`](./07-reference/changelog.md) — 最近改过什么

---

## 2. 分支策略

私人 fork，但仍建议：

```
main                 ← 永远可编译可部署的稳定状态
feat/<short-name>    ← 一个功能一个分支
fix/<short-name>     ← 一个修复一个分支
docs/<short-name>    ← 纯文档改动
```

**不在 main 上直接写代码**——除非是一行 typo。

---

## 3. Commit 信息规范

固定前缀：

| prefix | 用途 | 例 |
|---|---|---|
| `feat` | 新功能 | `feat(pool): 加一键绑定 channel` |
| `fix` | bug 修复 | `fix(pool): channel.Insert 替换 DB.Create 修复路由 0 行` |
| `refactor` | 重构（不改行为） | `refactor(pool): 抽 PoolPageLayout 共用组件` |
| `docs` | 文档 | `docs: 加 troubleshooting 排错手册` |
| `chore` | 构建 / 工具 / 依赖 | `chore: bump bun -> 1.2` |
| `test` | 加测试 | `test(pool): pool_recipe seeds 单元测试` |
| `style` | 仅格式化 | `style: gofmt 全 service/` |

**格式**：

```
fix(pool): channel.Insert 替换 DB.Create 修复路由 0 行

根因：
  DB.Create(ch) 不调 AddAbilities()，abilities 表永远为空，
  /v1/* 路由匹配不到。

修复：
  controller/pool.go::AddPoolAccount / ManualSubmitJobResult /
  BindPoolAccountChannel + service/pool_worker.go::runJob
  全部改为 ch.Insert()。

影响：
  自动建渠道 / 半自动建渠道 / 自动绑定 都立即可路由。
  无表结构变更。

Refs: ADR-0005
```

写 commit 像写一篇 200 字的小作文：**根因 + 修复 + 影响**，三段。

---

## 4. PR / 自合并清单

私人 fork 不一定走 PR，但 push main 之前自检：

- [ ] `gofmt -w .` 跑过
- [ ] `cd new-api-src && go build ./...` 编译过
- [ ] `cd new-api-src/web && bun run lint` 没新增 ESLint 错
- [ ] 改了 API 形状 → 改了 [`07-reference/pool-api.md`](./07-reference/pool-api.md)
- [ ] 改了表结构 → 改了 [`05-architecture/data-model.md`](./05-architecture/data-model.md) + 写了迁移
- [ ] 改了菜单 → 改了 [`04-usage/pool-management.md`](./04-usage/pool-management.md)
- [ ] 加了 Recipe → 改了 [`04-usage/recipe-walkthrough.md`](./04-usage/recipe-walkthrough.md)
- [ ] 写了 [`07-reference/changelog.md`](./07-reference/changelog.md) 一条
- [ ] 重大决策 → 写了 [`05-architecture/decisions.md`](./05-architecture/decisions.md) ADR

---

## 5. 写代码风格速查

### Go

- **不**给 bool 字段写 `gorm:"default:true/false"` —— 会触发 zero-value 陷阱（[ADR-0009](./05-architecture/decisions.md#adr-0009seed-函数加非空-fallback-保护避免-gorm-默认值陷阱)）
- 写 channel 入库**只用** `ch.Insert()`，不用 `DB.Create(ch)`（[ADR-0005](./05-architecture/decisions.md#adr-0005channel-写入必须用-chinsert不允许-dbcreatech)）
- 错误打印 `common.SysLog("[pool] ...: " + err.Error())`，**前缀 `[pool]` 必带**
- HTTP 写 ApiSuccess/ApiError/ApiErrorMsg，不要直接 `c.JSON`
- 长函数（> 80 行）拆 helper

### React

- 表单 Modal 必须 `destroyOnClose + key={editing?.id} + initValues={editing}`，否则编辑空数据
- 用 `Notification.error/success` 而不是 alert / console.log
- API 调用统一走 `api/api.js` 里的 `API.get/post/put/delete`，不要直接 `fetch`
- 文案中文为主，按钮一律加 emoji 前缀（与 new-api 原生对齐）

### SQL

- 关键字 `group` / `order` / `key` 必须反引号 `` `group` ``
- 不要写 `SELECT *`，列出字段
- 改大表前先 `EXPLAIN QUERY PLAN`

---

## 6. 文档维护

> 这是这个 fork 区别于"野生项目"的关键。

- 改代码 = 同时改文档（同一 commit）
- 不要写"我后面再补文档"——后面就是没有
- 文档示例代码必须能复制粘贴跑通
- 不放假数据 / 假表名

新加 markdown 文件统一：
- 顶部 `> 一句话目的` 引用块
- `## 1. xxx` 数字编号
- 文末没有"以上"/"完"/"END"

---

## 7. 不可越界的 5 件事

1. ❌ **不删 ADR**：决策错了写新 ADR `superseded by`，老的留着
2. ❌ **不在文档里编造数据**：所有 SQL / 数据 / 截图引用都要能反查到文件 / 行
3. ❌ **不强行升级上游 new-api**：fork 已选择独立维护路线（[ADR-0001](./05-architecture/decisions.md#adr-0001走-fork--自编译路线不走-plugin--sidecar)），想跟上游就重新 fork 一份
4. ❌ **不在生产改 SQLite 表结构**：先停服 → 备份 → 改 → 启动 → 自检
5. ❌ **不把 token / key / 备份明文 commit 到 git**：用 `git secrets` 或人工自查

---

## 8. 与上游 new-api 的关系

- 我们是**事实上的 hard fork**——不再 cherry-pick 上游
- 上游有破坏性更新（如改 Channel.Insert 签名）会让我们编译失败 → 这时**手动适配**，不要硬合并
- 仍可以从上游 issue / discussion 学问题解法，但落到代码以本 fork 为准

---

## 9. 让接手者 1 小时内能上手

如果有同事 / 自己半年后回来，按这个顺序读：

1. [`README.md`](./README.md) — 5 分钟知道这是什么
2. [`01-overview/architecture.md`](./01-overview/architecture.md) — 15 分钟知道架构
3. [`02-development/setup.md`](./02-development/setup.md) — 30 分钟跑起来
4. [`04-usage/admin-quickstart.md`](./04-usage/admin-quickstart.md) — 5 分钟会用
5. [`05-architecture/decisions.md`](./05-architecture/decisions.md) — 10 分钟知道为什么这么做

> 如果以上 5 篇看完还有疑问 = 文档没写好，回去补。
