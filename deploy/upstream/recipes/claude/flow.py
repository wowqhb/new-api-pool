"""Claude OAuth Recipe（半自动）

⚠️ Claude 注册 + 绑卡风控极重，**绑卡环节必须人工**：
- 自动：邮箱注册、登录、抓取 OAuth access/refresh token
- 人工：绑卡、付费订阅、首次登录设备验证

本流程支持两种模式：
  mode=oauth_capture: 假定账号已注册并订阅，使用现成账号抓 OAuth token 入池
  mode=full        : 完整流程（自动注册 + 提示人工绑卡 + 自动抓 token）

Token 刷新由 [oauth_refresh.py](./oauth_refresh.py) 单独 cron 跑。
"""
from __future__ import annotations
import asyncio
from datetime import datetime, timezone

import httpx
from loguru import logger

from orchestrator.state_machine import TaskCtx
from orchestrator.settings import settings
from adapters.email import get_provider as email_provider
from adapters.browser import open_session
from budget.controller import BudgetController


CLAUDE_OAUTH_AUTHORIZE = "https://claude.ai/oauth/authorize"
CLAUDE_API_KEYS_PAGE = "https://console.anthropic.com/settings/keys"
CLAUDE_LOGIN = "https://claude.ai/login"


async def run(ctx: TaskCtx) -> None:
    mode = ctx.payload.get("mode", "oauth_capture")
    budget = BudgetController(settings)
    await budget.assert_account_can_start(ctx)

    if mode == "full":
        await _run_full(ctx)
    else:
        await _run_oauth_capture(ctx)


async def _run_full(ctx: TaskCtx) -> None:
    """完整流程：注册 → 等人工绑卡 → 抓 OAuth"""
    email = email_provider()

    addr = await email.request_address(prefix="cl")
    ctx.email = addr.address
    await ctx.transition("email_ok")

    async with open_session(account_id=ctx.id, headless=False) as page:
        # 1) 注册（Claude 用 magic link，无密码）
        await page.goto(CLAUDE_LOGIN, timeout=60_000)
        await page.fill("input[type='email']", ctx.email)
        await page.click("button:has-text('Continue')")
        await asyncio.sleep(3)

        # 2) 抓邮件里的登录链接
        link = await email.wait_for(
            ctx.email, regex=r"(https://claude\.ai/[A-Za-z0-9_\-./?=&]+)", timeout=180
        )
        await page.goto(link, timeout=60_000)
        await asyncio.sleep(3)
        await ctx.transition("registered")

        # 3) 提示人工：绑卡 + 订阅 Pro
        logger.warning(
            "[task#{}] 人工接手：请在浏览器内完成 ① 绑卡 ② 订阅 Claude Pro。"
            "完成后回到这个 worker 终端按 ENTER。",
            ctx.id,
        )
        await _wait_for_manual_step(ctx)
        await ctx.transition("activated")

        # 4) 跳到 OAuth 授权页，抓 access/refresh token
        token_data = await _capture_oauth_token(page)
        await ctx.transition("key_extracted")

    channel_id = await _import_to_new_api(token_data, ctx.email)
    await ctx.save_account(
        email=ctx.email,
        access_token_vault=token_data["access_token"],   # TODO: Vault
        refresh_token_vault=token_data["refresh_token"], # TODO: Vault
        new_api_channel_id=channel_id,
    )
    await ctx.transition("imported")
    await ctx.transition("done")


async def _run_oauth_capture(ctx: TaskCtx) -> None:
    """已有账号 + 已订阅，仅做：登录 + 抓 OAuth token"""
    email_addr = ctx.payload.get("email")
    if not email_addr:
        raise ValueError("oauth_capture 模式需要 payload.email")
    ctx.email = email_addr
    await ctx.transition("email_ok")

    email = email_provider()

    async with open_session(account_id=ctx.id, headless=False) as page:
        await page.goto(CLAUDE_LOGIN, timeout=60_000)
        await page.fill("input[type='email']", email_addr)
        await page.click("button:has-text('Continue')")

        link = await email.wait_for(
            email_addr, regex=r"(https://claude\.ai/[A-Za-z0-9_\-./?=&]+)", timeout=180
        )
        await page.goto(link, timeout=60_000)
        await asyncio.sleep(3)
        await ctx.transition("activated")

        token_data = await _capture_oauth_token(page)
        await ctx.transition("key_extracted")

    channel_id = await _import_to_new_api(token_data, email_addr)
    await ctx.save_account(
        email=email_addr,
        access_token_vault=token_data["access_token"],
        refresh_token_vault=token_data["refresh_token"],
        new_api_channel_id=channel_id,
    )
    await ctx.transition("imported")
    await ctx.transition("done")


