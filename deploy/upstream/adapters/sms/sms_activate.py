"""sms-activate.io / 5sim 兼容（5sim API 接近）"""
from __future__ import annotations
import asyncio

import httpx
from loguru import logger

from .base import SMSProvider, SMSOrder
from orchestrator.settings import settings

API = "https://api.sms-activate.io/stubs/handler_api.php"


class SMSActivate(SMSProvider):
    def __init__(self):
        self.api_key = settings.sms_api_key
        if not self.api_key:
            raise ValueError("SMS_API_KEY 未配置")
        self._client = httpx.AsyncClient(timeout=30)

    async def _call(self, action: str, **params) -> str:
        params.update(api_key=self.api_key, action=action)
        r = await self._client.get(API, params=params)
        r.raise_for_status()
        return r.text.strip()

    async def request_phone(self, service: str, country: str | None = None) -> SMSOrder:
        country = country or settings.sms_default_country
        # service 代码：go (Google) / ot (any) / tg (telegram) / wa (whatsapp)
        for attempt in range(5):
            text = await self._call("getNumber", service=service, country=country)
            if text.startswith("ACCESS_NUMBER:"):
                _, oid, phone = text.split(":")
                # 价格通过 getPrices 单独查
                price_text = await self._call("getPrices", service=service, country=country)
                cost = 0.0
                try:
                    import json as _json
                    p = _json.loads(price_text).get(country, {}).get(service, {})
                    if isinstance(p, dict):
                        cost = float(list(p.values())[0])
                    elif isinstance(p, (int, float)):
                        cost = float(p)
                except Exception:
                    pass
                return SMSOrder(id=oid, phone="+" + phone, country=country, service=service, cost_usd=cost)
            if text in ("NO_NUMBERS", "NO_BALANCE"):
                logger.warning("sms request: {}", text)
                if text == "NO_BALANCE":
                    raise RuntimeError("SMS provider out of balance")
                await asyncio.sleep(5)
                continue
            await asyncio.sleep(2)
        raise RuntimeError(f"failed to get sms number for {service}/{country}")

    async def wait_for(self, order_id: str, timeout: int = 300) -> str:
        # 通知方进入"等待短信"状态
        await self._call("setStatus", id=order_id, status=1)
        deadline = asyncio.get_event_loop().time() + timeout
        while asyncio.get_event_loop().time() < deadline:
            text = await self._call("getStatus", id=order_id)
            if text.startswith("STATUS_OK:"):
                return text.split(":", 1)[1]
            if text == "STATUS_CANCEL":
                raise RuntimeError("sms cancelled by provider")
            await asyncio.sleep(5)
        # 超时让平台退款
        await self._call("setStatus", id=order_id, status=8)
        raise TimeoutError(f"sms timeout for order {order_id}")

    async def release(self, order_id: str, success: bool = True) -> None:
        # status=6: complete (成功) / status=8: cancel + refund
        await self._call("setStatus", id=order_id, status=6 if success else 8)

    async def balance(self) -> float:
        text = await self._call("getBalance")
        if text.startswith("ACCESS_BALANCE:"):
            return float(text.split(":", 1)[1])
        return 0.0
