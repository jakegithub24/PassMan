#!/usr/bin/env bash
set -e

echo "=== PassMan Backend Production Startup ==="

# 1. Run database migrations / schema synchronization if DATABASE_URL is provided
if [ -n "$DATABASE_URL" ]; then
    echo "Running database schema initialization..."
    python apply_schema.py || echo "Warning: Schema migration returned non-zero, continuing startup..."
fi

# 2. Determine port and worker count
PORT="${PORT:-8000}"
WORKERS="${WEB_CONCURRENCY:-4}"

echo "Starting Uvicorn server on port ${PORT} with ${WORKERS} workers in ${ENVIRONMENT:-production} mode..."

exec uvicorn main:app \
    --host 0.0.0.0 \
    --port "${PORT}" \
    --workers "${WORKERS}" \
    --proxy-headers \
    --forwarded-allow-ips="*"
