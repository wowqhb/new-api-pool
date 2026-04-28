"""上游预算控制器：单日总预算 / 单号成本上限 / 失败率熔断 / Telegram 告警"""
from __future__ import annotations
import asyncio
import time
from dataclasses import dataclass

import httpx
import psycopg
from loguru import logger

from orchestrator.settings import Settings
from orchestrator.state_machine import TaskCtx


@dataclass
class BudgetStatus:
    today_spent_usd: float
    today_succ: int
    today_fail: int
    today_total: int

    @property
    def failure_rate(self) -> float:
        if self.today_total == 0:
            return 0.0
        return self.today_fail / self.today_total


class BudgetExceeded(Exception):
    pass


class BudgetController:
    """
    Gates:
      - check_can_proceed(): worker 启动新任务前调
      - assert_account_can_start(ctx): recipe 入口调（确认这个号还能继续花）
      - record(ctx, item, usd): 每次花钱前/后记录（recipe 内部）

    数据来源：tasks/budget_ledger（已存在）。
    """

    def __init__(self, settings: Settings):
        self.s = settings
        self._stop_until = 0.0  # 软停线（失败率超阈值时短暂停线）

    async def check_can_proceed(self) -> bool:
        if time.time() < self._stop_until:
            return False
        try:
            st = await self._fetch_status()
        except Exception as e:
            logger.warning("budget check failed (DB unreachable?): {}", e)
            return True

        if st.today_spent_usd >= self.s.daily_budget_usd:
            await self._alert(
                f"⛔ 上游预算已达上限 ${self.s.daily_budget_usd}，今日累计 ${st.today_spent_usd:.2f}"
            )
            self._stop_until = time.time() + 1800  # 30min 后再检查（明天会自然刷新）
            return False

        if st.today_total >= 20 and st.failure_rate > self.s.failure_rate_stop:
            await self._alert(
                f"⛔ 失败率 {st.failure_rate:.0%} > 阈值 {self.s.failure_rate_stop:.0%}，"
                f"暂停 30 分钟（成功 {st.today_succ}/失败 {st.today_fail}）"
            )
            self._stop_until = time.time() + 1800
            return False

        return True

    async def assert_account_can_start(self, ctx: TaskCtx) -> None:
        """recipe 入口：当前号已花的钱不能超过 max_cost_per_account"""
        async with ctx.conn.cursor() as cur:
            await cur.execute(
                "SELECT COALESCE(SUM(cost_usd), 0) FROM budget_ledger WHERE task_id = %s",
                (ctx.id,),
            )
            spent = float((await cur.fetchone())[0] or 0)
        if spent >= self.s.max_cost_per_account:
            raise BudgetExceeded(
                f"task {ctx.id} 已花费 ${spent:.2f} 超过单号上限 ${self.s.max_cost_per_account}"
            )

    async def _fetch_status(self) -> BudgetStatus:
        conn = await psycopg.AsyncConnection.connect(self.s.pg_dsn, autocommit=True)
        try:
            async with conn.cursor() as cur:
                await cur.execute(
                    "SELECT COALESCE(SUM(cost_usd), 0) FROM budget_ledger "
                    "WHERE created_at >= date_trunc('day', NOW())"
                )
                spent = float((await cur.fetchone())[0] or 0)

                await cur.execute(
                    "SELECT state, COUNT(*) FROM tasks "
                    "WHERE started_at >= date_trunc('day', NOW()) "
                    "GROUP BY state"
                )
                rows = await cur.fetchall()
        finally:
            await conn.close()

        succ = fail = total = 0
        for state, cnt in rows:
            total += cnt
            if state == "done":
                succ += cnt
            elif state == "failed":
                fail += cnt
        return BudgetStatus(today_spent_usd=spent, today_succ=succ, today_fail=fail, today_total=total)

    async def _alert(self, text: str) -> None:
        logger.warning(text)
        if not (self.s.telegram_bot_token and self.s.telegram_chat_id):
            return
        url = f"https://api.telegram.org/bot{self.s.telegram_bot_token}/sendMessage"
        try:
            async with httpx.AsyncClient(timeout=10) as cli:
                await cli.post(
                    url,
                    json={"chat_id": self.s.telegram_chat_id, "text": text, "parse_mode": "HTML"},
                )
        except Exception as e:
            logger.warning("telegram alert failed: {}", e)


async def daily_summary(settings: Settings) -> str:
    """orchestrator 端：每天 09:00 推送一次摘要"""
    bc = BudgetController(settings)
    st = await bc._fetch_status()
    return (
        f"📊 上游流水线日报\n"
        f"今日花费：${st.today_spent_usd:.2f} / ${settings.daily_budget_usd}\n"
        f"任务总数：{st.today_total}（成功 {st.today_succ} / 失败 {st.today_fail}）\n"
        f"失败率：{st.failure_rate:.1%}"
    )
