#!/usr/bin/env bash
set -euo pipefail

sql_quote() {
    printf '%s' "$1" | sed "s/'/''/g"
}

ensure_database() {
    local db_name="$1"
    local app_role="$2"
    local app_password="$3"
    local migrator_role="$4"
    local migrator_password="$5"
    local app_password_sql
    local migrator_password_sql

    if [[ -z "$app_password" || -z "$migrator_password" ]]; then
        echo "Skipping ${db_name}; password env is not set."
        return 0
    fi

    app_password_sql="$(sql_quote "$app_password")"
    migrator_password_sql="$(sql_quote "$migrator_password")"

    psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" <<SQL
DO \$\$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = '${app_role}') THEN
        CREATE ROLE ${app_role} LOGIN PASSWORD '${app_password_sql}';
    ELSE
        ALTER ROLE ${app_role} WITH LOGIN PASSWORD '${app_password_sql}';
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = '${migrator_role}') THEN
        CREATE ROLE ${migrator_role} LOGIN PASSWORD '${migrator_password_sql}';
    ELSE
        ALTER ROLE ${migrator_role} WITH LOGIN PASSWORD '${migrator_password_sql}';
    END IF;
END
\$\$;
SQL

    if [[ "$(psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" -tAc "SELECT 1 FROM pg_database WHERE datname = '${db_name}'")" != "1" ]]; then
        psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" -c "CREATE DATABASE ${db_name} OWNER ${migrator_role};"
    fi

    psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$db_name" <<SQL
REVOKE CREATE ON SCHEMA public FROM PUBLIC;
GRANT USAGE ON SCHEMA public TO ${app_role};
ALTER DEFAULT PRIVILEGES FOR ROLE ${migrator_role} IN SCHEMA public
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO ${app_role};
ALTER DEFAULT PRIVILEGES FOR ROLE ${migrator_role} IN SCHEMA public
GRANT USAGE, SELECT ON SEQUENCES TO ${app_role};
SQL
}

ensure_database reading_garden_prod reading_garden_prod_app "${READING_GARDEN_PROD_APP_PASSWORD:-}" reading_garden_prod_migrator "${READING_GARDEN_PROD_MIGRATOR_PASSWORD:-}"
ensure_database reading_garden_dev reading_garden_dev_app "${READING_GARDEN_DEV_APP_PASSWORD:-}" reading_garden_dev_migrator "${READING_GARDEN_DEV_MIGRATOR_PASSWORD:-}"
ensure_database pawtogether_prod pawtogether_prod_app "${PAWTOGETHER_PROD_APP_PASSWORD:-}" pawtogether_prod_migrator "${PAWTOGETHER_PROD_MIGRATOR_PASSWORD:-}"
ensure_database pawtogether_dev pawtogether_dev_app "${PAWTOGETHER_DEV_APP_PASSWORD:-}" pawtogether_dev_migrator "${PAWTOGETHER_DEV_MIGRATOR_PASSWORD:-}"