async def _capture_oauth_token(page) -> dict:
    """通过 page.context.cookies + sessionStorage 取出 OAuth"""
    # claude.ai 主域 cookie 含 sessionKey；OAuth 调用一般在 console.anthropic.com
    cookies = await page.context.cookies()
    session_key = next((c["value"] for c in cookies if c["name"] == "sessionKey"), None)

    # 从 console.anthropic.com 抓 access token（在 localStorage）
    await page.goto("https://console.anthropic.com", timeout=60_000)
    await asyncio.sleep(3)

    access_token = await page.evaluate(
        """() => {
            for (const k of Object.keys(localStorage)) {
                if (k.includes('access_token') || k.startsWith('@@auth0')) {
                    try {
                        const v = JSON.parse(localStorage.getItem(k));
                        if (v.body?.access_token) return v.body.access_token;
                        if (v.access_token) return v.access_token;
                    } catch(_) {}
                }
            }
            return null;
        }"""
    )
    refresh_token = await page.evaluate(
        """() => {
            for (const k of Object.keys(localStorage)) {
                if (k.includes('refresh') || k.startsWith('@@auth0')) {
                    try {
                        const v = JSON.parse(localStorage.getItem(k));
                        if (v.body?.refresh_token) return v.body.refresh_token;
                        if (v.refresh_token) return v.refresh_token;
                    } catch(_) {}
                }
            }
            return null;
        }"""
    )

    if not access_token:
        raise RuntimeError("未抓到 access_token，可能未完成订阅或登录态丢失")

    return {
        "access_token": access_token,
        "refresh_token": refresh_token or "",
        "session_key": session_key or "",
        "captured_at": datetime.now(timezone.utc).isoformat(),
    }


async def _wait_for_manual_step(ctx: TaskCtx) -> None:
    """半自动：等 DB 上 payload.manual_done = true（外部脚本/Telegram bot 推过来）"""
    deadline = asyncio.get_event_loop().time() + 30 * 60
    while asyncio.get_event_loop().time() < deadline:
        async with ctx.conn.cursor() as cur:
            await cur.execute("SELECT payload FROM tasks WHERE id=%s", (ctx.id,))
            row = await cur.fetchone()
            payload = row[0] if isinstance(row[0], dict) else {}
            if payload.get("manual_done"):
                return
        await asyncio.sleep(15)
    raise TimeoutError("manual step 超时（30 分钟未确认）")


async def _import_to_new_api(token_data: dict, email: str) -> int:
    base = settings.new_api_base.rstrip("/")
    if not base or not settings.new_api_admin_token:
        logger.warning("new-api 未配置，跳过入池")
        return 0
    payload = {
        "name": f"claude-oauth-{email[:24]}-{datetime.utcnow():%Y%m%d}",
        "type": 14,  # Anthropic in new-api
        "key": token_data["access_token"],
        "other": token_data.get("refresh_token", ""),
        "models": "claude-sonnet-4-5,claude-opus-4-5,claude-haiku-4-5",
        "group": "claude-oauth-canary",
        "priority": 150,
        "weight": 50,
        "auto_ban": 1,
    }
    headers = {"Authorization": f"Bearer {settings.new_api_admin_token}"}
    async with httpx.AsyncClient(timeout=30) as cli:
        r = await cli.post(f"{base}/api/channel/", json=payload, headers=headers)
        r.raise_for_status()
        data = r.json()
        if not data.get("success"):
            raise RuntimeError(f"new-api import failed: {data}")
        return int(data.get("data", {}).get("id", 0))
