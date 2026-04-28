"""每日 09:00 cron：推送 Telegram 日报"""
from __future__ import annotations
import asyncio
import sys

import httpx
from loguru import logger

from orchestrator.settings import settings
from .controller import daily_summary


async def main():
    text = await daily_summary(settings)
    print(text)
    if settings.telegram_bot_token and settings.telegram_chat_id:
        url = f"https://api.telegram.org/bot{settings.telegram_bot_token}/sendMessage"
        async with httpx.AsyncClient(timeout=10) as cli:
            r = await cli.post(
                url,
                json={
                    "chat_id": settings.telegram_chat_id,
                    "text": text,
                },
            )
            r.raise_for_status()
            logger.info("daily report pushed")


if __name__ == "__main__":
    logger.remove()
    logger.add(sys.stderr, level=settings.log_level)
    asyncio.run(main())
