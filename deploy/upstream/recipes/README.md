# Recipes（注册脚本）

每个 platform 一个子目录：

```
recipes/
├── gemini/        # Google + AI Studio Free Key
├── claude/        # Anthropic + Claude Code OAuth（半自动）
└── ...
```

## Recipe 接口

每个 recipe 必须暴露 `flow.run(ctx: TaskCtx) -> None`：

```python
from orchestrator.state_machine import TaskCtx

async def run(ctx: TaskCtx) -> None:
    # 完整状态机：pending → email_ok → phone_ok → ... → imported
    ...
```

`TaskCtx` 提供：
- `transition(new_state)` 持久化状态切换
- `record_cost(item, usd)` 记录成本
- `save_account(**fields)` 注册成功后落库

## 目前实现

| Recipe | 状态 | 自动化程度 | 单号成本 |
|---|---|---|---|
| `gemini` | ✅ 完整 | 全自动 | $0.5-1 |
| `claude` | ⚠️ 半自动 | 绑卡环节人工 | $1-3 |
| `openai` | ❌ 不建议 | — | 不划算 |

## 调用

```bash
# 提交一个 Gemini 注册任务
docker compose -f docker-compose.upstream.yml exec orchestrator \
    python -m orchestrator.cli submit gemini

# 查看进度
docker compose -f docker-compose.upstream.yml exec orchestrator \
    python -m orchestrator.cli list
```

## 开发新 Recipe

1. 创建 `recipes/<name>/__init__.py` `recipes/<name>/flow.py`
2. 实现 `async def run(ctx)`，使用 `adapters/email`/`sms`/`captcha`/`browser`
3. 注册到 [`orchestrator/main.py::_load_recipe`](../orchestrator/main.py)
4. 加 README，列出失败场景与人工兜底步骤
