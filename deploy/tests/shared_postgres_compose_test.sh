#!/usr/bin/env bash
set -euo pipefail

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

mkdir -p "$TMP_DIR/init"

CONFIG_OUTPUT="$(
  POSTGRES_SUPERUSER=postgres \
  POSTGRES_SUPERUSER_PASSWORD=secret \
  READING_GARDEN_PROD_APP_PASSWORD=prodapppass \
  READING_GARDEN_PROD_MIGRATOR_PASSWORD=prodmigratorpass \
  PAWTOGETHER_PROD_APP_PASSWORD=pawprodapppass \
  PAWTOGETHER_PROD_MIGRATOR_PASSWORD=pawprodmigratorpass \
  PAWTOGETHER_DEV_APP_PASSWORD=retiredpass \
  PAWTOGETHER_DEV_MIGRATOR_PASSWORD=retiredpass \
  POSTGRES_INIT_DIR="$TMP_DIR/init" \
  docker compose -f deploy/docker-compose.postgres-shared.yml config
)"

printf '%s\n' "$CONFIG_OUTPUT" | grep -q 'name: reading-garden-shared-backend'
printf '%s\n' "$CONFIG_OUTPUT" | grep -q 'shared-postgres'
printf '%s\n' "$CONFIG_OUTPUT" | grep -q 'READING_GARDEN_PROD_APP_PASSWORD:'
printf '%s\n' "$CONFIG_OUTPUT" | grep -q 'PAWTOGETHER_PROD_APP_PASSWORD:'
if printf '%s\n' "$CONFIG_OUTPUT" | grep -q 'PAWTOGETHER_DEV_'; then
  echo 'retired PawTogether environment remains in compose' >&2
  exit 1
fi

echo "PASS"
