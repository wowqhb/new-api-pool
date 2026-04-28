# 上游预算控制器

三层风控阀门：

| 阀门 | 维度 | 默认 | 触发动作 |
|---|---|---|---|
| 1 | 单日总花费 | $50 / 天 | 全员停线 30 分钟 |
| 2 | 单号成本 | $2 / 号 | 该号 abort |
| 3 | 失败率 | > 30% | 全员停线 30 分钟 |

阀门触发会自动发 Telegram 告警并写日志。

## 实现

- [`controller.py`](./controller.py) `BudgetController`
  - `check_can_proceed()` — Worker 每次取任务前调
  - `assert_account_can_start(ctx)` — Recipe 入口调
  - `_alert(text)` — Telegram 推送
- [`controller.py`](./controller.py) `daily_summary(settings)` — 每日 09:00 推送日报

## 数据模型

依赖 [`orchestrator/db.py`](../orchestrator/db.py) 的：
- `tasks(state)` 统计成功 / 失败
- `budget_ledger(cost_usd, created_at)` 累计花费

## 配置

[`/Users/kevin/AITRANSFER/new-api/deploy/upstream/.env.upstream.example`](../.env.upstream.example)：

```bash
DAILY_BUDGET_USD=50.0           # 阀门 1
MAX_COST_PER_ACCOUNT_USD=2.0    # 阀门 2
FAILURE_RATE_STOP=0.30          # 阀门 3
TELEGRAM_BOT_TOKEN=...
TELEGRAM_CHAT_ID=...
```

## 日报 Cron

```cron
# 每天 09:00 推送上游流水线日报
0 9 * * * docker compose -f docker-compose.upstream.yml exec orchestrator \
    python -m budget.daily_report
```

## 调试 / 演练

手动触发熔断：
```bash
# 注入一笔超预算的"幽灵成本"
docker compose exec upstream-postgres \
    psql -U upstream -d upstream -c \
    "INSERT INTO budget_ledger (item, cost_usd) VALUES ('drill', 60);"

# Worker 下次拉任务时会发现超预算并停线
docker compose logs upstream-worker-1 | tail -20
```

预期：日志出现 `⛔ 上游预算已达上限`，Telegram 收到告警。

## 与其它系统的协作

- **new-api 主服务**：上游预算控制**不影响**用户侧服务，只控制注册流水线
- **健康巡检**：`deploy/scripts/channel-health-check.sh` 是用户侧通道巡检，与本控制器独立
- **充值告警**：[`payment/balance-tracker.sh`](../payment/balance-tracker.sh) 跟踪卡余额，与流水线预算解耦
