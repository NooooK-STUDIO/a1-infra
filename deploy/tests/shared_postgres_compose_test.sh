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
  READING_GARDEN_DEV_APP_PASSWORD=devapppass \
  READING_GARDEN_DEV_MIGRATOR_PASSWORD=devmigratorpass \
  POSTGRES_INIT_DIR="$TMP_DIR/init" \
  docker compose -f deploy/docker-compose.postgres-shared.yml config
)"

printf '%s\n' "$CONFIG_OUTPUT" | grep -q 'name: reading-garden-shared-backend'
printf '%s\n' "$CONFIG_OUTPUT" | grep -q 'shared-postgres'

echo "PASS"
