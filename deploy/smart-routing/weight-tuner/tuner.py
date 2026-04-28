"""自适应权重 tuner

每 60 秒：
1. 从 new-api logs DB 拉过去 5 分钟每个渠道的 RT/成功率/QPS
2. 算 score → 归一化为 weight
3. 调 new-api admin API 把新 weight 写回

环境变量：
- LOG_DSN: postgresql://user:pass@host/newapi_logs
- ADMIN_API_TOKEN
- API_BASE: 默认 http://new-api-1:3000
- TICK_SECONDS: 默认 60
- WINDOW_MINUTES: 默认 5
- MIN_REQUESTS: 默认 20（小于这个不调整）
- DRY_RUN: true 时只打印不写
"""
from __future__ import annotations
import asyncio, logging, os, time, math
from dataclasses import dataclass

import httpx
import psycopg
from prometheus_client import start_http_server, Gauge, Counter

logging.basicConfig(level=logging.INFO, format='%(asctime)s %(levelname)s %(message)s')
log = logging.getLogger(__name__)

LOG_DSN = os.environ["LOG_DSN"]
ADMIN_API_TOKEN = os.environ["ADMIN_API_TOKEN"]
API_BASE = os.environ.get("API_BASE", "http://new-api-1:3000")
TICK = int(os.environ.get("TICK_SECONDS", "60"))
WINDOW = int(os.environ.get("WINDOW_MINUTES", "5"))
MIN_REQS = int(os.environ.get("MIN_REQUESTS", "20"))
DRY = os.environ.get("DRY_RUN", "false").lower() == "true"
EMA_ALPHA = float(os.environ.get("EMA_ALPHA", "0.4"))   # 平滑系数

g_score = Gauge('smart_routing_channel_score', 'Score per channel', ['channel_id', 'group'])
g_weight = Gauge('smart_routing_channel_weight', 'New weight per channel', ['channel_id'])
c_updates = Counter('smart_routing_updates_total', 'Weight updates', ['channel_id'])

# 每个渠道的 EMA score 缓存
ema_cache: dict[int, float] = {}


@dataclass
class ChannelStat:
    channel_id: int
    group: str
    total: int
    success: int
    p95_ms: float
    qps: float

    @property
    def success_rate(self) -> float:
        return self.success / max(self.total, 1)


async def fetch_stats(window_min: int) -> list[ChannelStat]:
    sql = """
    SELECT
        channel_id,
        COALESCE(MAX(\"group\"), 'default') AS grp,
        COUNT(*) AS total,
        COUNT(*) FILTER (WHERE type = 2) AS success,
        COALESCE(percentile_cont(0.95) WITHIN GROUP (ORDER BY use_time), 0) AS p95_ms,
        COUNT(*)::float / (%s * 60) AS qps
    FROM logs
    WHERE created_at > NOW() - INTERVAL '%s minutes'
      AND channel_id IS NOT NULL
      AND channel_id > 0
    GROUP BY channel_id
    """
    out = []
    async with await psycopg.AsyncConnection.connect(LOG_DSN) as conn:
        async with conn.cursor() as cur:
            await cur.execute(sql, (window_min, window_min))
            async for row in cur:
                out.append(ChannelStat(
                    channel_id=row[0], group=row[1], total=row[2],
                    success=row[3], p95_ms=float(row[4] or 0), qps=float(row[5] or 0)
                ))
    return out


def compute_score(s: ChannelStat) -> float:
    if s.total < MIN_REQS:
        return 0.5  # 中性，不调整
    sr = s.success_rate
    rt_factor = 1.0 / max(s.p95_ms / 1000.0, 0.3)  # 1 / RT(秒)
    qps_norm = min(s.qps, 50) / 50.0
    raw = (sr ** 2) * rt_factor * (1 - qps_norm * 0.3)
    return max(0.01, raw)


async def update_channel(client: httpx.AsyncClient, channel_id: int, weight: int) -> None:
    if DRY:
        log.info("[DRY] channel %s weight -> %s", channel_id, weight)
        return
    r = await client.put(
        f"{API_BASE}/api/channel",
        headers={"Authorization": f"Bearer {ADMIN_API_TOKEN}"},
        json={"id": channel_id, "weight": weight},
        timeout=10,
    )
    if r.status_code == 200 and r.json().get("success"):
        c_updates.labels(channel_id=str(channel_id)).inc()
        log.info("channel %s weight -> %s", channel_id, weight)
    else:
        log.error("update failed for %s: %s %s", channel_id, r.status_code, r.text[:200])


async def tick():
    stats = await fetch_stats(WINDOW)
    if not stats:
        log.info("no stats, skip")
        return

    # 每分组分别归一化（不同分组不可比）
    by_group: dict[str, list[ChannelStat]] = {}
    for s in stats:
        by_group.setdefault(s.group, []).append(s)

    async with httpx.AsyncClient() as client:
        for grp, items in by_group.items():
            scores = {}
            for s in items:
                raw = compute_score(s)
                # EMA 平滑
                prev = ema_cache.get(s.channel_id, raw)
                smoothed = EMA_ALPHA * raw + (1 - EMA_ALPHA) * prev
                ema_cache[s.channel_id] = smoothed
                scores[s.channel_id] = smoothed
                g_score.labels(channel_id=str(s.channel_id), group=grp).set(smoothed)

            max_s = max(scores.values()) or 1.0
            for cid, score in scores.items():
                weight = max(1, min(100, int(score / max_s * 100)))
                g_weight.labels(channel_id=str(cid)).set(weight)
                await update_channel(client, cid, weight)


async def main():
    start_http_server(9090)
    log.info("smart-routing weight-tuner started (TICK=%ss WINDOW=%sm MIN_REQS=%s DRY=%s)",
             TICK, WINDOW, MIN_REQS, DRY)
    while True:
        try:
            await tick()
        except Exception:
            log.exception("tick failed")
        await asyncio.sleep(TICK)


if __name__ == "__main__":
    asyncio.run(main())
