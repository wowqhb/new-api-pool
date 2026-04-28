"""SMS 接码接口"""
from __future__ import annotations
from abc import ABC, abstractmethod
from dataclasses import dataclass


@dataclass
class SMSOrder:
    id: str
    phone: str
    country: str
    service: str
    cost_usd: float


class SMSProvider(ABC):
    @abstractmethod
    async def request_phone(self, service: str, country: str | None = None) -> SMSOrder: ...

    @abstractmethod
    async def wait_for(self, order_id: str, timeout: int = 300) -> str:
        """阻塞等待短信到达，返回验证码"""
        ...

    @abstractmethod
    async def release(self, order_id: str, success: bool = True) -> None:
        """归还（成功）或申请退款（失败）"""
        ...

    @abstractmethod
    async def balance(self) -> float: ...
