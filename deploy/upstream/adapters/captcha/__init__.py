from __future__ import annotations
from orchestrator.settings import settings
from .base import CaptchaSolver

_singleton: CaptchaSolver | None = None


def get_provider() -> CaptchaSolver:
    global _singleton
    if _singleton is not None:
        return _singleton
    p = settings.captcha_provider
    if p == "capsolver":
        from .capsolver import CapSolver
        _singleton = CapSolver()
    else:
        raise ValueError(f"unknown captcha provider: {p}")
    return _singleton


__all__ = ["CaptchaSolver", "get_provider"]
