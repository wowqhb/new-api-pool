"""集中配置（pydantic-settings）"""
from __future__ import annotations
from pydantic import Field
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env.upstream", extra="ignore")

    role: str = Field(default="orchestrator", validation_alias="ROLE")
    worker_id: str = Field(default="w0", validation_alias="WORKER_ID")

    pg_dsn: str = Field(validation_alias="PG_DSN")
    redis_url: str = Field(validation_alias="REDIS_URL")

    minio_endpoint: str = Field(validation_alias="MINIO_ENDPOINT")
    minio_user: str = Field(validation_alias="MINIO_ROOT_USER")
    minio_pass: str = Field(validation_alias="MINIO_ROOT_PASSWORD")
    minio_bucket: str = Field(default="upstream", validation_alias="MINIO_BUCKET")

    vault_addr: str = Field(default="", validation_alias="VAULT_ADDR")
    vault_token: str = Field(default="", validation_alias="VAULT_TOKEN")

    new_api_base: str = Field(default="", validation_alias="NEW_API_BASE")
    new_api_admin_token: str = Field(default="", validation_alias="NEW_API_ADMIN_TOKEN")

    proxy_provider: str = Field(default="", validation_alias="PROXY_PROVIDER")
    proxy_user: str = Field(default="", validation_alias="PROXY_USER")
    proxy_pass: str = Field(default="", validation_alias="PROXY_PASS")
    proxy_host: str = Field(default="", validation_alias="PROXY_HOST")
    proxy_port: int = Field(default=0, validation_alias="PROXY_PORT")
    proxy_country: str = Field(default="US", validation_alias="PROXY_COUNTRY")
    proxy_url: str = Field(
        default="",
        validation_alias="PROXY_URL",
        description="完整代理 URL，例如 http://user-{sid}-zone-resi:pass@gate.example.com:7777",
    )

    profile_root: str = Field(
        default="/data/profiles",
        validation_alias="PROFILE_ROOT",
        description="浏览器 profile 与录像存放目录",
    )

    email_provider: str = Field(default="cloudflare", validation_alias="EMAIL_PROVIDER")
    cf_email_api_token: str = Field(default="", validation_alias="CF_EMAIL_API_TOKEN")
    cf_email_domain: str = Field(default="", validation_alias="CF_EMAIL_DOMAIN")
    cf_email_destination: str = Field(default="", validation_alias="CF_EMAIL_DESTINATION")
    imap_host: str = Field(default="", validation_alias="IMAP_HOST")
    imap_user: str = Field(default="", validation_alias="IMAP_USER")
    imap_pass: str = Field(default="", validation_alias="IMAP_PASS")
    imap_port: int = Field(default=993, validation_alias="IMAP_PORT")

    sms_provider: str = Field(default="sms-activate", validation_alias="SMS_PROVIDER")
    sms_api_key: str = Field(default="", validation_alias="SMS_API_KEY")
    sms_default_country: str = Field(default="183", validation_alias="SMS_DEFAULT_COUNTRY")

    captcha_provider: str = Field(default="capsolver", validation_alias="CAPTCHA_PROVIDER")
    captcha_api_key: str = Field(default="", validation_alias="CAPTCHA_API_KEY")

    daily_budget_usd: float = Field(default=50.0, validation_alias="DAILY_BUDGET_USD")
    max_cost_per_account: float = Field(default=2.0, validation_alias="MAX_COST_PER_ACCOUNT_USD")
    failure_rate_stop: float = Field(default=0.30, validation_alias="FAILURE_RATE_STOP")
    max_workers: int = Field(default=3, validation_alias="MAX_CONCURRENT_WORKERS")

    telegram_bot_token: str = Field(default="", validation_alias="TELEGRAM_BOT_TOKEN")
    telegram_chat_id: str = Field(default="", validation_alias="TELEGRAM_CHAT_ID")

    log_level: str = Field(default="INFO", validation_alias="LOG_LEVEL")


settings = Settings()
