"""状态机 + 持久化"""
from __future__ import annotations
import json
from typing import Any
from datetime import datetime
import psycopg
from loguru import logger

STATES = (
    "pending",
    "email_ok",
    "phone_ok",
    "captcha_ok",
    "registered",
    "activated",
    "key_extracted",
    "imported",
    "done",
    "failed",
)


class TaskCtx:
    """单个任务的上下文，贯穿一次 Recipe 执行"""

    def __init__(self, task_id: int, recipe: str, payload: dict, conn: psycopg.AsyncConnection):
        self.id = task_id
        self.recipe = recipe
        self.payload = payload
        self.conn = conn
        self.email: str | None = None
        self.phone: str | None = None
        self.proxy: str | None = None
        self.fingerprint_id: int | None = None
        self.cost: float = 0.0
        self.account_id: int | None = None

    async def transition(self, new_state: str, error: str | None = None):
        async with self.conn.cursor() as cur:
            await cur.execute(
                """UPDATE tasks SET state = %s, last_step_at = NOW(), error = %s,
                   email = COALESCE(%s, email), phone = COALESCE(%s, phone),
                   proxy = COALESCE(%s, proxy), fingerprint_id = COALESCE(%s, fingerprint_id),
                   cost_usd = %s WHERE id = %s""",
                (new_state, error, self.email, self.phone, self.proxy,
                 self.fingerprint_id, self.cost, self.id),
            )
            if new_state in ("done", "failed"):
                await cur.execute(
                    "UPDATE tasks SET finished_at = NOW() WHERE id = %s", (self.id,)
                )
        await self.conn.commit()
        logger.info("task #{} → {}", self.id, new_state)

    async def record_cost(self, item: str, usd: float):
        self.cost += usd
        async with self.conn.cursor() as cur:
            await cur.execute(
                "INSERT INTO budget_ledger (task_id, item, cost_usd) VALUES (%s, %s, %s)",
                (self.id, item, usd),
            )
        await self.conn.commit()

    async def save_account(self, **fields):
        async with self.conn.cursor() as cur:
            cols = ["task_id", "recipe", "email"]
            vals = [self.id, self.recipe, fields.get("email", self.email)]
            for k, v in fields.items():
                if k in cols:
                    continue
                cols.append(k)
                vals.append(v)
            placeholders = ", ".join(["%s"] * len(vals))
            await cur.execute(
                f"INSERT INTO accounts ({', '.join(cols)}) VALUES ({placeholders}) RETURNING id",
                vals,
            )
            row = await cur.fetchone()
            self.account_id = row[0]
        await self.conn.commit()


async def load_task(conn: psycopg.AsyncConnection, task_id: int) -> dict | None:
    async with conn.cursor() as cur:
        await cur.execute(
            "SELECT id, recipe, state, payload::text FROM tasks WHERE id = %s", (task_id,)
        )
        row = await cur.fetchone()
        if not row:
            return None
        return {
            "id": row[0],
            "recipe": row[1],
            "state": row[2],
            "payload": json.loads(row[3]) if row[3] else {},
        }


async def create_task(conn: psycopg.AsyncConnection, recipe: str, payload: dict) -> int:
    async with conn.cursor() as cur:
        await cur.execute(
            "INSERT INTO tasks (recipe, payload) VALUES (%s, %s) RETURNING id",
            (recipe, json.dumps(payload)),
        )
        row = await cur.fetchone()
    await conn.commit()
    return row[0]
