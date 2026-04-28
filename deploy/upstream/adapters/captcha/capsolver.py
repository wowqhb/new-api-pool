"""CapSolver 实现"""
from __future__ import annotations
import asyncio

import httpx
from loguru import logger
from tenacity import retry, stop_after_attempt, wait_exponential

from .base import CaptchaSolver
from orchestrator.settings import settings

API = "https://api.capsolver.com"


class CapSolver(CaptchaSolver):
    def __init__(self):
        self.api_key = settings.captcha_api_key
        if not self.api_key:
            raise ValueError("CAPTCHA_API_KEY 未配置")
        self._client = httpx.AsyncClient(timeout=120, base_url=API)

    @retry(stop=stop_after_attempt(3), wait=wait_exponential(min=2, max=10))
    async def _create_task(self, task: dict) -> str:
        r = await self._client.post(
            "/createTask",
            json={"clientKey": self.api_key, "task": task},
        )
        r.raise_for_status()
        data = r.json()
        if data.get("errorId") != 0:
            raise RuntimeError(f"capsolver createTask failed: {data}")
        return data["taskId"]

    async def _wait_task(self, task_id: str, timeout: int = 180) -> str:
        deadline = asyncio.get_event_loop().time() + timeout
        while asyncio.get_event_loop().time() < deadline:
            r = await self._client.post(
                "/getTaskResult",
                json={"clientKey": self.api_key, "taskId": task_id},
            )
            r.raise_for_status()
            data = r.json()
            status = data.get("status")
            if status == "ready":
                sol = data["solution"]
                return (
                    sol.get("gRecaptchaResponse")
                    or sol.get("token")
                    or sol.get("text")
                    or ""
                )
            if status == "failed":
                raise RuntimeError(f"capsolver failed: {data}")
            await asyncio.sleep(3)
        raise TimeoutError(f"captcha task {task_id} timeout")

    async def solve_recaptcha_v2(self, site_url: str, site_key: str, *, invisible: bool = False) -> str:
        task = {
            "type": "ReCaptchaV2TaskProxyLess",
            "websiteURL": site_url,
            "websiteKey": site_key,
            "isInvisible": invisible,
        }
        tid = await self._create_task(task)
        return await self._wait_task(tid)

    async def solve_recaptcha_v3(
        self, site_url: str, site_key: str, *, action: str = "verify", min_score: float = 0.7
    ) -> str:
        task = {
            "type": "ReCaptchaV3TaskProxyLess",
            "websiteURL": site_url,
            "websiteKey": site_key,
            "pageAction": action,
            "minScore": min_score,
        }
        tid = await self._create_task(task)
        return await self._wait_task(tid)

    async def solve_hcaptcha(self, site_url: str, site_key: str) -> str:
        task = {
            "type": "HCaptchaTaskProxyLess",
            "websiteURL": site_url,
            "websiteKey": site_key,
        }
        tid = await self._create_task(task)
        return await self._wait_task(tid)

    async def solve_turnstile(self, site_url: str, site_key: str, *, action: str | None = None) -> str:
        task = {
            "type": "AntiTurnstileTaskProxyLess",
            "websiteURL": site_url,
            "websiteKey": site_key,
        }
        if action:
            task["metadata"] = {"action": action}
        tid = await self._create_task(task)
        return await self._wait_task(tid)

    async def balance(self) -> float:
        r = await self._client.post("/getBalance", json={"clientKey": self.api_key})
        r.raise_for_status()
        return float(r.json().get("balance", 0))
