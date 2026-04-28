FROM python:3.12-slim
WORKDIR /app
RUN pip install --no-cache-dir psycopg[binary]==3.2.3 httpx==0.28.0 prometheus-client==0.21.0 tenacity==9.0.0
COPY tuner.py /app/
ENV PYTHONUNBUFFERED=1
CMD ["python", "/app/tuner.py"]
