#!/usr/bin/env bash
# check_env.sh — verify that this machine is even capable of running the stack

set -euo pipefail

fail() {
  echo "[fail] $1" >&2
  exit 1
}

ok() { echo "[ok] $1"; }

# ─────────────────────────────────────────────────────────────────────────────
# Tools we require
# ─────────────────────────────────────────────────────────────────────────────
check_cmd() {
  local cmd="$1"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    fail "Missing required tool: '$cmd'"
  else
    ok "$cmd is installed"
  fi
}

echo "Checking system requirements..."

# ─────────────────────────────────────────────────────────────────────────────
# Check if .env file exists
# ─────────────────────────────────────────────────────────────────────────────
if [ ! -f .env ]; then
  fail ".env file not found. Please copy env.example to .env first: cp env.example .env"
else
  ok ".env file exists"
fi

check_cmd docker
check_cmd docker compose
check_cmd curl
check_cmd jq

# ─────────────────────────────────────────────────────────────────────────────
# Docker daemon running?
# ─────────────────────────────────────────────────────────────────────────────
if ! docker info >/dev/null 2>&1; then
  fail "Docker daemon does not seem to be running"
else
  ok "Docker daemon running"
fi

# ─────────────────────────────────────────────────────────────────────────────
# Check if qdrant storage volume exists (optional)
# ─────────────────────────────────────────────────────────────────────────────
if docker volume ls | grep qdrant_storage; then
  ok "Docker volume 'qdrant_storage' exists"
else
  echo "[warn] Docker volume 'qdrant_storage' does not exist (will be auto-created)"
fi

# ─────────────────────────────────────────────────────────────────────────────
# Try pulling an image (ensure network + docker works)
# ─────────────────────────────────────────────────────────────────────────────
echo -n "Testing docker image pull network..."
if docker pull hello-world >/dev/null 2>&1; then
  echo " OK"
  ok "Network access for docker images works"
else
  fail "Cannot pull docker images (network/firewall issue?)"
fi

echo
echo "Everything looks good. Go ahead and start the system:"
echo "    ./build_up.sh"
