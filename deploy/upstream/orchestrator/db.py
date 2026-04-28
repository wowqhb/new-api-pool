"""DB schema + 连接"""
from __future__ import annotations
import asyncio
from contextlib import asynccontextmanager

import psycopg
from .settings import settings

DDL = """
CREATE TABLE IF NOT EXISTS tasks (
    id              BIGSERIAL PRIMARY KEY,
    recipe          TEXT        NOT NULL,                  -- gemini / claude / ...
    state           TEXT        NOT NULL DEFAULT 'pending',
    -- pending|email_ok|phone_ok|captcha_ok|registered|activated|key_extracted|imported|done|failed
    attempt         INT         NOT NULL DEFAULT 0,
    cost_usd        NUMERIC(10,4) NOT NULL DEFAULT 0,
    started_at      TIMESTAMPTZ DEFAULT NOW(),
    finished_at     TIMESTAMPTZ,
    last_step_at    TIMESTAMPTZ DEFAULT NOW(),
    worker_id       TEXT,
    parent_task_id  BIGINT,                                 -- 重试用
    fingerprint_id  BIGINT,                                 -- 引用 fingerprints.id
    proxy           TEXT,
    email           TEXT,
    phone           TEXT,
    error           TEXT,
    payload         JSONB       NOT NULL DEFAULT '{}'::jsonb
);
CREATE INDEX IF NOT EXISTS idx_tasks_state ON tasks(state);
CREATE INDEX IF NOT EXISTS idx_tasks_recipe ON tasks(recipe);
CREATE INDEX IF NOT EXISTS idx_tasks_started ON tasks(started_at DESC);

CREATE TABLE IF NOT EXISTS accounts (
    id              BIGSERIAL PRIMARY KEY,
    task_id         BIGINT REFERENCES tasks(id),
    recipe          TEXT NOT NULL,
    email           TEXT NOT NULL,
    password_vault  TEXT,                                   -- vault path
    phone           TEXT,
    country         TEXT,
    api_key_vault   TEXT,
    refresh_token_vault TEXT,
    access_token_vault TEXT,
    new_api_channel_id BIGINT,                              -- 入池后回填
    status          TEXT NOT NULL DEFAULT 'active',         -- active/dead/quarantine
    health_score    NUMERIC(5,2) DEFAULT 100,
    created_at      TIMESTAMPTZ DEFAULT NOW(),
    last_used_at    TIMESTAMPTZ,
    notes           TEXT
);
CREATE UNIQUE INDEX IF NOT EXISTS uq_accounts_email_recipe ON accounts(email, recipe);

CREATE TABLE IF NOT EXISTS fingerprints (
    id              BIGSERIAL PRIMARY KEY,
    account_id      BIGINT,                                 -- 软关联 accounts.id
    user_agent      TEXT,
    proxy           TEXT,
    cookies_json    TEXT,
    local_storage_json TEXT,
    geoip_country   TEXT,
    canvas_seed     TEXT,
    payload         JSONB       NOT NULL DEFAULT '{}'::jsonb,
    created_at      TIMESTAMPTZ DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_fingerprints_account ON fingerprints(account_id);

CREATE TABLE IF NOT EXISTS budget_ledger (
    id              BIGSERIAL PRIMARY KEY,
    task_id         BIGINT REFERENCES tasks(id),
    item            TEXT NOT NULL,                          -- sms / proxy / captcha / browser
    cost_usd        NUMERIC(10,4) NOT NULL,
    created_at      TIMESTAMPTZ DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_budget_at ON budget_ledger(created_at);
"""


async def init_db():
    async with await psycopg.AsyncConnection.connect(settings.pg_dsn) as conn:
        async with conn.cursor() as cur:
            await cur.execute(DDL)
        await conn.commit()


def init_db_sync():
    asyncio.run(init_db())


async def get_conn():
    return await psycopg.AsyncConnection.connect(settings.pg_dsn, autocommit=False)


@asynccontextmanager
async def db_cursor():
    """便捷 cursor 上下文，自动 commit/rollback。"""
    conn = await psycopg.AsyncConnection.connect(settings.pg_dsn, autocommit=False)
    try:
        async with conn.cursor() as cur:
            yield cur
        await conn.commit()
    except Exception:
        await conn.rollback()
        raise
    finally:
        await conn.close()
