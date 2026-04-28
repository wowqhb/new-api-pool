"""语义缓存 sidecar

收到 chat completion 请求 → 提 last user message → 取 embedding → RediSearch 近邻 →
  - 命中：直接返回缓存的 response（标记 X-Cache: HIT）
  - 未命中：转给上游 → 收回响应后写入缓存

要求 Redis 8（含 RediSearch + RedisJSON），或 Redis Stack。

环境变量：
- REDIS_URL: redis://:pwd@redis-stack:6379
- UPSTREAM: 转发目标，如 http://router-sidecar:8080
- EMBEDDING_API: 用 new-api 自身做 embedding，如 http://new-api-1:3000/v1/embeddings
- EMBEDDING_MODEL: text-embedding-3-small
- EMBEDDING_TOKEN: 内部 admin token
- THRESHOLD: cosine 距离阈值（默认 0.05，即 95% 相似度）
- TTL_SECONDS: 缓存 TTL（默认 3600）
- INDEX_NAME: chatcache_idx
- ENABLED_MODELS: 逗号分隔的模型白名单（其它模型直通）
"""
from __future__ import annotations
import os, json, hashlib, logging, asyncio
from typing import Any

import httpx
import numpy as np
import redis.asyncio as aredis
from fastapi import FastAPI, Request
from fastapi.responses import JSONResponse, StreamingResponse
from prometheus_client import Counter, Histogram, start_http_server

logging.basicConfig(level=logging.INFO, format='%(asctime)s %(levelname)s %(message)s')
log = logging.getLogger(__name__)

REDIS_URL = os.environ["REDIS_URL"]
UPSTREAM = os.environ.get("UPSTREAM", "http://router-sidecar:8080")
EMBEDDING_API = os.environ.get("EMBEDDING_API", "http://new-api-1:3000/v1/embeddings")
EMBEDDING_MODEL = os.environ.get("EMBEDDING_MODEL", "text-embedding-3-small")
EMBEDDING_TOKEN = os.environ.get("EMBEDDING_TOKEN", "")
THRESHOLD = float(os.environ.get("THRESHOLD", "0.05"))
TTL = int(os.environ.get("TTL_SECONDS", "3600"))
INDEX_NAME = os.environ.get("INDEX_NAME", "chatcache_idx")
ENABLED_MODELS = set(filter(None, os.environ.get("ENABLED_MODELS", "").split(",")))
EMBED_DIM = 1536  # text-embedding-3-small / -large compatible

c_total = Counter('semantic_cache_requests_total', 'Total cache lookups')
c_hits = Counter('semantic_cache_hits_total', 'Cache hits', ['layer'])
c_misses = Counter('semantic_cache_misses_total', 'Cache misses')
h_lookup = Histogram('semantic_cache_lookup_seconds', 'Lookup latency')

app = FastAPI(title="semantic-cache")
client = httpx.AsyncClient(timeout=httpx.Timeout(connect=10.0, read=600.0, write=30.0, pool=10.0))
r: aredis.Redis | None = None


async def ensure_index():
    global r
    r = aredis.from_url(REDIS_URL, decode_responses=False)
    try:
        await r.execute_command(
            "FT.CREATE", INDEX_NAME, "ON", "HASH", "PREFIX", "1", "chatcache:",
            "SCHEMA",
            "model", "TAG",
            "user", "TAG",
            "ts", "NUMERIC", "SORTABLE",
            "embedding", "VECTOR", "FLAT", "6",
            "TYPE", "FLOAT32", "DIM", str(EMBED_DIM), "DISTANCE_METRIC", "COSINE",
        )
        log.info("index %s created", INDEX_NAME)
    except Exception as e:
        if "Index already exists" in str(e):
            log.info("index %s already exists", INDEX_NAME)
        else:
            log.warning("create index failed: %s", e)


@app.on_event("startup")
async def _startup():
    start_http_server(9091)
    await ensure_index()


def request_key(payload: dict[str, Any]) -> str:
    """L0 hash key（完全相同）"""
    h = hashlib.sha256(json.dumps(payload, sort_keys=True, ensure_ascii=False).encode()).hexdigest()
    return f"chatcache_l0:{h}"


def extract_query(payload: dict) -> str:
    """提取最后一条 user message 作为语义匹配的 key"""
    msgs = payload.get("messages", [])
    for m in reversed(msgs):
        if m.get("role") == "user":
            content = m.get("content")
            if isinstance(content, str):
                return content
            if isinstance(content, list):
                # multimodal: 取所有 text 拼接
                return " ".join(p.get("text", "") for p in content if isinstance(p, dict) and p.get("type") == "text")
    return ""


async def embed(text: str) -> np.ndarray | None:
    if not text or not EMBEDDING_TOKEN:
        return None
    try:
        resp = await client.post(
            EMBEDDING_API,
            headers={"Authorization": f"Bearer {EMBEDDING_TOKEN}"},
            json={"model": EMBEDDING_MODEL, "input": text[:8000]},
            timeout=10,
        )
        if resp.status_code != 200:
            return None
        data = resp.json()
        vec = np.array(data["data"][0]["embedding"], dtype=np.float32)
        return vec
    except Exception as e:
        log.warning("embed failed: %s", e)
        return None


