"""邮箱供给接口"""
from __future__ import annotations
from abc import ABC, abstractmethod
from dataclasses import dataclass


@dataclass
class EmailAddress:
    address: str
    provider: str
    metadata: dict


class EmailProvider(ABC):
    @abstractmethod
    async def request_address(self, prefix: str | None = None) -> EmailAddress: ...

    @abstractmethod
    async def wait_for(self, address: str, *, regex: str, timeout: int = 120, since: str | None = None) -> str:
        """等收信中匹配 regex group(1) 的内容（如 6 位验证码）"""
        ...

    @abstractmethod
    async def release(self, address: str) -> None:
        """归还/标记弃用"""
        ...

    @property
    def cost_per_email(self) -> float:
        return 0.0
