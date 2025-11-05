#!/usr/bin/env bash
# check_stack.sh — verify tvrec API, Qdrant, and collection population

set -euo pipefail

# ── Config (override with env vars) ───────────────────────────────────────────
API_HOST="${API_HOST:-localhost}"
API_PORT="${API_PORT:-8000}"
QDRANT_HOST="${QDRANT_HOST:-localhost}"
QDRANT_PORT="${QDRANT_PORT:-6333}"
COLLECTION_NAME="${COLLECTION_NAME:-tvguide}"
MIN_POINTS="${MIN_POINTS:-1}"          # require at least this many points
MAX_WAIT_SEC="${MAX_WAIT_SEC:-300}"    # total wait budget
SLEEP_SEC="${SLEEP_SEC:-2}"

# ── Helpers ──────────────────────────────────────────────────────────────────
now() { date +%s; }

wait_for_http() {
  local name="$1" url="$2"
  local deadline=$(( $(now) + MAX_WAIT_SEC ))
  echo -n "[wait] $name at $url "
  until curl -sS -f -m 5 "$url" >/dev/null; do
    if (( $(now) >= deadline )); then
      echo
      echo "[fail] $name not reachable within ${MAX_WAIT_SEC}s"
      return 1
    fi
    echo -n "."
    sleep "$SLEEP_SEC"
  done
  echo " OK"
}

json_get() {  # requires jq
  jq -r "$1"
}

require_jq() {
  if ! command -v jq >/dev/null 2>&1; then
    echo "[fail] 'jq' is required. Install it and rerun." >&2
    exit 2
  fi
}

# ── Checks ───────────────────────────────────────────────────────────────────
require_jq

API_URL="http://${API_HOST}:${API_PORT}"
QDRANT_URL="http://${QDRANT_HOST}:${QDRANT_PORT}"

# 1) API up
wait_for_http "API"    "${API_URL}/health"
# double-check health payload
if [[ "$(curl -sS "${API_URL}/health" | json_get '.status')" != "ok" ]]; then
  echo "[fail] API /health returned non-ok payload"
  exit 1
fi
echo "[ok] API healthy"

# 2) Qdrant up
wait_for_http "Qdrant" "${QDRANT_URL}/collections"
echo "[ok] Qdrant reachable"

# 3) Collection exists
if ! curl -sS -f "${QDRANT_URL}/collections/${COLLECTION_NAME}" >/dev/null; then
  echo "[fail] Collection '${COLLECTION_NAME}' does not exist"
  exit 1
fi
echo "[ok] Collection '${COLLECTION_NAME}' exists"

# 4) Collection populated (exact count)
COUNT_JSON="$(curl -sS -f -X POST \
  -H 'Content-Type: application/json' \
  -d '{"exact":true}' \
  "${QDRANT_URL}/collections/${COLLECTION_NAME}/points/count")"

POINTS="$(printf '%s' "$COUNT_JSON" | json_get '.result.count')"

# Fallback to vectors size read (older qdrant) if count missing
if [[ "$POINTS" == "null" || -z "$POINTS" ]]; then
  INFO_JSON="$(curl -sS -f "${QDRANT_URL}/collections/${COLLECTION_NAME}")"
  POINTS="$(printf '%s' "$INFO_JSON" | json_get '.result.points_count // 0')"
fi

echo "[info] Points in '${COLLECTION_NAME}': ${POINTS}"

if [[ "$POINTS" =~ ^[0-9]+$ ]] && (( POINTS >= MIN_POINTS )); then
  echo "[ok] Collection populated (>= ${MIN_POINTS})"
  exit 0
else
  echo "[fail] Collection not populated enough (have ${POINTS}, need ${MIN_POINTS})"
  exit 3
fi
