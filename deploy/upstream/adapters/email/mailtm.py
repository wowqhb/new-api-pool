"""mail.tm 临时邮箱（兜底，**注意大部分平台已封**）"""
from __future__ import annotations
import asyncio
import re
import secrets
import string

import httpx
from loguru import logger

from .base import EmailProvider, EmailAddress

API = "https://api.mail.tm"


def _rand(n: int = 10) -> str:
    return "".join(secrets.choice(string.ascii_lowercase + string.digits) for _ in range(n))


class MailTm(EmailProvider):
    def __init__(self):
        self._client = httpx.AsyncClient(timeout=30, base_url=API)
        self._sessions: dict[str, dict] = {}

    async def _get_domain(self) -> str:
        r = await self._client.get("/domains")
        r.raise_for_status()
        return r.json()["hydra:member"][0]["domain"]

    async def request_address(self, prefix: str | None = None) -> EmailAddress:
        domain = await self._get_domain()
        addr = f"{prefix or 'reg'}{_rand(8)}@{domain}"
        password = _rand(16)
        await self._client.post("/accounts", json={"address": addr, "password": password})
        token_resp = await self._client.post("/token", json={"address": addr, "password": password})
        token = token_resp.json()["token"]
        self._sessions[addr] = {"token": token, "password": password}
        return EmailAddress(address=addr, provider="mailtm", metadata={"password": password})

    async def wait_for(self, address: str, *, regex: str, timeout: int = 120, since: str | None = None) -> str:
        sess = self._sessions.get(address)
        if not sess:
            raise ValueError(f"address {address} not requested by us")
        rx = re.compile(regex, re.MULTILINE | re.IGNORECASE)
        deadline = asyncio.get_event_loop().time() + timeout
        headers = {"Authorization": f"Bearer {sess['token']}"}
        while asyncio.get_event_loop().time() < deadline:
            r = await self._client.get("/messages", headers=headers)
            for m in r.json().get("hydra:member", []):
                detail = await self._client.get(f"/messages/{m['id']}", headers=headers)
                body = detail.json().get("text") or detail.json().get("html", [""])[0]
                match = rx.search(body)
                if match:
                    return match.group(1)
            await asyncio.sleep(5)
        raise TimeoutError(f"no matching mail for {address} within {timeout}s")

    async def release(self, address: str) -> None:
        sess = self._sessions.pop(address, None)
        if sess:
            try:
                await self._client.delete(f"/accounts/me", headers={"Authorization": f"Bearer {sess['token']}"})
            except Exception as e:
                logger.warning("release {} failed: {}", address, e)

    @property
    def cost_per_email(self) -> float:
        return 0.0
