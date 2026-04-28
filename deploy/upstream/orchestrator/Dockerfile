FROM python:3.12-slim

# 系统依赖（Camoufox / Playwright）
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl wget unzip xvfb fonts-liberation libnss3 libatk1.0-0 libatk-bridge2.0-0 \
    libcups2 libdbus-1-3 libdrm2 libxkbcommon0 libgtk-3-0 libgbm1 libpango-1.0-0 \
    libcairo2 libasound2 libxcomposite1 libxdamage1 libxfixes3 libxrandr2 libxshmfence1 \
    ca-certificates xauth tini procps \
  && rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY orchestrator/requirements.txt /app/orchestrator/requirements.txt
RUN pip install --no-cache-dir -r /app/orchestrator/requirements.txt
RUN python -m camoufox fetch || true   # 下载 Camoufox 二进制（需联网）

COPY orchestrator /app/orchestrator
COPY adapters /app/adapters
COPY recipes /app/recipes
COPY browser /app/browser
COPY budget /app/budget

ENV PYTHONUNBUFFERED=1 PYTHONPATH=/app

ENTRYPOINT ["tini", "-g", "--"]
CMD ["python", "-m", "orchestrator.main"]
