# ─────────────────────────────────────────────────────────────────────────────
# Dockerfile
# ─────────────────────────────────────────────────────────────────────────────
# Single image used by the API service

FROM python:3.11-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1

RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential curl && rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY pyproject.toml ./
# Install dependencies from pyproject.toml using Python 3.11's built-in tomllib
RUN python -c "import tomllib, subprocess; f = open('pyproject.toml', 'rb'); deps = tomllib.load(f)['project']['dependencies']; f.close(); subprocess.run(['pip', 'install'] + deps, check=True)"

# Optional: prepare a writable cache for models
RUN mkdir -p /root/.cache/huggingface

COPY app ./app

# Healthcheck for API service
HEALTHCHECK --interval=30s --timeout=3s CMD curl -fsS http://localhost:8000/health || exit 1