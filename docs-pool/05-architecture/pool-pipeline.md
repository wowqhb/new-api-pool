# 注册管线（Pool Pipeline）

> 从"管理员点入队"到"可被路由的可用渠道"全过程。两条路：半自动（默认）和全自动（已腾出接口但当前无内置 Runner）。

## 1. 全景图

```
                  ┌──────────────────────────────────────────────────────┐
                  │   Admin UI: 「自动注册」页 → 选 Recipe → 点「入队」  │
                  └──────────────────────────────────────────────────────┘
                                          │
                                          ▼
              ┌─────── controller.EnqueuePoolRecipe (POST /api/pool/recipes/:key/enqueue) ──────┐
              │                                                                                     │
              │   - GetPoolRecipeByKey                                                              │
              │   - 校验 Enabled                                                                     │
              │   - 创建 PoolJob                                                                     │
              │     status = manual_pending（ManualMode=true）/ pending（false）                   │
              │   - 返回 { job_id }                                                                  │
              └────────────────────────────────────────────────────────────────────────────────────┘
                                          │
                                  ┌───────┴───────┐
                                  ▼               ▼
                       【半自动管线】          【全自动管线】
                       ManualMode = true       ManualMode = false
                                                       │
                                                       ▼
                                            service.StartPoolWorker (后台 8s 一扫)
                                                       │
                                  ┌───────────────────-┘
                                  ▼
                      service.dispatchOnce
                        SearchPoolJobs(status=pending, limit=20)
                        for each job:
                          GetPoolRecipeByKey
                          if recipe.ManualMode { skip }
                          GetRunner(key)
                          if nil { fail "未找到 Runner" }
                          抢 semaphore（默认 maxConc=2）
                          go runJob(...)

                                  ┌──────────────────────────────────┐
                                  │   service.runJob                 │
                                  │     job.UpdateStatus(running)   │
                                  │     ctx, cancel = WithTimeout(5min)
                                  │     RecipeRunner.Run(ctx, recipe)
                                  │     if err { fail; counter++ }   │
                                  │     if result.KeyRaw == "" { fail }
                                  └──────────────┬───────────────────┘
                                                 │ 成功
                                                 ▼
                       ★ 收尾流水线 ★（半自动也会跑同样的逻辑，从下面 controller.ManualSubmitJobResult 进入）

                              ┌────────────────────────────────────┐
                              │ 1) 写 PoolAccount                  │
                              │    name, provider, type=official, │
                              │    KeyMasked, BalanceUSD,          │
                              │    GroupName, Notes                │
                              └────────────────┬───────────────────┘
                                               │
                              ┌────────────────▼───────────────────┐
                              │ 2) 自动建 Channel（若 ChannelType>0）│
                              │    Type, Key=KeyRaw, Status=enabled│
                              │    Name, Group="default,<prov>",   │
                              │    Models=Recipe.DefaultModels,    │
                              │    Tag="pool-auto"/"pool-manual",  │
                              │    BaseURL=Recipe.ChannelBaseURL   │
                              │    ★ ch.Insert() 自动写 abilities ★│
                              └────────────────┬───────────────────┘
                                               │
                              ┌────────────────▼───────────────────┐
                              │ 3) PoolAccount.ChannelId = ch.Id   │
                              │    pool_account.Update()           │
                              └────────────────┬───────────────────┘
                                               │
                              ┌────────────────▼───────────────────┐
                              │ 4) Job → success                   │
                              │    result_json = { account_id,     │
                              │                    channel_id, by }│
                              │    Recipe.success_count ++         │
                              └────────────────────────────────────┘
```

## 2. 半自动入口（手动回填）

控制器：`controller/pool.go::ManualSubmitJobResult`，路由 `POST /api/pool/jobs/:id/manual-result`。

```jsonc
// Request body
{
  "pool_account_name": "gemini-personal-1",
  "key_raw": "AIza...",
  "balance_usd": 0,                    // 可选
  "expire_at": 0,                      // 可选 unix sec
  "notes": "由 root 手动回填"            // 可选
}
```

