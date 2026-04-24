#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT
APP_HOST_DIR="${TMP_DIR}/reading-garden-dev"

mkdir -p "${APP_HOST_DIR}/secrets" "${APP_HOST_DIR}/data"
printf 'DB_PASSWORD=test-password\n' > "${APP_HOST_DIR}/.env"
printf 'DB_HOST=shared-postgres\n' > "${APP_HOST_DIR}/.runtime.env"
printf '{}' > "${APP_HOST_DIR}/secrets/firebase-service-account.json"

assert_file() {
    local path="$1"
    if [[ ! -f "$path" ]]; then
        echo "missing file: $path" >&2
        exit 1
    fi
}

assert_contains() {
    local file="$1"
    local pattern="$2"
    if ! grep -Fq -- "$pattern" "$file"; then
        echo "missing pattern '$pattern' in $file" >&2
        exit 1
    fi
}

APP_COMPOSE="${ROOT_DIR}/deploy/docker-compose.oci.yml"

assert_file "$APP_COMPOSE"
assert_file "${ROOT_DIR}/deploy/bootstrap-host-caddy.sh"
assert_file "${ROOT_DIR}/deploy/render-host-caddy-upstream.sh"
assert_file "${ROOT_DIR}/deploy/host-caddy/Caddyfile"
assert_file "${ROOT_DIR}/deploy/host-caddy/sites/reading-garden-prod.caddy"
assert_file "${ROOT_DIR}/deploy/host-caddy/sites/reading-garden-dev.caddy"
assert_file "${ROOT_DIR}/deploy/docker-compose.postgres-shared.yml"
assert_file "${ROOT_DIR}/deploy/bootstrap-shared-postgres.sh"
assert_file "${ROOT_DIR}/deploy/postgres/init/10-create-app-databases.sh"

IMAGE_REF="ghcr.io/example/reading-garden:test" \
APP_HOST_DIR="${APP_HOST_DIR}" \
APP_CONTAINER_PREFIX="reading-garden-dev" \
APP_VOLUME_PREFIX="reading-garden-dev" \
APP_STOP_GRACE_PERIOD="35s" \
APP_BLUE_HOST_PORT="18090" \
APP_GREEN_HOST_PORT="18091" \
APP_BLUE_MANAGEMENT_HOST_PORT="19090" \
APP_GREEN_MANAGEMENT_HOST_PORT="19091" \
docker compose --profile green -f "$APP_COMPOSE" config > "${TMP_DIR}/app-compose.yaml"

if grep -Fq "reading-garden-caddy" "${TMP_DIR}/app-compose.yaml"; then
    echo "app compose should not include caddy service" >&2
    exit 1
fi

assert_contains "${TMP_DIR}/app-compose.yaml" "container_name: reading-garden-dev-blue"
assert_contains "${TMP_DIR}/app-compose.yaml" "container_name: reading-garden-dev-green"
assert_contains "${TMP_DIR}/app-compose.yaml" "stop_grace_period: 35s"
assert_contains "${TMP_DIR}/app-compose.yaml" "published: \"18090\""
assert_contains "${TMP_DIR}/app-compose.yaml" "published: \"18091\""
assert_contains "${TMP_DIR}/app-compose.yaml" "published: \"19090\""
assert_contains "${TMP_DIR}/app-compose.yaml" "published: \"19091\""
assert_contains "${TMP_DIR}/app-compose.yaml" "DB_HOST: shared-postgres"
assert_contains "${TMP_DIR}/app-compose.yaml" "name: reading-garden-shared-backend"
assert_contains "${TMP_DIR}/app-compose.yaml" "source: ${APP_HOST_DIR}/data"
assert_contains "${TMP_DIR}/app-compose.yaml" "source: ${APP_HOST_DIR}/secrets/firebase-service-account.json"
if grep -Fq "container_name: reading-garden-dev-db" "${TMP_DIR}/app-compose.yaml"; then
    echo "app compose should not include postgres service" >&2
    exit 1
fi
if grep -Fq "host.docker.internal=host-gateway" "${TMP_DIR}/app-compose.yaml"; then
    echo "app compose should not use host-gateway bridge access" >&2
    exit 1
fi
if grep -Fq "name: reading-garden-public" "${TMP_DIR}/app-compose.yaml"; then
    echo "app compose should not depend on public docker network" >&2
    exit 1
fi

echo "deploy layout test passed"
