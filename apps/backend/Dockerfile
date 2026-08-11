FROM python:3.13-slim AS builder

WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir --target=/app/deps -r requirements.txt

FROM python:3.13-slim

# セキュリティ: non-root ユーザーで実行
RUN groupadd -r appuser && useradd -r -g appuser appuser

WORKDIR /app
COPY --from=builder /app/deps /app/deps
COPY main.py .

ENV PYTHONPATH=/app/deps
ENV PYTHONUNBUFFERED=1
EXPOSE 8080

USER appuser
CMD ["python", "-m", "uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8080"]