工作步骤跟全自动**完全一致**——共享上图"★ 收尾流水线 ★"。区别只是 KeyRaw 来源：
- 全自动：`RecipeRunner.Run()` 返回 `RecipeResult.KeyRaw`
- 半自动：`controller` 从 HTTP body 拿 `key_raw`

## 3. 全自动入口（worker 模式）

### 3.1 Worker 启动

`main.go` 启动时：
```go
if common.IsMasterNode {
    service.StartPoolHealthCron(context.Background())   // 巡检
    service.StartPoolWorker(context.Background())       // 注册 worker
}
```

`StartPoolWorker`（`service/pool_worker.go`）：
- `atomic CompareAndSwap` 保证只启一份
- 取 `PoolWorkerMaxConcurrent` 选项做信号量（默认 2）
- 启 goroutine：每 `8s` 扫一次 `pending` 状态的 PoolJob

### 3.2 Runner 注册

每个全自动 Recipe 必须有对应 `RecipeRunner`：

```go
type RecipeRunner interface {
    Key() string
    Description() string
    Run(ctx context.Context, recipe *model.PoolRecipe) (*RecipeResult, error)
}
```

注册：
```go
func init() {
    RegisterRunner(&fireworksRunner{})
}
```

> 本仓库 v2.0 起**未内置任何商业站点 Runner**。具体见 [decisions.md](./decisions.md) ADR-0002。

### 3.3 dispatchOnce

```go
jobs := SearchPoolJobs("", "pending", 0, 20)
for each job:
    recipe := GetPoolRecipeByKey(job.RecipeKey)
    if recipe.ManualMode: continue        // 半自动不该出现在 pending
    runner := GetRunner(recipe.Key)
    if runner == nil:
        job.fail("未找到 Runner: ...")
        recipe.failure_count++
        continue
    select {
    case workerSemaphore <- struct{}{}:    // 抢 slot
    default: continue                      // 满了等下轮
    }
    go runJob(ctx, job, recipe, runner)
```

### 3.4 runJob

```go
job.UpdateStatus(running)
jobCtx, cancel := WithTimeout(ctx, 5*time.Minute)   // 单 job 超时
defer cancel()

result, err := runner.Run(jobCtx, recipe)
if err:
    job.fail(err.Error())
    return
if result == nil || result.KeyRaw == "":
    job.fail("runner 返回空 Key")
    return

// ★ 收尾流水线
acc := &PoolAccount{... KeyMasked: Mask(result.KeyRaw)}
acc.Insert()
if recipe.ChannelType > 0:
    ch := &Channel{... Key: result.KeyRaw, Models: recipe.DefaultModels, Tag: "pool-auto"}
    ch.Insert()                            // ← AddAbilities() 自动跟随
    acc.ChannelId = ch.Id
    acc.Update()
job.success({pool_account_id, channel_id, by:"worker"})
recipe.success_count++
```

## 4. 全自动 Runner 该做的事

> 仅参考；本仓库目前不内置。

```go
func (r *fireworksRunner) Run(ctx context.Context, recipe *model.PoolRecipe) (*RecipeResult, error) {
    // 1) 拿一次性邮箱
    inbox, err := AcquireEmail(ctx)        // service/pool_email.go
    if err != nil { return nil, err }
    defer ReleaseEmail(inbox)

    // 2) 拿手机号 / OTP（若需）
    sms, err := AcquireSms(ctx, recipe)    // service/pool_sms.go
    if err == nil { defer sms.Release() }

    // 3) 启 chromedp 自带 UA + 代理
    //    填注册表单 → 点 register → 等验证邮件 → 点磁链 / 验证码
    //    到 dashboard → 创建 API Key → 提取明文

    // 4) 返回
    return &RecipeResult{
        AccountName: "fireworks-" + inbox.Address,
        KeyRaw:      "fw_xxx...",
        BalanceUSD:  1.0,                  // 上游赠送 $1
        Notes:       "auto by fireworks-runner v1",
    }, nil
}
```

实际**不可行**的点：Cloudflare Turnstile 检测 `isTrusted` 属性，chromedp 模拟点击在 95% 站点会被识破。本 fork v2 删除了所有商业站点 Runner，详见 ADR-0002。

## 5. EmailProvider 抽象

