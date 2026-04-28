"""定时刷新 Claude OAuth access token

使用：cron 每 4 小时跑一次：
    0 */4 * * * docker compose -f docker-compose.upstream.yml exec orchestrator \
        python -m recipes.claude.oauth_refresh

逻辑：
1. 查 accounts 表所有 recipe='claude' & status='active' 的号
2. 用 refresh_token 调 Anthropic OAuth refresh endpoint
3. 更新本地（DB+Vault）
4. 调 new-api PUT /api/channel/{id} 更新 key
"""
from __future__ import annotations
import asyncio
import sys
from datetime import datetime, timezone

import httpx
import psycopg
from loguru import logger

from orchestrator.settings import settings


REFRESH_URL = "https://console.anthropic.com/v1/oauth/token"


async def main():
    conn = await psycopg.AsyncConnection.connect(settings.pg_dsn, autocommit=True)
    try:
        async with conn.cursor() as cur:
            await cur.execute(
                "SELECT id, email, access_token_vault, refresh_token_vault, new_api_channel_id "
                "FROM accounts WHERE recipe='claude' AND status='active'"
            )
            rows = await cur.fetchall()

        success = fail = 0
        async with httpx.AsyncClient(timeout=30) as cli:
            for acct_id, email, _at, refresh, chan_id in rows:
                if not refresh:
                    logger.warning("acct {} email={} 没有 refresh_token，跳过", acct_id, email)
                    continue
                try:
                    new_at, new_rt = await _refresh_one(cli, refresh)
                    async with conn.cursor() as cur:
                        await cur.execute(
                            "UPDATE accounts SET access_token_vault=%s, refresh_token_vault=%s, "
                            "last_used_at=NOW() WHERE id=%s",
                            (new_at, new_rt, acct_id),
                        )
                    if chan_id and settings.new_api_base:
                        await _update_channel(cli, chan_id, new_at, new_rt)
                    success += 1
                except Exception as e:
                    logger.exception("acct {} refresh failed: {}", acct_id, e)
                    fail += 1
                    async with conn.cursor() as cur:
                        await cur.execute(
                            "UPDATE accounts SET health_score = GREATEST(0, health_score-10) WHERE id=%s",
                            (acct_id,),
                        )
        logger.info("[refresh] success={} fail={} total={} at {}",
                    success, fail, len(rows), datetime.now(timezone.utc).isoformat())
    finally:
        await conn.close()


async def _refresh_one(cli: httpx.AsyncClient, refresh_token: str) -> tuple[str, str]:
    r = await cli.post(
        REFRESH_URL,
        json={
            "grant_type": "refresh_token",
            "refresh_token": refresh_token,
            "client_id": "9d1c250a-e61b-44d9-88ed-5944d1962f5e",  # Anthropic CLI 公开 client_id
        },
    )
    r.raise_for_status()
    data = r.json()
    return data["access_token"], data.get("refresh_token", refresh_token)


async def _update_channel(cli: httpx.AsyncClient, channel_id: int, access_token: str, refresh_token: str):
    base = settings.new_api_base.rstrip("/")
    headers = {"Authorization": f"Bearer {settings.new_api_admin_token}"}
    r = await cli.get(f"{base}/api/channel/{channel_id}", headers=headers)
    r.raise_for_status()
    chan = r.json().get("data", {})
    chan["key"] = access_token
    chan["other"] = refresh_token
    r = await cli.put(f"{base}/api/channel/", headers=headers, json=chan)
    r.raise_for_status()


if __name__ == "__main__":
    logger.remove()
    logger.add(sys.stderr, level=settings.log_level)
    asyncio.run(main())
