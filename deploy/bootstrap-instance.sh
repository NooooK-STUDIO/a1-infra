#!/usr/bin/env bash
set -euo pipefail

SOURCE_APP_DIR="${SOURCE_APP_DIR:-/opt/reading-garden}"
APP_DIR="${REMOTE_APP_DIR:-${APP_DIR:-}}"

if [[ -z "$APP_DIR" ]]; then
    echo "REMOTE_APP_DIR or APP_DIR is required" >&2
    exit 1
fi

mkdir -p \
    "$APP_DIR" \
    "$APP_DIR/backups" \
    "$APP_DIR/data/images/multipart-temp" \
    "$APP_DIR/secrets"

if [[ ! -f "$APP_DIR/.env" ]]; then
    echo "Missing required env file: $APP_DIR/.env" >&2
    exit 1
fi

if [[ ! -f "$APP_DIR/secrets/firebase-service-account.json" ]]; then
    echo "Missing required secret file: $APP_DIR/secrets/firebase-service-account.json" >&2
    exit 1
fi

read_env_value() {
    local key="$1"
    local raw

    raw="$(awk -F= -v lookup_key="$key" '
        $0 ~ "^[[:space:]]*" lookup_key "=" {
            print substr($0, index($0, "=") + 1)
        }
    ' "$APP_DIR/.env" | tail -n 1)"
    raw="${raw%$'\r'}"

    if [[ "${raw:0:1}" == '"' && "${raw: -1}" == '"' ]]; then
        raw="${raw:1:${#raw}-2}"
    elif [[ "${raw:0:1}" == "'" && "${raw: -1}" == "'" ]]; then
        raw="${raw:1:${#raw}-2}"
    fi

    printf '%s' "$raw"
}

DB_NAME_VALUE="$(read_env_value "DB_NAME")"

if [[ -z "$DB_NAME_VALUE" ]]; then
    datasource_url="$(read_env_value "SPRING_DATASOURCE_URL")"
    DB_NAME_VALUE="${datasource_url##*/}"
    DB_NAME_VALUE="${DB_NAME_VALUE%%\?*}"
fi

if [[ -z "$DB_NAME_VALUE" ]]; then
    echo "Missing required DB_NAME in $APP_DIR/.env" >&2
    exit 1
fi

SHARED_POSTGRES_HOST="${SHARED_POSTGRES_HOST:-shared-postgres}"
SHARED_POSTGRES_PORT="${SHARED_POSTGRES_PORT:-5432}"

cat > "$APP_DIR/.runtime.env" <<EOF
DB_HOST=${SHARED_POSTGRES_HOST}
DB_PORT=${SHARED_POSTGRES_PORT}
SPRING_DATASOURCE_URL=jdbc:postgresql://${SHARED_POSTGRES_HOST}:${SHARED_POSTGRES_PORT}/${DB_NAME_VALUE}
SPRING_FLYWAY_URL=jdbc:postgresql://${SHARED_POSTGRES_HOST}:${SHARED_POSTGRES_PORT}/${DB_NAME_VALUE}
EOF
