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

load_optional_secret_env() {
    local var_name="$1"
    local secret_path="$2"

    if [[ -n "${!var_name:-}" ]]; then
        return 0
    fi

    if [[ -f "$secret_path" ]]; then
        export "$var_name=$(tr -d '\r\n' < "$secret_path")"
    fi
}

if [[ ! -f "$POSTGRES_COMPOSE_FILE" ]]; then
    echo "Missing shared PostgreSQL compose file: $POSTGRES_COMPOSE_FILE" >&2
    exit 1
fi

export POSTGRES_SUPERUSER="${POSTGRES_SUPERUSER:-postgres}"
load_secret_env POSTGRES_SUPERUSER_PASSWORD "${POSTGRES_SECRETS_DIR}/postgres_superuser.password"
load_optional_secret_env READING_GARDEN_PROD_APP_PASSWORD "${POSTGRES_SECRETS_DIR}/reading_garden_prod_app.password"
load_optional_secret_env READING_GARDEN_PROD_MIGRATOR_PASSWORD "${POSTGRES_SECRETS_DIR}/reading_garden_prod_migrator.password"
load_optional_secret_env READING_GARDEN_DEV_APP_PASSWORD "${POSTGRES_SECRETS_DIR}/reading_garden_dev_app.password"
load_optional_secret_env READING_GARDEN_DEV_MIGRATOR_PASSWORD "${POSTGRES_SECRETS_DIR}/reading_garden_dev_migrator.password"
load_optional_secret_env PAWTOGETHER_PROD_APP_PASSWORD "${POSTGRES_SECRETS_DIR}/pawtogether_prod_app.password"
load_optional_secret_env PAWTOGETHER_PROD_MIGRATOR_PASSWORD "${POSTGRES_SECRETS_DIR}/pawtogether_prod_migrator.password"
load_optional_secret_env PAWTOGETHER_DEV_APP_PASSWORD "${POSTGRES_SECRETS_DIR}/pawtogether_dev_app.password"
load_optional_secret_env PAWTOGETHER_DEV_MIGRATOR_PASSWORD "${POSTGRES_SECRETS_DIR}/pawtogether_dev_migrator.password"
load_optional_secret_env POSTGRES_EXPORTER_PASSWORD "${POSTGRES_SECRETS_DIR}/postgres_exporter.password"

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

ensure_app_database() {
    local db_name="$1"
    local app_role="$2"
    local app_password="$3"
    local migrator_role="$4"
    local migrator_password="$5"

    if [[ -z "$app_password" || -z "$migrator_password" ]]; then
        echo "Skipping ${db_name}; password env is not set."
        return 0
    fi

    docker exec -i \
        -e APP_DB_NAME="$db_name" \
        -e APP_ROLE="$app_role" \
        -e APP_PASSWORD="$app_password" \
        -e APP_MIGRATOR_ROLE="$migrator_role" \
        -e APP_MIGRATOR_PASSWORD="$migrator_password" \
        "$POSTGRES_CONTAINER_NAME" \
        bash -seu <<'BASH'
sql_quote() {
    printf '%s' "$1" | sed "s/'/''/g"
}

app_password_sql="$(sql_quote "$APP_PASSWORD")"
migrator_password_sql="$(sql_quote "$APP_MIGRATOR_PASSWORD")"

psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" <<SQL
DO \$\$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = '${APP_ROLE}') THEN
        CREATE ROLE ${APP_ROLE} LOGIN PASSWORD '${app_password_sql}';
    ELSE
        ALTER ROLE ${APP_ROLE} WITH LOGIN PASSWORD '${app_password_sql}';
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = '${APP_MIGRATOR_ROLE}') THEN
        CREATE ROLE ${APP_MIGRATOR_ROLE} LOGIN PASSWORD '${migrator_password_sql}';
    ELSE
        ALTER ROLE ${APP_MIGRATOR_ROLE} WITH LOGIN PASSWORD '${migrator_password_sql}';
    END IF;
END
\$\$;
SQL

if [[ "$(psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" -tAc "SELECT 1 FROM pg_database WHERE datname = '${APP_DB_NAME}'")" != "1" ]]; then
    psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" -c "CREATE DATABASE ${APP_DB_NAME} OWNER ${APP_MIGRATOR_ROLE};"
fi

psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$APP_DB_NAME" <<SQL
REVOKE CREATE ON SCHEMA public FROM PUBLIC;
GRANT USAGE ON SCHEMA public TO ${APP_ROLE};
ALTER DEFAULT PRIVILEGES FOR ROLE ${APP_MIGRATOR_ROLE} IN SCHEMA public
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO ${APP_ROLE};
ALTER DEFAULT PRIVILEGES FOR ROLE ${APP_MIGRATOR_ROLE} IN SCHEMA public
GRANT USAGE, SELECT ON SEQUENCES TO ${APP_ROLE};
SQL
BASH
}

ensure_app_database reading_garden_prod reading_garden_prod_app "${READING_GARDEN_PROD_APP_PASSWORD:-}" reading_garden_prod_migrator "${READING_GARDEN_PROD_MIGRATOR_PASSWORD:-}"
ensure_app_database reading_garden_dev reading_garden_dev_app "${READING_GARDEN_DEV_APP_PASSWORD:-}" reading_garden_dev_migrator "${READING_GARDEN_DEV_MIGRATOR_PASSWORD:-}"
ensure_app_database pawtogether_prod pawtogether_prod_app "${PAWTOGETHER_PROD_APP_PASSWORD:-}" pawtogether_prod_migrator "${PAWTOGETHER_PROD_MIGRATOR_PASSWORD:-}"
ensure_app_database pawtogether_dev pawtogether_dev_app "${PAWTOGETHER_DEV_APP_PASSWORD:-}" pawtogether_dev_migrator "${PAWTOGETHER_DEV_MIGRATOR_PASSWORD:-}"

if [[ -n "${POSTGRES_EXPORTER_PASSWORD:-}" ]]; then
    docker exec -i \
        -e POSTGRES_EXPORTER_PASSWORD="$POSTGRES_EXPORTER_PASSWORD" \
        "$POSTGRES_CONTAINER_NAME" \
        psql -v ON_ERROR_STOP=1 -v postgres_exporter_password="$POSTGRES_EXPORTER_PASSWORD" --username "$POSTGRES_SUPERUSER" --dbname postgres <<'SQL'
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'reading_garden_monitoring') THEN
        CREATE ROLE reading_garden_monitoring LOGIN;
    END IF;
END
$$;
ALTER ROLE reading_garden_monitoring WITH LOGIN PASSWORD :'postgres_exporter_password';
GRANT pg_monitor TO reading_garden_monitoring;
SQL
else
    echo "Skipping PostgreSQL monitoring role setup because POSTGRES_EXPORTER_PASSWORD is not set."
fi
