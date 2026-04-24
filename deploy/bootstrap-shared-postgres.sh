#!/usr/bin/env bash
set -euo pipefail

POSTGRES_STACK_DIR="${POSTGRES_STACK_DIR:-/opt/infra/postgresql}"
POSTGRES_COMPOSE_FILE="${POSTGRES_COMPOSE_FILE:-${POSTGRES_STACK_DIR}/docker-compose.yml}"
POSTGRES_PROJECT_DIR="${POSTGRES_PROJECT_DIR:-$(dirname "$POSTGRES_COMPOSE_FILE")}"
POSTGRES_CONTAINER_NAME="${POSTGRES_CONTAINER_NAME:-shared-postgres}"
POSTGRES_BOOTSTRAP_TIMEOUT_SECONDS="${POSTGRES_BOOTSTRAP_TIMEOUT_SECONDS:-120}"
SHARED_BACKEND_NETWORK_NAME="${SHARED_BACKEND_NETWORK_NAME:-reading-garden-shared-backend}"
POSTGRES_INIT_DIR="${POSTGRES_INIT_DIR:-${POSTGRES_STACK_DIR}/init}"
POSTGRES_SECRETS_DIR="${POSTGRES_SECRETS_DIR:-${POSTGRES_STACK_DIR}/secrets}"

load_secret_env() {
    local var_name="$1"
    local secret_path="$2"

    if [[ -n "${!var_name:-}" ]]; then
        return 0
    fi

    if [[ ! -f "$secret_path" ]]; then
        echo "Missing required secret file: $secret_path" >&2
        exit 1
    fi

    export "$var_name=$(tr -d '\r\n' < "$secret_path")"
}

if [[ ! -f "$POSTGRES_COMPOSE_FILE" ]]; then
    echo "Missing shared PostgreSQL compose file: $POSTGRES_COMPOSE_FILE" >&2
    exit 1
fi

export POSTGRES_SUPERUSER="${POSTGRES_SUPERUSER:-postgres}"
load_secret_env POSTGRES_SUPERUSER_PASSWORD "${POSTGRES_SECRETS_DIR}/postgres_superuser.password"
load_secret_env READING_GARDEN_PROD_APP_PASSWORD "${POSTGRES_SECRETS_DIR}/reading_garden_prod_app.password"
load_secret_env READING_GARDEN_PROD_MIGRATOR_PASSWORD "${POSTGRES_SECRETS_DIR}/reading_garden_prod_migrator.password"
load_secret_env READING_GARDEN_DEV_APP_PASSWORD "${POSTGRES_SECRETS_DIR}/reading_garden_dev_app.password"
load_secret_env READING_GARDEN_DEV_MIGRATOR_PASSWORD "${POSTGRES_SECRETS_DIR}/reading_garden_dev_migrator.password"

if ! docker network inspect "$SHARED_BACKEND_NETWORK_NAME" >/dev/null 2>&1; then
    docker network create "$SHARED_BACKEND_NETWORK_NAME" >/dev/null
fi

cd "$POSTGRES_PROJECT_DIR"
docker compose -f "$POSTGRES_COMPOSE_FILE" up -d

deadline=$((SECONDS + POSTGRES_BOOTSTRAP_TIMEOUT_SECONDS))
until docker inspect --format='{{.State.Health.Status}}' "$POSTGRES_CONTAINER_NAME" 2>/dev/null | grep -q "healthy"; do
    if (( SECONDS >= deadline )); then
        echo "ERROR: ${POSTGRES_CONTAINER_NAME} did not become healthy within ${POSTGRES_BOOTSTRAP_TIMEOUT_SECONDS}s" >&2
        docker compose -f "$POSTGRES_COMPOSE_FILE" logs postgres --tail 50 || true
        exit 1
    fi
    sleep 2
done
