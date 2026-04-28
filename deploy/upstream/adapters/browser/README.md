# Browser Adapter（Camoufox + 住宅代理）

> 反检测浏览器最强候选目前是 [Camoufox](https://github.com/daijro/camoufox)（Firefox fork，原生 patch C++ 层指纹）。

## 关键能力

- 每号一套**固定指纹**（Canvas / WebGL / Audio / Fonts / Locale / TZ / Resolution / UA），存入 Postgres `fingerprints` 表
- 每号绑定一条**住宅代理 sticky session**（同 IP 至少绑定 24 小时）
- 自动注入 cookies / localStorage（恢复登录态）
- 自动录制操作录像（Playwright `record_video`）入 MinIO

## 技术栈

| 模块 | 选型 |
|---|---|
| 浏览器 | Camoufox (Firefox fork) |
| 自动化 | Playwright Async API |
| 代理 | 住宅 IP（IPRoyal / 922S5 / BrightData） |
| 指纹库 | 自维护 Postgres `fingerprints` |

## 使用

```python
from adapters.browser import open_session

async with open_session(account_id=42) as page:
    await page.goto("https://accounts.google.com")
    # ... 注册流程
```

`open_session` 内部：
1. 从 Postgres 查/生成 fingerprint
2. 从代理池借出 sticky session
3. 启 Camoufox + 注入指纹
4. 加载 cookies（如有）
5. 退出时保存 cookies + 录像

## 反检测要点

- **永远不用 Chrome/Chromium**（CDP 协议本身就是检测信号）
- **永远不用同一 IP 注两个号**
- **永远不用机房 IP**
- 操作时模拟真实人类节奏（鼠标贝塞尔曲线、随机停顿 200-1500ms、错误打字回退）
- 不要在很短的时间内（<1 分钟）完成"打开页面 → 填表 → 提交"

## 代理选型

| 提供商 | 价格 | 推荐度 |
|---|---|---|
| BrightData | $15/GB | 顶级，但贵 |
| IPRoyal | $7/GB | 性价比 |
| 922S5 | $0.04/IP | 按 IP 计费，注册便宜 |
| PIA S5 | $0.03/IP | 同上 |

> ⚠️ 不要尝试 free proxy 或共享代理，IP 黑名单率 99%。
