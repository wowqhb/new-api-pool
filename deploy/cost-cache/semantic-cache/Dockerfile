FROM python:3.12-slim
WORKDIR /app
RUN pip install --no-cache-dir fastapi==0.115.0 uvicorn[standard]==0.32.0 httpx==0.28.0 \
    redis==5.2.0 numpy==2.1.3 prometheus-client==0.21.0
COPY *.py /app/
ENV PYTHONUNBUFFERED=1
CMD ["uvicorn", "cache:app", "--host", "0.0.0.0", "--port", "8081"]
