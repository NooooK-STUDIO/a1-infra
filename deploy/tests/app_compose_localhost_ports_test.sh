#!/usr/bin/env bash
set -euo pipefail

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

mkdir -p "$TMP_DIR/secrets" "$TMP_DIR/data"
touch "$TMP_DIR/.env"
touch "$TMP_DIR/.runtime.env"
printf '{}\n' > "$TMP_DIR/secrets/firebase-service-account.json"

assert_port_binding() {
    local published_port="$1"
    local target_port="$2"

    if ! printf '%s\n' "$CONFIG_OUTPUT" | awk -v published="$published_port" -v target="$target_port" '
        function reset_binding() {
            host_matches = 0
            target_matches = 0
            published_matches = 0
        }
        function check_binding() {
            if (host_matches && target_matches && published_matches) {
                found = 1
            }
        }
        /^      - mode: ingress$/ {
            check_binding()
            reset_binding()
            in_binding = 1
            next
        }
        in_binding && /^[^ ]/ {
            check_binding()
            in_binding = 0
            reset_binding()
            next
        }
        in_binding && $1 == "host_ip:" && $2 == "127.0.0.1" {
            host_matches = 1
        }
        in_binding && $1 == "target:" && $2 == target {
            target_matches = 1
        }
        in_binding && $1 == "published:" && $2 == "\"" published "\"" {
            published_matches = 1
        }
        in_binding && $1 == "protocol:" {
            check_binding()
            in_binding = 0
            reset_binding()
        }
        END {
            check_binding()
            exit found ? 0 : 1
        }
    '; then
        echo "missing localhost binding for published port ${published_port} -> target ${target_port}" >&2
        exit 1
    fi
}

CONFIG_OUTPUT="$(
  IMAGE_REF=ghcr.io/example/reading-garden:test \
  APP_HOST_DIR="$TMP_DIR" \
  APP_CONTAINER_PREFIX=reading-garden-prod \
  APP_VOLUME_PREFIX=reading-garden-prod \
  APP_BLUE_HOST_PORT=18080 \
  APP_GREEN_HOST_PORT=18081 \
  APP_BLUE_MANAGEMENT_HOST_PORT=19080 \
  APP_GREEN_MANAGEMENT_HOST_PORT=19081 \
  docker compose --profile green -f deploy/docker-compose.oci.yml config
)"

assert_port_binding 18080 8080
assert_port_binding 18081 8080
assert_port_binding 19080 8081
assert_port_binding 19081 8081
printf '%s\n' "$CONFIG_OUTPUT" | grep -q 'name: reading-garden-shared-backend'

if printf '%s\n' "$CONFIG_OUTPUT" | grep -q 'postgres:'; then
    echo "app compose must not define postgres service" >&2
    exit 1
fi

if printf '%s\n' "$CONFIG_OUTPUT" | grep -q 'host.docker.internal=host-gateway'; then
    echo "app compose must not rely on host-gateway for postgres access" >&2
    exit 1
fi

echo "PASS"
