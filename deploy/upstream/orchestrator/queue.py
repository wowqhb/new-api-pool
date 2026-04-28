"""Redis Streams 队列"""
from __future__ import annotations
import json
import redis.asyncio as aredis
from .settings import settings

STREAM = "upstream:tasks"
GROUP = "workers"
DLQ = "upstream:dlq"


async def get_redis() -> aredis.Redis:
    return aredis.from_url(settings.redis_url, decode_responses=True)


async def ensure_group(r: aredis.Redis):
    try:
        await r.xgroup_create(STREAM, GROUP, id="$", mkstream=True)
    except Exception as e:
        if "BUSYGROUP" not in str(e):
            raise


async def submit_task(r: aredis.Redis, task_id: int, recipe: str, payload: dict):
    await r.xadd(STREAM, {
        "task_id": str(task_id),
        "recipe": recipe,
        "payload": json.dumps(payload, ensure_ascii=False),
    })


async def claim(r: aredis.Redis, consumer: str, count: int = 1, block_ms: int = 5000):
    res = await r.xreadgroup(GROUP, consumer, {STREAM: ">"}, count=count, block=block_ms)
    if not res:
        return []
    out = []
    for _, msgs in res:
        for msg_id, fields in msgs:
            out.append((msg_id, fields))
    return out


async def ack(r: aredis.Redis, msg_id: str):
    await r.xack(STREAM, GROUP, msg_id)


async def to_dlq(r: aredis.Redis, msg_id: str, fields: dict, error: str):
    await r.xadd(DLQ, {**fields, "error": error[:500], "from_msg": msg_id})
    await ack(r, msg_id)
