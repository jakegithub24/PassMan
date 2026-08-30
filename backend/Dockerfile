# Multi-stage production Dockerfile for PassMan FastAPI Backend (Task 13.1 / Render / Fly.io)
FROM python:3.13-slim AS builder

WORKDIR /app

# Install build dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    libpq-dev \
    curl \
    && rm -rf /var/lib/apt/lists/*

# Install uv package manager
COPY --from=ghcr.io/astral-sh/uv:latest /uv /bin/uv

# Install Python dependencies using uv
COPY pyproject.toml uv.lock* requirements.txt* ./
RUN uv pip install --system --no-cache -r requirements.txt || uv pip install --system --no-cache .

# Final runtime image
FROM python:3.13-slim AS runner

WORKDIR /app

# Install runtime libpq for PostgreSQL
RUN apt-get update && apt-get install -y --no-install-recommends \
    libpq5 \
    curl \
    && rm -rf /var/lib/apt/lists/*

# Copy installed site-packages from builder
COPY --from=builder /usr/local/lib/python3.13/site-packages /usr/local/lib/python3.13/site-packages
COPY --from=builder /usr/local/bin /usr/local/bin

# Create non-root user for security
RUN groupadd -g 1001 passman && \
    useradd -u 1001 -g passman -s /bin/bash -m passman

# Copy application source code
COPY . /app

# Ensure proper permissions
RUN chmod +x /app/start.sh 2>/dev/null || true && \
    chown -R passman:passman /app

USER passman

# Expose default HTTP port
EXPOSE 8000

ENV PORT=8000 \
    PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    ENVIRONMENT=production

# Health check matching FastAPI root endpoint
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD curl -f http://localhost:${PORT}/ || exit 1

ENTRYPOINT ["/bin/bash", "/app/start.sh"]
