# Orchestrator

## 角色

- `ROLE=orchestrator`：单实例，做监控 / cron / 自动重试 / 看板
- `ROLE=worker`：可水平扩展，从 Redis Stream 拿任务执行 Recipe

## 状态机

```
pending → email_ok → phone_ok → captcha_ok → registered → activated → key_extracted → imported → done
                                                                                             ↑
                                                                                          failed
```

每步在 `tasks` 表持久化，失败保留所有上下文（email / proxy / fingerprint_id / cost / error）供人工排查。

## 重试与恢复

- worker 异常崩溃：Redis Stream 的 pending 消息超时未 ack 会被 reclaim
- 任务失败：进 DLQ，人工排查后用 `cli retry <id>` 重新入队
- 半成功：任务 state 字段记录到哪一步了，重启时 recipe 应从该步继续（recipe 实现要 idempotent）

## 数据表

- `tasks`：注册任务全生命周期
- `accounts`：成功注册产生的账号
- `fingerprints`：每号一套指纹（cookies / UA / canvas seed）
- `budget_ledger`：每笔成本明细

## CLI

```bash
docker exec upstream-orchestrator python -m orchestrator.cli init-db
docker exec upstream-orchestrator python -m orchestrator.cli submit --recipe gemini --count 5
docker exec upstream-orchestrator python -m orchestrator.cli list
docker exec upstream-orchestrator python -m orchestrator.cli list --state failed
docker exec upstream-orchestrator python -m orchestrator.cli retry 42
```

## 编写新的 Recipe

参考 `recipes/gemini/flow.py`，约定：

```python
async def run(ctx: TaskCtx):
    """从 ctx.state 继续，每步成功后 ctx.transition(...)"""
    if ctx.state == 'pending':
        await step_email(ctx)
        await ctx.transition('email_ok')
    if ctx.state in ('pending', 'email_ok'):
        await step_phone(ctx)
        await ctx.transition('phone_ok')
    # ...
```

## 监控

每个 worker 暴露 Prometheus `/metrics` 在 9090 端口：
- `upstream_tasks_total{state,recipe}`
- `upstream_step_seconds{step,recipe}`
- `upstream_cost_usd_total{item}`
- `upstream_workers_busy`

加到主 Prometheus（注意网络打通 / federation）。