`service/pool_email.go`：

```go
type EmailProvider interface {
    Name() string
    Acquire(ctx context.Context) (*Inbox, error)
    Wait(ctx context.Context, inbox *Inbox, predicate func(*Mail) bool, timeout time.Duration) (*Mail, error)
    Release(inbox *Inbox)
}
```

实现：
- `mailtmProvider`（`pool_mailtm.go`）—— 默认；mail.tm，免费，10 分钟过期
- `guerrillaProvider` —— 备用，更长 token 但 IP 限制
- `1secmailProvider` —— 备用，简单 polling

`AcquireEmail()` 按 `PoolEmailProvider` 选项选 → 失败 fallback 顺序：mailtm > guerrilla > 1secmail。

## 6. SmsProvider 抽象

`service/pool_sms.go`：

```go
type SmsProvider interface {
    Name() string
    Balance() (float64, error)
    Acquire(ctx context.Context, country, operator, product string) (*SmsSession, error)
}

type SmsSession struct {
    Number   string
    OrderId  string
    WaitOTP(ctx context.Context, timeout time.Duration) (string, error)
    Release(success bool) error
}
```

实现：
- `fivesimProvider` —— 默认；用 Bearer JWT 调 5sim.net REST
- `smsActivateProvider` —— 备用；旧版 API Key
- `mockProvider` —— 仅本地测试

启动时 `logAutomationSelfCheck()` 会拉一次余额并写日志：
```
[pool-worker] selfcheck: SMS provider 5sim 余额 = 12.345 RUB
[pool-worker] selfcheck: Email provider = mailtm（fallback 顺序: mailtm > guerrilla > 1secmail）
```

## 7. 健康巡检管线

`service/pool_health.go::StartPoolHealthCron`：
- 每 5 分钟跑一次 `checkOnce()`（启动 30 秒后第一次）
- 检测多个规则，命中 → 写 `pool_alert_history` + Telegram 推送

巡检规则（当前内置）：
| rule_key | 触发条件 |
|---|---|
| `channel_down` | channel 最近 30 个请求失败率 > 50% 且样本 ≥ 10 |
| `channel_disabled` | new-api 自动健康检查把 channel 置为 disabled |
| `balance_low` | pool_account.balance_usd < 阈值（默认 5） |
| `pool_account_expire` | expire_at < now + 7d |
| `system_health` | DB ping 失败 / Redis 失联 |

详细：[06-operations/monitoring-alerts.md](../06-operations/monitoring-alerts.md)。

## 8. 异常情况

| 异常 | 行为 |
|---|---|
| Worker panic | 用 `defer recover()` 捕获 → job.fail("worker panic: ...") |
| 单 job 超时 5 分钟 | runner Run() ctx Done → 期望 runner 立即返回；上层超时直接计 fail |
| Runner 返回空 KeyRaw | job.fail("runner 返回空 Key") |
| Insert PoolAccount 失败 | job.fail("runner 成功但 pool_accounts 写入失败: ...") |
| Insert Channel 失败 | 仅打日志，PoolAccount 已创建，job 仍 success；ChannelId=0 |
| 多节点重复 dispatch | 单进程信号量保证；多节点必须只一个 master 跑 worker |

## 9. 关键文件对照表

| 文件 | 行数 | 责任 |
|---|---|---|
| `controller/pool.go` | 1244 | HTTP handler 全部，含半自动收尾流水线 |
| `service/pool_worker.go` | 286 | dispatchOnce + runJob + selfcheck |
| `service/pool_runners.go` | 74 | RecipeRunner 接口 + 注册表 |
| `service/pool_email.go` | 410 | EmailProvider 抽象 + fallback |
| `service/pool_mailtm.go` | 262 | mail.tm 客户端 |
| `service/pool_sms.go` | 352 | SmsProvider 抽象 + 5sim/sms-activate/mock |
| `service/pool_health.go` | 293 | 巡检 cron + Telegram |
| `model/pool_account.go` | 134 | PoolAccount CRUD |
| `model/pool_recipe.go` | 551 | PoolRecipe + PoolJob + Seed |
| `model/pool_alert.go` | 68 | PoolAlertHistory |
