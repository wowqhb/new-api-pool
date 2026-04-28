# 用户 API 文档 + SDK 适配

## 目标

- 给用户**5 分钟**就能跑通第一次调用
- 兼容主流 SDK（OpenAI / Anthropic / Google）—**改 base_url 即可**
- 错误码一目了然 → 减少 50% 工单
- 中英文双语

## 文件清单

- [`quickstart.md`](./quickstart.md) 5 分钟入门（含 Python / Node / curl）
- [`models.md`](./models.md) 模型清单 + 倍率 + 上下文长度
- [`error-codes.md`](./error-codes.md) 完整错误码字典
- [`sdk-compat.md`](./sdk-compat.md) 各 SDK / 客户端适配指南
- [`api-reference.md`](./api-reference.md) 完整 API 参考（含路径、参数、响应）
- [`postman/`](./postman/) Postman / Bruno 集合
- [`examples/`](./examples/) 各语言示例

## 文档站点选型

| 工具 | 推荐 | 备注 |
|---|---|---|
| **VitePress** | ★★★★★ | 静态站，速度快，本仓库默认 |
| Mintlify | ★★★★ | 商业、UI 美观，但要 lock-in |
| Docusaurus | ★★★ | React，灵活但复杂 |
| GitBook | ★★ | UI 老旧 |

我们用 **VitePress** 部署到 `docs.example.com`：

```bash
cd docs/site
pnpm install
pnpm run docs:build
# 部署到 Cloudflare Pages 或 Vercel
```

## 文档站结构

```
docs/site/
├── .vitepress/
│   └── config.mts        # 站点配置 + 侧边栏
├── index.md              # 首页
├── quickstart.md         # → 链 quickstart.md
├── guides/
│   ├── pricing.md
│   ├── rate-limits.md
│   ├── caching.md
│   └── streaming.md
├── api/
│   ├── chat.md
│   ├── messages.md
│   └── ...
├── models/
│   ├── openai.md
│   ├── anthropic.md
│   └── google.md
├── examples/
│   ├── python.md
│   ├── node.md
│   ├── go.md
│   └── ...
├── sdk/
│   └── compat.md         # → 链 sdk-compat.md
└── errors.md             # → 链 error-codes.md
```

## 维护原则

- 价格 / 模型清单**每周自动同步**（cron 从 new-api options 表取，渲染 markdown）
- 错误码**每次新增前必须更新文档**（CI 卡 PR）
- 中英双语**同步发布**（不允许只更新一种语言）
- 重大改动**邮件 + Telegram 频道**通知所有付费用户

## 多语言

最低支持中英双语；后续按用户分布加：
- 简体中文（默认）
- 繁体中文
- English
- 日本語（如有日韩用户）

## 嵌入用户后台

new-api 用户中心右上角加 "Docs" 按钮：
```html
<a href="https://docs.example.com" target="_blank">📖 文档</a>
```

并在 onboarding 流程引导新用户先看 quickstart。
