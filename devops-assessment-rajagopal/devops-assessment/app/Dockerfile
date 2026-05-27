# ─── Stage 1: build dependencies ─────────────────────────────────────────────
FROM python:3.12-slim AS builder

WORKDIR /build
COPY requirements.txt .
RUN pip install --no-cache-dir --prefix=/install -r requirements.txt

# ─── Stage 2: lean runtime image ─────────────────────────────────────────────
FROM python:3.12-slim

# Non-root user for security
RUN addgroup --system app && adduser --system --ingroup app app

WORKDIR /app
COPY --from=builder /install /usr/local
COPY app.py .

# Create log directory
RUN mkdir -p /app/logs && chown -R app:app /app

USER app

ENV PORT=80 \
    APP_ENV=production \
    PYTHONUNBUFFERED=1

EXPOSE 80

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD python -c "import urllib.request; urllib.request.urlopen('http://localhost:${PORT}/health')"

CMD ["python", "app.py"]
