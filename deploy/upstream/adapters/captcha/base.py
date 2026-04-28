"""Captcha Solver 接口"""
from __future__ import annotations
from abc import ABC, abstractmethod


class CaptchaSolver(ABC):
    @abstractmethod
    async def solve_recaptcha_v2(self, site_url: str, site_key: str, *, invisible: bool = False) -> str: ...

    @abstractmethod
    async def solve_recaptcha_v3(
        self, site_url: str, site_key: str, *, action: str = "verify", min_score: float = 0.7
    ) -> str: ...

    @abstractmethod
    async def solve_hcaptcha(self, site_url: str, site_key: str) -> str: ...

    @abstractmethod
    async def solve_turnstile(self, site_url: str, site_key: str, *, action: str | None = None) -> str: ...

    @abstractmethod
    async def balance(self) -> float: ...
