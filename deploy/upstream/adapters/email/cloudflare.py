"""Cloudflare Email Routing catch-all + IMAP 收信

工作原理：
- 自有域名 mailbox.example.com 在 CF 启用 catch-all → 转发到真实邮箱 inbox@yourrealmail.com
- 我们生成 <random>@mailbox.example.com 给上游平台
- IMAP 连真实邮箱拉信，匹配 to=<random>@mailbox.example.com
"""
from __future__ import annotations
import asyncio
import re
import secrets
import string
from datetime import datetime, timedelta, timezone

from imap_tools import MailBox, AND, A
from loguru import logger

from .base import EmailProvider, EmailAddress
from orchestrator.settings import settings


def _rand(n: int = 12) -> str:
    return "".join(secrets.choice(string.ascii_lowercase + string.digits) for _ in range(n))


class CloudflareCatchall(EmailProvider):
    def __init__(self):
        self.domain = settings.cf_email_domain
        self.imap_host = settings.imap_host
        self.imap_user = settings.imap_user
        self.imap_pass = settings.imap_pass
        self.imap_port = settings.imap_port
        if not (self.domain and self.imap_host and self.imap_user and self.imap_pass):
            raise ValueError("CF Email + IMAP 凭证未配置")

    async def request_address(self, prefix: str | None = None) -> EmailAddress:
        local = f"{prefix or 'reg'}-{_rand(8)}"
        addr = f"{local}@{self.domain}"
        return EmailAddress(address=addr, provider="cloudflare-catchall", metadata={"local": local})

    async def wait_for(self, address: str, *, regex: str, timeout: int = 120, since: str | None = None) -> str:
        logger.info("waiting mail to {} (timeout={}s)", address, timeout)
        deadline = asyncio.get_event_loop().time() + timeout
        rx = re.compile(regex, re.MULTILINE | re.IGNORECASE)
        since_dt = datetime.now(timezone.utc) - timedelta(minutes=2)

        while asyncio.get_event_loop().time() < deadline:
            try:
                code = await asyncio.to_thread(self._poll_once, address, rx, since_dt)
                if code:
                    return code
            except Exception as e:
                logger.warning("imap poll failed: {}", e)
            await asyncio.sleep(5)
        raise TimeoutError(f"no matching mail for {address} within {timeout}s")

    def _poll_once(self, address: str, rx: re.Pattern, since: datetime) -> str | None:
        with MailBox(self.imap_host, port=self.imap_port).login(
            self.imap_user, self.imap_pass, initial_folder="INBOX"
        ) as mbox:
            criteria = AND(date_gte=since.date(), to=address)
            for msg in mbox.fetch(criteria, mark_seen=False, reverse=True, limit=20):
                # to 字段在 catch-all 转发后变成主邮箱，原始地址在 X-Forwarded-To / Delivered-To
                target = (
                    " ".join(msg.headers.get("delivered-to", []))
                    + " ".join(msg.headers.get("x-forwarded-to", []))
                    + (msg.to_values[0].email if msg.to_values else "")
                )
                if address.lower() not in target.lower():
                    continue
                m = rx.search(msg.text or "") or rx.search(msg.html or "")
                if m:
                    return m.group(1)
        return None

    async def release(self, address: str) -> None:
        # CF catch-all 不需要释放，地址永久可用
        pass

    @property
    def cost_per_email(self) -> float:
        return 0.0
