"""Camoufox + Playwright 会话封装"""
from __future__ import annotations
import asyncio
import json
import os
import time
from contextlib import asynccontextmanager
from pathlib import Path

from loguru import logger

from .fingerprint import get_or_create_fingerprint, Fingerprint
from .proxy import lease_proxy, release_proxy, ProxyEndpoint
from orchestrator.settings import settings


def _profile_dir(account_id: int) -> Path:
    base = Path(settings.profile_root)
    base.mkdir(parents=True, exist_ok=True)
    p = base / f"acct-{account_id}"
    p.mkdir(parents=True, exist_ok=True)
    return p


@asynccontextmanager
async def open_session(account_id: int, *, headless: bool = True, record_video: bool = True):
    """打开一个绑定 account_id 的浏览器会话。

    使用 Camoufox（Firefox fork）；若不可用，回落到 Playwright Firefox。
    """
    fp = await get_or_create_fingerprint(account_id)
    proxy = lease_proxy(account_id)
    profile = _profile_dir(account_id)
    storage_state = profile / "state.json"
    video_dir = profile / "videos"
    video_dir.mkdir(parents=True, exist_ok=True)

    browser = None
    context = None
    try:
        browser, context = await _launch(fp, proxy, headless, storage_state, video_dir, record_video)
        page = await context.new_page()
        # 注入指纹相关 JS（供网页 JS 探测时返回固定值）
        await page.add_init_script(
            f"""
            Object.defineProperty(navigator, 'deviceMemory', {{ get: () => {fp.device_memory} }});
            Object.defineProperty(navigator, 'hardwareConcurrency', {{ get: () => {fp.hardware_concurrency} }});
            Object.defineProperty(screen, 'colorDepth', {{ get: () => {fp.color_depth} }});
            """
        )
        yield page
    finally:
        if context is not None:
            try:
                await context.storage_state(path=str(storage_state))
            except Exception as e:
                logger.warning("save storage_state failed: {}", e)
            try:
                await context.close()
            except Exception:
                pass
        if browser is not None:
            try:
                await browser.close()
            except Exception:
                pass
        release_proxy(proxy)


async def _launch(
    fp: Fingerprint,
    proxy: ProxyEndpoint,
    headless: bool,
    storage_state: Path,
    video_dir: Path,
    record_video: bool,
):
    """优先 Camoufox，失败回落 Playwright Firefox"""
    try:
        from camoufox.async_api import AsyncCamoufox  # type: ignore
        cam = AsyncCamoufox(
            headless=headless,
            proxy=proxy.to_playwright(),
            **fp.to_camoufox_config(),
        )
        browser = await cam.__aenter__()
        ctx_kwargs = {}
        if record_video:
            ctx_kwargs["record_video_dir"] = str(video_dir)
        if storage_state.exists():
            ctx_kwargs["storage_state"] = str(storage_state)
        context = await browser.new_context(**ctx_kwargs)
        return browser, context
    except Exception as e:
        logger.warning("camoufox unavailable, fallback to playwright firefox: {}", e)

    from playwright.async_api import async_playwright  # type: ignore
    pw = await async_playwright().start()
    browser = await pw.firefox.launch(
        headless=headless,
        proxy=proxy.to_playwright(),
    )
    ctx_kwargs = fp.to_playwright_context_options()
    if record_video:
        ctx_kwargs["record_video_dir"] = str(video_dir)
    if storage_state.exists():
        ctx_kwargs["storage_state"] = str(storage_state)
    context = await browser.new_context(**ctx_kwargs)
    return browser, context


async def save_storage_state(page, account_id: int) -> Path:
    profile = _profile_dir(account_id)
    state_path = profile / "state.json"
    await page.context.storage_state(path=str(state_path))
    return state_path


async def save_cookies(page, account_id: int) -> Path:
    profile = _profile_dir(account_id)
    cookies = await page.context.cookies()
    p = profile / "cookies.json"
    p.write_text(json.dumps(cookies, indent=2))
    return p


async def humanize_typing(page, selector: str, text: str) -> None:
    """模拟人类打字节奏（200-300 wpm 上下波动）"""
    await page.click(selector)
    for ch in text:
        await page.keyboard.type(ch)
        await asyncio.sleep(0.04 + (time.time_ns() % 100) / 1000.0)
