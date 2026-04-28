# 编码规范

不追求一次写到位的"完美工程"，但守住几条底线，避免下次接手时骂街。

## 1. 通用原则

1. **能少写一行就少写一行**——所有"为了将来扩展"的抽象都不要做，等真正需要时再 refactor。
2. **改代码同时改文档**——尤其是 [04-usage/](../04-usage/) 的 UI 描述、[07-reference/](../07-reference/) 的 API 列表、[05-architecture/](../05-architecture/) 的字段说明。
3. **不要写假实现 / mock**——一是把人骗了；二是 mock runner 之前已经引发过事故，全部删掉了。
4. **所有上游交互都加超时 + log**——上游一卡就是 30 秒，没 log 等于黑盒。

## 2. Go（后端）

### 2.1 文件组织
- `controller/`：纯 HTTP handler，签名 `func XxxHandler(c *gin.Context)`，不放复杂逻辑（>50 行的拆到 service）。
- `service/`：业务逻辑、第三方集成、后台 cron / worker。**只有 service 能调外部 HTTP**。
- `model/`：GORM 结构体 + 自定义查询。**只有 model 直接碰 DB**。
- `router/`：只放路由表，不写逻辑。

### 2.2 命名
- 表名复数（`pool_accounts` / `pool_recipes`），结构体单数（`PoolAccount` / `PoolRecipe`）。
- 公开函数大驼峰，私有小驼峰。
- 包外函数加包名前缀注释：`// SearchPoolAccounts 按关键字 + provider + status 过滤`。

### 2.3 GORM 陷阱
- **不要给 bool 字段加 `default:true`**——seed 时 `false` 会被当 zero value 用 default 覆盖。本 fork 出过事故，见 ADR-0004。
- **新增字段要 `AutoMigrate`**：`model/main.go` 里把结构体加进 `Migrator().AutoMigrate(...)`。
- **删除字段不要直接 drop column**：先注释掉字段、保留 1-2 个版本，确认没线上数据要保后再 drop。

### 2.4 channel 写入必须用 `Insert()`
```go
// ❌ 不行 —— 不会写 abilities 表，路由命不中
model.DB.Create(ch)

// ✅ 必须
ch.Insert()
```
原因详见 [05-architecture/routing-abilities.md](../05-architecture/routing-abilities.md)。这是本 fork 出过的最大坑。

### 2.5 错误返回
- HTTP handler 用 `common.ApiError(c, err)` / `common.ApiErrorMsg(c, "...")`。
- service 函数 return error 时**带上下文**：`fmt.Errorf("acquire sms: %w", err)`，不要裸 return。
- 不要 panic（除非是程序 bug 而非业务异常），统一用 error。

### 2.6 日志
- 用 `common.SysLog` / `common.SysError`，不要 fmt.Println。
- 号池相关 log 一律前缀 `[pool-worker]` / `[pool-health]` / `[pool]`，方便 grep。
- 外部接口失败必须打 log（带 URL / 状态码 / body 前 200 字）。

### 2.7 测试
当前后端测试覆盖率较低，新代码**至少**写一条 happy path 单测：
```bash
go test ./service -run TestPoolWorker -v
```
跑全量：`go test ./... -count=1`。

## 3. React / Frontend

### 3.1 技术栈
- React 18 + Vite 5 + Bun 包管理
- UI 库：`@douyinfe/semi-ui`（Semi Design）
- 路由：`react-router-dom@6`
- 国际化：`react-i18next`（号池 fork 部分基本只用中文，简单字符串可不走 i18n）

### 3.2 文件位置
- 号池所有页 → `web/src/pages/Pool/`
- 共用组件 → `web/src/components/`
- 全局菜单注册 → `web/src/components/layout/SiderBar.jsx` 的 `PATH_MAP` + `items` 数组
- 路由注册 → `web/src/App.jsx`

### 3.3 表单
**所有 Modal 表单**都要用 Semi `Form`（不要原生 `<input>`），并支持回显：
```jsx
<Modal
  visible={visible}
  destroyOnClose            // ★ 关闭时销毁内部 state
  onCancel={() => setVisible(false)}
>
  <Form
    key={editing?.id}        // ★ id 变了强制重建
    initValues={editing}     // ★ 编辑模式回显
    onSubmit={handleSubmit}
  >
    <Form.Input field="name" label="名称" rules={[{required: true}]} />
    ...
  </Form>
</Modal>
```
不带 `destroyOnClose` + `key` 会出"编辑回显空白"的 bug，本 fork 出过事故。

### 3.4 API 调用
统一走 `axios` + `web/src/helpers/api.js` 里的封装。错误用 `Notification.error`。

### 3.5 样式
- 优先用 Tailwind 工具类（已配置）。
- Semi UI 颜色变量优先：`--semi-color-primary`、`--semi-color-bg-2` 等。
- 不要写 inline `style={{...}}` 大块样式，统一 className。

### 3.6 ESLint / Prettier
```bash
cd web && bun run lint:fix && bun run eslint:fix
```
提交前过一遍。

## 4. SQLite 注意

- 列名 `group` 是关键字。`glebarez/sqlite` 会把 GORM 字段 `Group` 翻译成列 `group_`，但**应用层用 `group`/`Group` 是对的**。手写 SQL 时要双引号或反引号包：`SELECT \`group\` FROM tokens`。
- `manual_mode` 是 bool，SQLite 存 `0/1`。判断用 `manual_mode = ?` 传 Go bool 即可。
- SQLite 不支持 `ALTER COLUMN`，删字段要重建表。所以**先想清楚再加字段**。

## 5. Commit Message

格式：
```
<type>(<scope>): <subject>

<body 可选>
```

| type | 用途 |
|---|---|
| `feat` | 新功能 |
| `fix` | bug 修 |
| `refactor` | 重构（无功能变化） |
| `docs` | 只改文档 |
| `chore` | 构建 / 依赖 / 脚本 |
| `style` | 格式化（无语义变化） |
| `test` | 新增/修测试 |

scope 用 `pool` / `pool-recipe` / `pool-runner` / `channel` / `web` / `i18n` 等。

例子：
```
feat(pool): add fireworks-ai recipe with default models
fix(pool): use ch.Insert() so abilities table is populated
docs(pool): add troubleshooting for "no available channel"
```

## 6. PR / 自审清单

合并前自己问一遍：
- [ ] 改的字段都进 `AutoMigrate` 了吗？
- [ ] 新加的 channel 都 `ch.Insert()` 了吗？
- [ ] 新加的 endpoint 加路由 + AdminAuth 了吗？
- [ ] 新加的 UI 表单 `destroyOnClose + key + initValues` 三件套都齐了吗？
- [ ] 默认值（Telegram Token / 5sim Key / Email Provider）放在 `SeedDefault*` 函数里了吗？
- [ ] 改了行为的话 [07-reference/changelog.md](../07-reference/changelog.md) 加一行了吗？
- [ ] 文档同步了吗？
