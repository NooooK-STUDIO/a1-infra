#!/usr/bin/env bash
set -euo pipefail

BASE_URL="${1:-${BASE_URL:-http://127.0.0.1:8080}}"
TIMEOUT_SECONDS="${TIMEOUT_SECONDS:-60}"
SLEEP_SECONDS="${SLEEP_SECONDS:-2}"

deadline=$((SECONDS + TIMEOUT_SECONDS))

until health_body="$(curl -fsS "${BASE_URL}/api/health")"; do
  if (( SECONDS >= deadline )); then
    echo "health check timed out after ${TIMEOUT_SECONDS}s" >&2
    exit 1
  fi
  sleep "${SLEEP_SECONDS}"
done

printf '%s' "${health_body}" | python3 -c 'import json, sys
data = json.load(sys.stdin)
assert data.get("status") == "UP", data
'

until curl -fsS "${BASE_URL}/v3/api-docs" >/dev/null; do
  if (( SECONDS >= deadline )); then
    echo "api-docs check timed out after ${TIMEOUT_SECONDS}s" >&2
    exit 1
  fi
  sleep "${SLEEP_SECONDS}"
done

echo "cutover smoke passed"
