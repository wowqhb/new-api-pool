"""命令行：init-db / submit / list / cancel / retry"""
from __future__ import annotations
import asyncio
import json
import typer

from .settings import settings
from . import db, queue, state_machine

app = typer.Typer(no_args_is_help=True)


@app.command("init-db")
def cmd_init_db():
    """建表 + 索引"""
    asyncio.run(db.init_db())
    typer.echo("[+] db initialized")


@app.command("submit")
def cmd_submit(
    recipe: str = typer.Option(..., help="gemini / claude"),
    count: int = typer.Option(1, help="提交几个任务"),
    payload_json: str = typer.Option("{}", help="payload JSON"),
):
    """批量提交注册任务"""
    asyncio.run(_submit(recipe, count, json.loads(payload_json)))


async def _submit(recipe: str, count: int, payload: dict):
    r = await queue.get_redis()
    await queue.ensure_group(r)
    conn = await db.get_conn()
    try:
        for i in range(count):
            tid = await state_machine.create_task(conn, recipe, payload)
            await queue.submit_task(r, tid, recipe, payload)
            typer.echo(f"  [+] task #{tid} submitted")
    finally:
        await conn.close()


@app.command("list")
def cmd_list(state: str = "", limit: int = 20):
    asyncio.run(_list(state, limit))


async def _list(state: str, limit: int):
    conn = await db.get_conn()
    try:
        sql = "SELECT id, recipe, state, attempt, cost_usd, started_at, error FROM tasks"
        params = []
        if state:
            sql += " WHERE state = %s"
            params.append(state)
        sql += " ORDER BY id DESC LIMIT %s"
        params.append(limit)
        async with conn.cursor() as cur:
            await cur.execute(sql, params)
            rows = await cur.fetchall()
        for r in rows:
            typer.echo(f"#{r[0]:5} {r[1]:8} {r[2]:14} attempt={r[3]} ${r[4]:.2f} {r[5]} err={r[6] or '-'}")
    finally:
        await conn.close()


@app.command("retry")
def cmd_retry(task_id: int):
    """把 failed 任务重新入队"""
    asyncio.run(_retry(task_id))


async def _retry(task_id: int):
    conn = await db.get_conn()
    r = await queue.get_redis()
    try:
        async with conn.cursor() as cur:
            await cur.execute(
                "UPDATE tasks SET state='pending', attempt=attempt+1, error=NULL "
                "WHERE id = %s RETURNING recipe, payload::text", (task_id,)
            )
            row = await cur.fetchone()
        await conn.commit()
        if not row:
            typer.echo(f"[!] task {task_id} not found")
            return
        recipe, payload = row[0], json.loads(row[1] or "{}")
        await queue.submit_task(r, task_id, recipe, payload)
        typer.echo(f"[+] re-submitted task #{task_id}")
    finally:
        await conn.close()


if __name__ == "__main__":
    app()
