"""orchestrator/worker entrypoint

ROLE=orchestrator: 监控、定时调度、看板
ROLE=worker: 从 Redis Stream 取任务执行
"""
from __future__ import annotations
import asyncio
import json
import sys
from loguru import logger

from .settings import settings
from . import db, queue, state_machine
from budget.controller import BudgetController


async def main_worker():
    """Worker 循环：取任务 → 调用 recipe → 更新状态"""
    r = await queue.get_redis()
    await queue.ensure_group(r)
    consumer = settings.worker_id
    logger.info("worker {} starting", consumer)

    budget = BudgetController(settings)

    while True:
        try:
            if not await budget.check_can_proceed():
                logger.warning("budget gate closed, sleep 60s")
                await asyncio.sleep(60)
                continue

            msgs = await queue.claim(r, consumer, count=1, block_ms=5000)
            if not msgs:
                continue

            for msg_id, fields in msgs:
                task_id = int(fields["task_id"])
                recipe_name = fields["recipe"]
                payload = json.loads(fields.get("payload", "{}"))
                logger.info("worker {} got task #{} recipe={}", consumer, task_id, recipe_name)

                conn = await db.get_conn()
                try:
                    ctx = state_machine.TaskCtx(task_id, recipe_name, payload, conn)
                    recipe_mod = _load_recipe(recipe_name)
                    await recipe_mod.run(ctx)
                    await queue.ack(r, msg_id)
                except Exception as e:
                    logger.exception("task {} failed: {}", task_id, e)
                    try:
                        ctx = state_machine.TaskCtx(task_id, recipe_name, payload, conn)
                        await ctx.transition("failed", error=str(e)[:500])
                    finally:
                        await queue.to_dlq(r, msg_id, fields, str(e))
                finally:
                    await conn.close()
        except Exception:
            logger.exception("worker loop error")
            await asyncio.sleep(5)


def _load_recipe(name: str):
    if name == "gemini":
        from recipes.gemini import flow as mod
        return mod
    if name == "claude":
        from recipes.claude import flow as mod
        return mod
    raise ValueError(f"unknown recipe: {name}")


async def main_orchestrator():
    """Orchestrator: 监控 + 周期任务"""
    logger.info("orchestrator started")
    await db.init_db()
    while True:
        # TODO: 自动重提失败 / 健康巡检 / 看板
        await asyncio.sleep(60)


if __name__ == "__main__":
    logger.remove()
    logger.add(sys.stderr, level=settings.log_level)
    if settings.role == "worker":
        asyncio.run(main_worker())
    else:
        asyncio.run(main_orchestrator())