async def l1_lookup(model: str, vec: np.ndarray) -> dict | None:
    """KNN 查最近的一条"""
    try:
        results = await r.execute_command(
            "FT.SEARCH", INDEX_NAME,
            f"@model:{{{model}}}=>[KNN 1 @embedding $BLOB AS dist]",
            "PARAMS", "2", "BLOB", vec.tobytes(),
            "RETURN", "2", "dist", "response",
            "DIALECT", "2", "LIMIT", "0", "1",
        )
        if results and len(results) >= 3:
            fields = results[2]
            kv = {fields[i].decode(): fields[i + 1] for i in range(0, len(fields), 2)}
            dist = float(kv.get("dist", 1))
            if dist <= THRESHOLD:
                resp_bytes = kv.get("response")
                return json.loads(resp_bytes) if resp_bytes else None
    except Exception as e:
        log.warning("l1 lookup failed: %s", e)
    return None


async def l1_save(model: str, query: str, vec: np.ndarray, response: dict) -> None:
    key = f"chatcache:{hashlib.sha256(query.encode()).hexdigest()[:16]}:{int(asyncio.get_event_loop().time() * 1000)}"
    try:
        await r.hset(key, mapping={
            "model": model,
            "query": query[:1000],
            "embedding": vec.tobytes(),
            "response": json.dumps(response, ensure_ascii=False),
            "ts": int(asyncio.get_event_loop().time()),
        })
        await r.expire(key, TTL)
    except Exception as e:
        log.warning("l1 save failed: %s", e)


@app.api_route("/v1/chat/completions", methods=["POST"])
async def chat_completions(request: Request):
    body = await request.body()
    try:
        payload = json.loads(body)
    except Exception:
        return JSONResponse({"error": "invalid json"}, status_code=400)

    c_total.inc()

    # streaming 不缓存（实现复杂，先支持 non-stream）
    if payload.get("stream"):
        return await _proxy(request, body)

    model = payload.get("model", "")
    if ENABLED_MODELS and model not in ENABLED_MODELS:
        return await _proxy(request, body)

    # L0
    l0_key = request_key(payload)
    cached = await r.get(l0_key)
    if cached:
        c_hits.labels(layer="l0").inc()
        log.info("L0 HIT model=%s", model)
        return JSONResponse(json.loads(cached), headers={"X-Cache": "HIT-L0"})

    # L1
    query = extract_query(payload)
    vec = await embed(query) if query else None
    if vec is not None:
        with h_lookup.time():
            cached = await l1_lookup(model, vec)
        if cached:
            c_hits.labels(layer="l1").inc()
            log.info("L1 HIT model=%s", model)
            return JSONResponse(cached, headers={"X-Cache": "HIT-L1"})

    # MISS → 透传上游
    c_misses.inc()
    upstream_resp = await _proxy_collect(request, body)
    if upstream_resp.status_code == 200:
        try:
            data = upstream_resp.json()
            await r.setex(l0_key, TTL, json.dumps(data, ensure_ascii=False))
            if vec is not None:
                await l1_save(model, query, vec, data)
        except Exception as e:
            log.warning("save cache failed: %s", e)

    return JSONResponse(
        upstream_resp.json() if upstream_resp.headers.get("content-type", "").startswith("application/json") else upstream_resp.text,
        status_code=upstream_resp.status_code,
        headers={"X-Cache": "MISS"},
    )


@app.api_route("/v1/{path:path}", methods=["GET", "POST", "PUT", "DELETE", "OPTIONS"])
async def passthrough(path: str, request: Request):
    body = await request.body()
    return await _proxy(request, body)


async def _proxy(request: Request, body: bytes):
    headers = {k: v for k, v in request.headers.items() if k.lower() not in ("host", "content-length")}
    if request.headers.get("accept", "").endswith("event-stream") or b'"stream":true' in body:
        upstream_req = client.build_request(
            request.method, f"{UPSTREAM}{request.url.path}",
            content=body, headers=headers, params=dict(request.query_params),
        )
        upstream_resp = await client.send(upstream_req, stream=True)
        async def gen():
            async for chunk in upstream_resp.aiter_bytes():
                yield chunk
        return StreamingResponse(gen(), status_code=upstream_resp.status_code,
                                 headers={k: v for k, v in upstream_resp.headers.items()
                                          if k.lower() not in ("content-encoding", "content-length", "transfer-encoding")},
                                 media_type=upstream_resp.headers.get("content-type"))
    r2 = await client.request(request.method, f"{UPSTREAM}{request.url.path}",
                              content=body, headers=headers, params=dict(request.query_params))
    return JSONResponse(r2.json() if "json" in r2.headers.get("content-type", "") else r2.text,
                        status_code=r2.status_code)


async def _proxy_collect(request: Request, body: bytes) -> httpx.Response:
    headers = {k: v for k, v in request.headers.items() if k.lower() not in ("host", "content-length")}
    return await client.request(request.method, f"{UPSTREAM}{request.url.path}",
                                content=body, headers=headers, params=dict(request.query_params))


@app.get("/healthz")
async def healthz():
    return {"ok": True}
