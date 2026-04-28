from __future__ import annotations
from orchestrator.settings import settings
from .base import EmailProvider, EmailAddress

_singleton: EmailProvider | None = None


def get_provider() -> EmailProvider:
    global _singleton
    if _singleton is not None:
        return _singleton
    p = settings.email_provider
    if p == "cloudflare":
        from .cloudflare import CloudflareCatchall
        _singleton = CloudflareCatchall()
    elif p == "mailtm":
        from .mailtm import MailTm
        _singleton = MailTm()
    else:
        raise ValueError(f"unknown email provider: {p}")
    return _singleton


__all__ = ["EmailProvider", "EmailAddress", "get_provider"]
