"""智能路由 sidecar

在 Caddy 与 new-api 之间，做：
1. 跨分组重试（fallback chain）
2. 流式响应转发
3. 命中错误码重试

约定的 fallback chain：
  - x-router-chain header 显式指定，如 "official,claude-oauth,gemini-free"
  - 否则按用户分组的默认链
"""
from __future__ import annotations
import os, json, logging, time
from collections.abc import AsyncIterator

import httpx
from fastapi import FastAPI, Request
from fastapi.responses import JSONResponse, StreamingResponse

logging.basicConfig(level=logging.INFO, format='%(asctime)s %(levelname)s %(message)s')
log = logging.getLogger(__name__)

UPSTREAM = os.environ.get("UPSTREAM", "http://new-api-1:3000")
DEFAULT_CHAINS = json.loads(os.environ.get("FALLBACK_CHAINS", json.dumps({
    "vip": ["official", "claude-oauth", "gemini-free"],
    "default": ["claude-oauth", "official", "gemini-free", "third-party"],
    "free": ["gemini-free", "third-party"],
})))

RETRY_CODES = {429, 500, 502, 503, 504}
DEAD_CODES = {401, 403}    # 渠道死了，不重试同分组，直接换分组
MAX_RETRIES_PER_GROUP = 2

app = FastAPI(title="smart-router")
client = httpx.AsyncClient(timeout=httpx.Timeout(connect=10.0, read=600.0, write=30.0, pool=10.0))


def get_user_group(req: Request) -> str:
    """从 Authorization 看用户分组（如果有 prefix），否则 default"""
    return req.headers.get("X-User-Group", "default")


def get_chain(req: Request) -> list[str]:
    custom = req.headers.get("X-Router-Chain")
    if custom:
        return [g.strip() for g in custom.split(",") if g.strip()]
    return DEFAULT_CHAINS.get(get_user_group(req), DEFAULT_CHAINS["default"])


async def stream_to_client(resp: httpx.Response) -> AsyncIterator[bytes]:
    async for chunk in resp.aiter_bytes():
        yield chunk


@app.api_route("/v1/{path:path}", methods=["GET", "POST", "PUT", "DELETE", "OPTIONS"])
async def proxy(path: str, request: Request):
    body = await request.body()
    chain = get_chain(request)
    is_stream = b'"stream":true' in body or b'"stream": true' in body

    headers = {k: v for k, v in request.headers.items() if k.lower() not in ("host", "content-length")}

    last_error = None
    for group in chain:
        # 在 header 加 X-Channel-Group 让 new-api 按 group 选渠道
        headers["X-Channel-Group"] = group
        for attempt in range(MAX_RETRIES_PER_GROUP):
            try:
                t0 = time.monotonic()
                if is_stream:
                    upstream_req = client.build_request(
                        request.method, f"{UPSTREAM}/v1/{path}",
                        content=body, headers=headers,
                        params=dict(request.query_params),
                    )
                    upstream_resp = await client.send(upstream_req, stream=True)
                    if upstream_resp.status_code in DEAD_CODES:
                        await upstream_resp.aclose()
                        last_error = f"group={group} status={upstream_resp.status_code}"
                        log.warning("dead group %s, switch", group)
                        break  # 跳出 attempt 重试，进下一 group
                    if upstream_resp.status_code in RETRY_CODES:
                        await upstream_resp.aclose()
                        log.warning("retryable group=%s status=%s attempt=%s",
                                    group, upstream_resp.status_code, attempt)
                        last_error = f"group={group} status={upstream_resp.status_code}"
                        continue
                    log.info("ok group=%s status=%s rt=%.0fms (stream)",
                             group, upstream_resp.status_code, (time.monotonic() - t0) * 1000)
                    return StreamingResponse(
                        stream_to_client(upstream_resp),
                        status_code=upstream_resp.status_code,
                        headers={k: v for k, v in upstream_resp.headers.items()
                                 if k.lower() not in ("content-encoding", "content-length", "transfer-encoding")},
                        media_type=upstream_resp.headers.get("content-type"),
                    )
                else:
                    r = await client.request(
                        request.method, f"{UPSTREAM}/v1/{path}",
                        content=body, headers=headers,
                        params=dict(request.query_params),
                    )
                    if r.status_code in DEAD_CODES:
                        last_error = f"group={group} status={r.status_code}"
                        log.warning("dead group %s, switch", group)
                        break
                    if r.status_code in RETRY_CODES:
                        log.warning("retryable group=%s status=%s attempt=%s", group, r.status_code, attempt)
                        last_error = f"group={group} status={r.status_code}"
                        continue
                    log.info("ok group=%s status=%s rt=%.0fms", group, r.status_code, (time.monotonic() - t0) * 1000)
                    return JSONResponse(
                        content=r.json() if "json" in r.headers.get("content-type", "") else r.text,
                        status_code=r.status_code,
                    )
            except httpx.TimeoutException as e:
                last_error = f"group={group} timeout {e}"
                log.warning("timeout group=%s attempt=%s: %s", group, attempt, e)
                continue
            except Exception as e:
                last_error = f"group={group} error {e}"
                log.exception("error group=%s", group)
                break

    log.error("all chains failed: %s", last_error)
    return JSONResponse(
        content={"error": {"message": "All upstream groups failed", "type": "upstream_error", "details": last_error}},
        status_code=503,
    )


@app.get("/healthz")
async def healthz():
    return {"ok": True}
