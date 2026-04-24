#!/usr/bin/env bash
set -euo pipefail

BLUE_GREEN_SCRIPT="deploy/blue-green-deploy.sh"

required=(
  'HOST_CADDY_UPSTREAM_FILE="${HOST_CADDY_UPSTREAM_FILE:?HOST_CADDY_UPSTREAM_FILE is required}"'
  'APP_BLUE_HOST_PORT="${APP_BLUE_HOST_PORT:?APP_BLUE_HOST_PORT is required}"'
  'APP_GREEN_HOST_PORT="${APP_GREEN_HOST_PORT:?APP_GREEN_HOST_PORT is required}"'
  'HOST_CADDY_SUDO="${HOST_CADDY_SUDO:-sudo}"'
  'HOST_CADDY_RELOAD_CMD="${HOST_CADDY_RELOAD_CMD:-caddy reload --address unix//var/lib/caddy/caddy-admin.sock --config /etc/caddy/Caddyfile --adapter caddyfile}"'
  'ROUTE_RENDERER="${ROUTE_RENDERER:-${APP_DIR}/render-host-caddy-upstream.sh}"'
  'docker compose -f "$COMPOSE_FILE" up --pull never -d app-blue'
  'docker compose -f "$COMPOSE_FILE" --profile green up --pull never -d "app-${STANDBY}"'
  'docker compose -f "$COMPOSE_FILE" up --pull never -d "app-${STANDBY}"'
)

for pattern in "${required[@]}"; do
    if ! grep -Fq "$pattern" "$BLUE_GREEN_SCRIPT"; then
        echo "missing required env reference: $pattern" >&2
        exit 1
    fi
done

if grep -Fq 'docker compose -f "$EDGE_COMPOSE_FILE" exec -T caddy' "$BLUE_GREEN_SCRIPT"; then
    echo "edge container exec must be removed" >&2
    exit 1
fi

echo "PASS"
