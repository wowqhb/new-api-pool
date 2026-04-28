"""Fingerprint 维护：每个 account_id 绑定一组固定的浏览器指纹"""
from __future__ import annotations
import json
import random
from dataclasses import dataclass, asdict

from orchestrator.db import db_cursor


_LOCALES = ["en-US", "en-GB", "en-CA", "en-AU"]
_TIMEZONES = ["America/New_York", "America/Los_Angeles", "Europe/London", "Asia/Tokyo", "Asia/Singapore"]
_RESOLUTIONS = [(1920, 1080), (1366, 768), (1536, 864), (1440, 900), (2560, 1440)]
# Firefox UA 系列（Camoufox 是 Firefox fork）
_UAS = [
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:122.0) Gecko/20100101 Firefox/122.0",
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 14.3; rv:122.0) Gecko/20100101 Firefox/122.0",
    "Mozilla/5.0 (X11; Linux x86_64; rv:122.0) Gecko/20100101 Firefox/122.0",
]


@dataclass
class Fingerprint:
    id: int | None
    account_id: int
    user_agent: str
    locale: str
    timezone: str
    width: int
    height: int
    device_memory: int  # 4/8/16
    hardware_concurrency: int  # 2/4/8/12
    color_depth: int

    def to_camoufox_config(self) -> dict:
        return {
            "user_agent": self.user_agent,
            "locale": self.locale,
            "timezone_id": self.timezone,
            "viewport": {"width": self.width, "height": self.height},
            "screen": {"width": self.width, "height": self.height},
            "color_scheme": "light",
            # 由 Camoufox 自动生成 canvas/webgl/audio 指纹的固定种子
            "addons": [],
        }

    def to_playwright_context_options(self) -> dict:
        return {
            "user_agent": self.user_agent,
            "locale": self.locale,
            "timezone_id": self.timezone,
            "viewport": {"width": self.width, "height": self.height},
            "screen": {"width": self.width, "height": self.height},
            "color_scheme": "light",
        }


async def get_or_create_fingerprint(account_id: int) -> Fingerprint:
    async with db_cursor() as cur:
        await cur.execute(
            "SELECT id, account_id, payload FROM fingerprints WHERE account_id=%s",
            (account_id,),
        )
        row = await cur.fetchone()
        if row:
            payload = row[2] if isinstance(row[2], dict) else json.loads(row[2])
            return Fingerprint(id=row[0], account_id=row[1], **payload)
        w, h = random.choice(_RESOLUTIONS)
        fp = Fingerprint(
            id=None,
            account_id=account_id,
            user_agent=random.choice(_UAS),
            locale=random.choice(_LOCALES),
            timezone=random.choice(_TIMEZONES),
            width=w,
            height=h,
            device_memory=random.choice([4, 8, 16]),
            hardware_concurrency=random.choice([4, 8, 12]),
            color_depth=24,
        )
        payload = {k: v for k, v in asdict(fp).items() if k not in ("id", "account_id")}
        await cur.execute(
            "INSERT INTO fingerprints (account_id, payload) VALUES (%s, %s) RETURNING id",
            (account_id, json.dumps(payload)),
        )
        fp.id = (await cur.fetchone())[0]
        return fp
