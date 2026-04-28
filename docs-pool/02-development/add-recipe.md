# 添加一个新 Recipe（新上游）

> 场景：你想往「号池管理 → 自动注册」里加一个新厂商，让管理员能在后台一键拿到操作步骤、必备材料、文档链接，并在录入 Key 后自动建好 new-api 渠道。

完成本文你会得到：
- 后台 Recipes 页多出一行你的新剧本
- 入队后弹出步骤 → 用户线下注册 → 录入 Key → 自动写 `pool_accounts` + 自动建 `channels` + 路由立即可用

整个流程**只改一个文件**：`new-api-src/model/pool_recipe.go`，函数 `buildDefaultRecipeSeeds()`。

---

## 1. 决定怎么走

回答 4 个问题：

1. **半自动还是全自动**？  
   - 半自动（默认 / 推荐）：`ManualMode=true`，UI 给步骤，用户线下完成 → 适合所有商业站点。
   - 全自动：`ManualMode=false` + 写一个 `RecipeRunner` 实现并 `RegisterRunner()`。本仓库目前**未内置任何商业站点全自动 Runner**——大厂全部 Cloudflare Turnstile + 设备指纹，自动化必败。除非你有真实住宅代理 + 接码服务 + 打码服务，否则别走这条路。
2. **Channel 类型是几号**？  
   - new-api 里每个上游协议有个固定 int，去 `web/src/pages/Channel/EditChannel.jsx` 或 `relay/channel/types.go` 找：常见的 1=OpenAI、14=Anthropic、24=Gemini、43=DeepSeek、40=SiliconFlow、20=OpenRouter、48=xAI、25=Moonshot、26=智谱、17=阿里、35=MiniMax、34=Cohere、42=Mistral、41=Vertex AI、57=Codex。
3. **BaseURL 是什么**？  
   - 上游 OpenAI 兼容协议的根地址，一般是文档第一行就有：`https://api.example.com` 或 `https://api.example.com/v1`。
4. **默认 Models 列表**？  
   - 用户能直接选用的模型清单（逗号分隔，不要空格）。这一项**很关键**：如果留空，自动建出的 channel 没 models，路由不到，要用户去「渠道管理 → 获取模型列表」补全。

---

## 2. 改一行代码

打开 `<REPO>/model/pool_recipe.go`，在 `buildDefaultRecipeSeeds()` return 数组里追加：

```go
{
    Key:                 "fireworks-ai",                    // 全表唯一 slug，不要带空格
    Name:                "Fireworks AI",                    // 后台显示名（可加 ⭐ 标记推荐）
    Provider:            "fireworks",                       // 同 Channel.Group / PoolAccount.Provider
    Version:             "1.0.0",
    ManualMode:          true,                              // 99% 情况下用 true
    Difficulty:          PoolRecipeDifficultyEasy,          // easy/medium/hard
    IPRequirement:       "any",                             // any / residential / specific_country
    AutomationCapability: "manual",                          // 信息字段，UI 给用户决策用
    ChannelType:         1,                                 // OpenAI 兼容用 1，否则按 new-api 表
    ChannelBaseURL:      "https://api.fireworks.ai/inference/v1",
    DefaultModels:       "accounts/fireworks/models/llama-v3p1-70b-instruct,accounts/fireworks/models/mixtral-8x22b-instruct",
    DocURL:              "https://fireworks.ai/account/api-keys",
    OutputFormat:        "fw_... (52 字符)",
    Description:         "✅ Fireworks 免费 $1 试用 + Llama/Mixtral 推理。Github/Google OAuth 登录即可，无需信用卡。",
    RequiredMaterials:   `["GitHub 或 Google 账号"]`,        // JSON 数组，前端按数组渲染
    ManualSteps: "1. 打开 https://fireworks.ai/login\n" +
                  "2. GitHub/Google 登录\n" +
                  "3. Account → API Keys → Create new key\n" +
                  "4. 复制 fw_... 回填",
},
```

字段全集（含解释）参见 `model/pool_recipe.go` 的 `PoolRecipe` 结构体注释。

---

## 3. 重启生效

```bash
cd <REPO>
(cd web && bun run build)
go build -o new-api-macos .
pkill -f new-api-macos; ./start.command
```

启动会跑 `SeedDefaultPoolRecipes()`：
- Recipe 不存在 → INSERT
- 已存在 → UPDATE 元数据字段（**不会**覆盖用户改过的 `Enabled` / `WebhookURL` / `ConfigJSON` / `Version`）

