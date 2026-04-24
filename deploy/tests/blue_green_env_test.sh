#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

assert_contains() {
    local file="$1"
    local pattern="$2"
    if ! grep -Fq "$pattern" "$file"; then
        echo "missing pattern '$pattern' in $file" >&2
        exit 1
    fi
}

ROUTE_RENDERER="${ROOT_DIR}/deploy/render-host-caddy-upstream.sh"
BOOTSTRAP_SCRIPT="${ROOT_DIR}/deploy/bootstrap-instance.sh"
BLUE_GREEN_SCRIPT="${ROOT_DIR}/deploy/blue-green-deploy.sh"

if [[ ! -x "$ROUTE_RENDERER" ]]; then
    echo "route renderer must be executable: $ROUTE_RENDERER" >&2
    exit 1
fi

if [[ ! -x "$BOOTSTRAP_SCRIPT" ]]; then
    echo "bootstrap script must be executable: $BOOTSTRAP_SCRIPT" >&2
    exit 1
fi

assert_contains "$BLUE_GREEN_SCRIPT" 'APP_CONTAINER_PREFIX="${APP_CONTAINER_PREFIX:-reading-garden}"'
assert_contains "$BLUE_GREEN_SCRIPT" 'HOST_CADDY_UPSTREAM_FILE="${HOST_CADDY_UPSTREAM_FILE:?HOST_CADDY_UPSTREAM_FILE is required}"'
assert_contains "$BLUE_GREEN_SCRIPT" 'APP_BLUE_HOST_PORT="${APP_BLUE_HOST_PORT:?APP_BLUE_HOST_PORT is required}"'
assert_contains "$BLUE_GREEN_SCRIPT" 'APP_GREEN_HOST_PORT="${APP_GREEN_HOST_PORT:?APP_GREEN_HOST_PORT is required}"'
assert_contains "$BLUE_GREEN_SCRIPT" 'CUTOVER_DRAIN_SECONDS="${CUTOVER_DRAIN_SECONDS:-30}"'
assert_contains "$BLUE_GREEN_SCRIPT" 'APP_STOP_TIMEOUT_SECONDS="${APP_STOP_TIMEOUT_SECONDS:-35}"'
assert_contains "$BLUE_GREEN_SCRIPT" 'sleep "$CUTOVER_DRAIN_SECONDS"'
assert_contains "$BLUE_GREEN_SCRIPT" 'docker compose -f "$COMPOSE_FILE" stop -t "$APP_STOP_TIMEOUT_SECONDS" "app-${ACTIVE}"'
assert_contains "$BLUE_GREEN_SCRIPT" 'ROUTE_RENDERER="${ROUTE_RENDERER:-${APP_DIR}/render-host-caddy-upstream.sh}"'
assert_contains "$BOOTSTRAP_SCRIPT" 'REMOTE_APP_DIR:-${APP_DIR:-}'
assert_contains "$BOOTSTRAP_SCRIPT" 'SHARED_POSTGRES_HOST="${SHARED_POSTGRES_HOST:-shared-postgres}"'
assert_contains "$BOOTSTRAP_SCRIPT" 'SHARED_POSTGRES_PORT="${SHARED_POSTGRES_PORT:-5432}"'

"$ROUTE_RENDERER" "18090" > "${TMP_DIR}/dev-upstream.caddy"
assert_contains "${TMP_DIR}/dev-upstream.caddy" "reverse_proxy 127.0.0.1:18090"

mkdir -p "${TMP_DIR}/source/secrets"
mkdir -p "${TMP_DIR}/target/secrets"
printf 'DB_HOST=postgres\n' > "${TMP_DIR}/source/.env"
printf '{}' > "${TMP_DIR}/source/secrets/firebase-service-account.json"
printf 'DB_HOST=target-postgres\n' > "${TMP_DIR}/target/.env"
printf '{"target":true}\n' > "${TMP_DIR}/target/secrets/firebase-service-account.json"

printf 'DB_NAME=reading_garden_dev\n' >> "${TMP_DIR}/target/.env"

SOURCE_APP_DIR="${TMP_DIR}/source" REMOTE_APP_DIR="${TMP_DIR}/target" "$BOOTSTRAP_SCRIPT"

assert_contains "${TMP_DIR}/target/.env" "DB_HOST=target-postgres"
assert_contains "${TMP_DIR}/target/secrets/firebase-service-account.json" '"target":true'
assert_contains "${TMP_DIR}/target/.runtime.env" "DB_HOST=shared-postgres"
assert_contains "${TMP_DIR}/target/.runtime.env" "SPRING_DATASOURCE_URL=jdbc:postgresql://shared-postgres:5432/reading_garden_dev"

echo "blue green env test passed"
