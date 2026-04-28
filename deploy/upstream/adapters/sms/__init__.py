from __future__ import annotations
from orchestrator.settings import settings
from .base import SMSProvider, SMSOrder

_singleton: SMSProvider | None = None


def get_provider() -> SMSProvider:
    global _singleton
    if _singleton is not None:
        return _singleton
    p = settings.sms_provider
    if p in ("sms-activate", "5sim"):
        from .sms_activate import SMSActivate
        _singleton = SMSActivate()
    else:
        raise ValueError(f"unknown sms provider: {p}")
    return _singleton


__all__ = ["SMSProvider", "SMSOrder", "get_provider"]