打开后台 → 号池管理 → 自动注册，应能看到你的新剧本。

---

## 4. 验证一遍闭环

1. 在 Recipes 页找到你的剧本，点「入队」。
2. 切到「任务历史」tab，应有新条 `manual_pending`。
3. 点「查看步骤」，确认 DocURL / Steps / Materials 渲染正常。
4. 模拟拿到 Key，点「录入结果」：
   ```
   pool_account_name: fireworks-test
   key_raw: fw_test123abc...
   ```
5. 进「上游账号」页，应看到新行；进 new-api 原生「渠道管理」，应看到 `pool-manual` tag 的渠道。
6. 用一个 default 组的 user token 调一次该模型：
   ```bash
   curl http://localhost:3000/v1/chat/completions \
     -H "Authorization: Bearer sk-USER-TOKEN" \
     -H "Content-Type: application/json" \
     -d '{
       "model": "accounts/fireworks/models/llama-v3p1-70b-instruct",
       "messages":[{"role":"user","content":"hi"}]
     }'
   ```
   - 如果上游返回正常 → 路由通了，恭喜 ✅
   - 如果 `No available channel for model X under group default`：检查 `Channel.Group` 是否含 `default,...`、`Channel.Models` 是否含目标模型、`abilities` 表是否有记录。详见 [05-architecture/routing-abilities.md](../05-architecture/routing-abilities.md)。

---

## 5. 进阶：如果你**真的**要做全自动 Runner

> 警告：开始之前请先读完 [05-architecture/decisions.md](../05-architecture/decisions.md) ADR-0002。决定继续后：

### 5.1 实现 RecipeRunner 接口

新增文件 `service/pool_runner_<recipe-key>.go`：

```go
package service

import (
    "context"
    "github.com/QuantumNous/new-api/model"
)

type fireworksRunner struct{}

func (r *fireworksRunner) Key() string         { return "fireworks-ai" }
func (r *fireworksRunner) Description() string { return "Fireworks 全自动注册（GitHub OAuth）" }

func (r *fireworksRunner) Run(ctx context.Context, recipe *model.PoolRecipe) (*RecipeResult, error) {
    // 1. 拿一次性邮箱
    inbox, err := AcquireEmail(ctx)
    if err != nil { return nil, err }
    defer ReleaseEmail(inbox)

    // 2. 自带 chromedp 起浏览器（住宅代理 + 真实 UA）
    // 3. 注册 / 登录 / 验证邮件 / 创建 Key
    // 4. 返回 RecipeResult

    return &RecipeResult{
        AccountName: "fireworks-" + inbox.Address,
        KeyRaw:      "fw_xxx...",
        Notes:       "auto by fireworks runner",
    }, nil
}

func init() {
    RegisterRunner(&fireworksRunner{})
}
```

### 5.2 把 Recipe 切到自动模式

回到 `pool_recipe.go` 把 `ManualMode: true` 改成 `false`，然后**用 SQL 强制覆盖一次**（因为 `upsertPoolRecipe` 的"用户改过"保护可能拦住）：
```sql
UPDATE pool_recipes SET manual_mode=0 WHERE `key`='fireworks-ai';
```

### 5.3 启动 worker

`service.StartPoolWorker` 已经在 `main.go` 里启动了；启动日志里会出现：
```
[pool-worker] runner registered: fireworks-ai
[pool-worker] started, max_concurrent=2, runners=[fireworks-ai]
```

### 5.4 入队 → 跟踪

```bash
# 入队（注意自动模式不能用 manual-result，要等 worker）
curl -X POST http://localhost:3000/api/pool/recipes/fireworks-ai/enqueue \
  -H "Authorization: Bearer ADMIN-TOKEN"
```

8 秒内 worker 会扫到，写日志 `[pool-worker] running job_id=N recipe=fireworks-ai`。完整流程见 [05-architecture/pool-pipeline.md](../05-architecture/pool-pipeline.md)。

---

## 6. 记得做的小事

- 改完 commit message 写：`feat(pool): add recipe <provider-name>`
- 在 [07-reference/changelog.md](../07-reference/changelog.md) 加一行
- 在 [04-usage/recipe-walkthrough.md](../04-usage/recipe-walkthrough.md) 给你的 Recipe 单开一节人工注册指引（如果你 Recipe 里的 ManualSteps 已经够清楚就不用）
- 如果 channel type 没用过，连带在 [05-architecture/data-model.md](../05-architecture/data-model.md) channel-type 速查表加一行
