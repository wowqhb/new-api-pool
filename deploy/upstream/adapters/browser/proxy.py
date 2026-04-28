"""住宅代理 sticky session 管理"""
from __future__ import annotations
import hashlib
import urllib.parse
from dataclasses import dataclass

from orchestrator.settings import settings


@dataclass
class ProxyEndpoint:
    server: str
    username: str | None
    password: str | None
    label: str

    def to_playwright(self) -> dict:
        proxy = {"server": self.server}
        if self.username:
            proxy["username"] = self.username
        if self.password:
            proxy["password"] = self.password
        return proxy


def _sticky_session_id(account_id: int) -> str:
    return hashlib.sha1(f"acct-{account_id}".encode()).hexdigest()[:10]


def lease_proxy(account_id: int) -> ProxyEndpoint:
    """
    住宅代理一般支持 sticky session：
        host: gate.example.com:7777
        user: <login>-session-<sid>-sessTime-30
        pass: <password>
    """
    base_url = settings.proxy_url
    if not base_url:
        raise ValueError("PROXY_URL 未配置（住宅代理强制要求）")
    parsed = urllib.parse.urlparse(base_url)
    sid = _sticky_session_id(account_id)
    user = parsed.username or ""
    if user and "{sid}" in user:
        user = user.replace("{sid}", sid)
    elif user:
        user = f"{user}-session-{sid}-sessTime-30"
    else:
        user = f"session-{sid}"
    server = f"{parsed.scheme}://{parsed.hostname}:{parsed.port}"
    return ProxyEndpoint(
        server=server,
        username=user,
        password=parsed.password,
        label=f"sticky:{sid}",
    )


def release_proxy(_proxy: ProxyEndpoint) -> None:
    return None
