"""Gemini Free Recipe（Google 注册 → AI Studio Get API Key → 入池）

⚠️ 注意：
- Google 风控极严，本流程提供框架，**实际选择器/反检测策略需要随时维护**。
- 必须使用住宅代理 + 优质 IP（推荐印度尼西亚/越南），机房 IP 100% 失败。
- 单号 $0.5-1（SMS + 代理 + Captcha + 邮箱）
- 失败率 30-50% 是正常水平，要持续 A/B 不同策略。
"""
from __future__ import annotations
import asyncio
import secrets
import string
from datetime import datetime

import httpx
from loguru import logger

from orchestrator.state_machine import TaskCtx
from orchestrator.settings import settings
from adapters.email import get_provider as email_provider
from adapters.sms import get_provider as sms_provider
from adapters.captcha import get_provider as captcha_provider
from adapters.browser import open_session
from budget.controller import BudgetController


def _gen_password() -> str:
    chars = string.ascii_letters + string.digits + "!@#$%^&*"
    return "".join(secrets.choice(chars) for _ in range(16))


def _gen_name() -> tuple[str, str]:
    first_pool = ["Alex", "Jordan", "Taylor", "Casey", "Morgan", "Riley", "Skyler", "Avery"]
    last_pool = ["Smith", "Johnson", "Brown", "Lee", "Garcia", "Miller", "Davis", "Wilson"]
    return secrets.choice(first_pool), secrets.choice(last_pool)


async def run(ctx: TaskCtx) -> None:
    budget = BudgetController(settings)
    await budget.assert_account_can_start(ctx)

    email = email_provider()
    sms = sms_provider()
    solver = captcha_provider()

    # 1) 邮箱
    addr = await email.request_address(prefix="g")
    ctx.email = addr.address
    await ctx.transition("email_ok")
    logger.info("[task#{}] email = {}", ctx.id, ctx.email)

    password = _gen_password()
    first, last = _gen_name()

    sms_order = None
    try:
        async with open_session(account_id=ctx.id) as page:
            # 2) 打开 Google 注册页
            await page.goto("https://accounts.google.com/signup", timeout=60_000)
            await asyncio.sleep(2)

            # 3) 填表（选择器随 Google 改版会失效，要随时校准）
            await page.fill("input[name='firstName']", first)
            await page.fill("input[name='lastName']", last)
            await page.click("button:has-text('Next'), #collectNameNext button")
            await asyncio.sleep(2)

            # 4) 用户名（用我们生成的邮箱前缀，因 Google 强制 @gmail，
            #    所以需选择 "Use my current email" 选项）
            try:
                await page.click("text=Use your existing email")
                await page.fill("input[type='email']", ctx.email)
            except Exception:
                # 个别版本上没有此选项，则使用 gmail 子邮箱
                local = ctx.email.split("@")[0]
                await page.fill("input[name='Username']", local[:30])
            await page.click("button:has-text('Next')")
            await asyncio.sleep(2)

            # 5) 密码
            await page.fill("input[name='Passwd']", password)
            await page.fill("input[name='ConfirmPasswd'], input[name='PasswdAgain']", password)
            await page.click("button:has-text('Next')")
            await asyncio.sleep(3)

            # 6) 邮箱验证（如选择 use existing email 路径）
            try:
                code = await email.wait_for(
                    ctx.email,
                    regex=r"\b(\d{6})\b",
                    timeout=180,
                )
                await page.fill("input[type='tel'], input[name='code']", code)
                await page.click("button:has-text('Verify'), button:has-text('Next')")
                await asyncio.sleep(2)
            except TimeoutError:
                logger.warning("[task#{}] email verification timeout (may not be required)", ctx.id)

            # 7) 手机号验证
            country_map = {"183": "+7", "22": "+91", "6": "+62", "89": "+84", "187": "+1"}
            sms_order = await sms.request_phone(service="go", country=settings.sms_default_country)
            ctx.phone = sms_order.phone
            await ctx.record_cost("sms", sms_order.cost_usd)

            # Google 用国旗 dropdown 选国家
            await page.fill("input[type='tel']", sms_order.phone.lstrip("+"))
            await page.click("button:has-text('Next')")
            sms_code = await sms.wait_for(sms_order.id, timeout=300)
            await page.fill("input[name='code'], input[type='tel']:nth-of-type(2)", sms_code)
            await page.click("button:has-text('Verify'), button:has-text('Next')")
            await sms.release(sms_order.id, success=True)
            await ctx.transition("phone_ok")

            # 8) 生日 / 性别
            await page.fill("input[name='day']", "15")
            await page.select_option("select#month", "5")
            await page.fill("input[name='year']", "1995")
            await page.select_option("select#gender", "1")
            await page.click("button:has-text('Next')")
            await asyncio.sleep(2)

            # 9) 同意条款
            try:
                await page.click("button:has-text('I agree'), button:has-text('Accept')")
            except Exception:
                pass

            await ctx.transition("registered")
            await asyncio.sleep(3)

            # 10) 跳转 AI Studio 抓 Key
            await page.goto("https://aistudio.google.com/apikey", timeout=60_000)
            await asyncio.sleep(3)

            # 接受 Terms（首次进入）
            try:
                await page.click("text=I agree to the")
                await page.click("button:has-text('Continue')")
            except Exception:
                pass

            # 创建 API Key
            await page.click("button:has-text('Create API key'), button:has-text('Get API key')")
            await asyncio.sleep(2)
            try:
                await page.click("text=Create API key in new project")
            except Exception:
                pass
            await asyncio.sleep(5)

            # 抓取 Key 文本
            key_locator = page.locator("input[readonly], textarea[readonly], code:has-text('AIza')")
            api_key = (await key_locator.first.inner_text()) or (
                await key_locator.first.input_value()
            )
            api_key = api_key.strip()
            if not api_key.startswith("AIza"):
                raise RuntimeError(f"unexpected api key shape: {api_key[:8]}...")

            await ctx.transition("key_extracted")

        # 11) 入池：调 new-api admin API 创建 channel（灰度分组）
        channel_id = await _import_to_new_api(api_key, ctx.email)
        await ctx.save_account(
            email=ctx.email,
            password_vault=password,  # TODO: 改写入 Vault
            phone=ctx.phone,
            api_key_vault=api_key,    # TODO: 改写入 Vault
            new_api_channel_id=channel_id,
        )
        await ctx.transition("imported")
        await ctx.transition("done")
        logger.info("[task#{}] DONE: channel={} email={}", ctx.id, channel_id, ctx.email)
    except Exception:
        if sms_order is not None:
            try:
                await sms.release(sms_order.id, success=False)
            except Exception:
                pass
        raise


async def _import_to_new_api(api_key: str, email: str) -> int:
    """调 new-api `/api/channel` 把新 Key 加入 gemini-free-canary 分组"""
    base = settings.new_api_base.rstrip("/")
    if not base or not settings.new_api_admin_token:
        logger.warning("new-api 未配置，跳过入池（仅记录到 DB）")
        return 0
    payload = {
        "name": f"gemini-free-{email[:24]}-{datetime.utcnow():%Y%m%d}",
        "type": 25,  # Gemini in new-api
        "key": api_key,
        "models": "gemini-2.0-flash,gemini-2.0-flash-lite,gemini-1.5-flash",
        "group": "gemini-free-canary",
        "priority": 100,
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
