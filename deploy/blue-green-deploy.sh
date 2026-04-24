#!/usr/bin/env bash
# Blue-Green deployment script for Reading Garden on Oracle A1
# Usage: IMAGE_REF=ghcr.io/.../...:tag ./blue-green-deploy.sh
set -euo pipefail

APP_DIR="${REMOTE_APP_DIR:-/opt/reading-garden}"
COMPOSE_FILE="${APP_DIR}/docker-compose.yml"
TIMEOUT_SECONDS="${TIMEOUT_SECONDS:-120}"
SMOKE_BASE_URL="${SMOKE_BASE_URL:-https://readinggarden.duckdns.org}"
APP_CONTAINER_PREFIX="${APP_CONTAINER_PREFIX:-reading-garden}"
APP_VOLUME_PREFIX="${APP_VOLUME_PREFIX:-$APP_CONTAINER_PREFIX}"
APP_HOST_DIR="${APP_HOST_DIR:-$APP_DIR}"
CUTOVER_DRAIN_SECONDS="${CUTOVER_DRAIN_SECONDS:-30}"
APP_STOP_TIMEOUT_SECONDS="${APP_STOP_TIMEOUT_SECONDS:-35}"
HOST_CADDY_UPSTREAM_FILE="${HOST_CADDY_UPSTREAM_FILE:?HOST_CADDY_UPSTREAM_FILE is required}"
APP_BLUE_HOST_PORT="${APP_BLUE_HOST_PORT:?APP_BLUE_HOST_PORT is required}"
APP_GREEN_HOST_PORT="${APP_GREEN_HOST_PORT:?APP_GREEN_HOST_PORT is required}"
HOST_CADDY_SUDO="${HOST_CADDY_SUDO:-sudo}"
HOST_CADDY_VALIDATE_CMD="${HOST_CADDY_VALIDATE_CMD:-caddy validate --config /etc/caddy/Caddyfile --adapter caddyfile}"
HOST_CADDY_RELOAD_CMD="${HOST_CADDY_RELOAD_CMD:-caddy reload --address unix//var/lib/caddy/caddy-admin.sock --config /etc/caddy/Caddyfile --adapter caddyfile}"
ROUTE_RENDERER="${ROUTE_RENDERER:-${APP_DIR}/render-host-caddy-upstream.sh}"

run_host_caddy_cmd() {
    local command="$1"

    if [[ -n "$HOST_CADDY_SUDO" ]]; then
        "$HOST_CADDY_SUDO" env PATH="$PATH" bash -lc "$command"
    else
        env PATH="$PATH" bash -lc "$command"
    fi
}

reload_caddy() {
    run_host_caddy_cmd "$HOST_CADDY_VALIDATE_CMD"
    run_host_caddy_cmd "$HOST_CADDY_RELOAD_CMD"
}

route_file_has_upstream() {
    local file_path="$1"
    local target_host_port="$2"

    grep -q "reverse_proxy 127.0.0.1:${target_host_port}" "$file_path"
}

route_file_current_upstream() {
    local file_path="$1"

    sed -nE 's/.*reverse_proxy 127\.0\.0\.1:([0-9]+).*/\1/p' "$file_path" | head -n 1
}

render_route_file_for_target() {
    local target_host_port="$1"
    local output_path="$2"

    "$ROUTE_RENDERER" "$target_host_port" > "$output_path"

    if ! route_file_has_upstream "$output_path" "$target_host_port"; then
        echo "ERROR: Failed to render host Caddy upstream for port ${target_host_port}" >&2
        return 1
    fi
}

write_route_file_in_place() {
    local source_path="$1"

    run_host_caddy_cmd "install -m 644 '$source_path' '$HOST_CADDY_UPSTREAM_FILE'"
}

switch_proxy_target() {
    local target_host_port="$1"
    local backup
    local candidate
    local had_previous=false
    local previous_target

    backup="$(mktemp)"
    candidate="$(mktemp)"
    previous_target=""

    if run_host_caddy_cmd "test -f '$HOST_CADDY_UPSTREAM_FILE'"; then
        had_previous=true
        if ! run_host_caddy_cmd "cp '$HOST_CADDY_UPSTREAM_FILE' '$backup'"; then
            rm -f "$backup" "$candidate"
            return 1
        fi
        previous_target="$(route_file_current_upstream "$backup" || true)"
    fi

    if ! render_route_file_for_target "$target_host_port" "$candidate"; then
        rm -f "$backup" "$candidate"
        return 1
    fi

    if ! write_route_file_in_place "$candidate"; then
        rm -f "$backup" "$candidate"
        return 1
    fi

    if reload_caddy; then
        rm -f "$backup" "$candidate"
        return 0
    fi

    if [[ "$had_previous" == true ]]; then
        write_route_file_in_place "$backup" || true
        if [[ -n "$previous_target" ]]; then
            reload_caddy || true
        fi
    else
        run_host_caddy_cmd "rm -f '$HOST_CADDY_UPSTREAM_FILE'" || true
    fi
    rm -f "$backup" "$candidate"
    return 1
}

running_container_exists() {
    local name="$1"

    docker ps --format '{{.Names}}' | grep -qx "$name"
}

cd "$APP_DIR"

export IMAGE_REF="${IMAGE_REF:?IMAGE_REF is required}"
export APP_HOST_DIR
export APP_CONTAINER_PREFIX
export APP_VOLUME_PREFIX

if ! running_container_exists "${APP_CONTAINER_PREFIX}-blue" && ! running_container_exists "${APP_CONTAINER_PREFIX}-green"; then
    echo "=== First deployment: starting blue ==="

    docker compose -f "$COMPOSE_FILE" pull
    docker compose -f "$COMPOSE_FILE" up --pull never -d app-blue

    echo "=== Waiting for app-blue to become healthy ==="
    deadline=$((SECONDS + TIMEOUT_SECONDS))
    until docker inspect --format='{{.State.Health.Status}}' "${APP_CONTAINER_PREFIX}-blue" 2>/dev/null | grep -q "healthy"; do
        if (( SECONDS >= deadline )); then
            echo "ERROR: app-blue did not become healthy within ${TIMEOUT_SECONDS}s" >&2
            docker compose -f "$COMPOSE_FILE" logs app-blue --tail 50
            exit 1
        fi
        sleep 2
    done

    switch_proxy_target "${APP_BLUE_HOST_PORT}"

    TIMEOUT_SECONDS=30 "${APP_DIR}/cutover-smoke-check.sh" "${SMOKE_BASE_URL}"
    echo "=== First deployment complete: app-blue is active ==="
    docker system prune -f || true
    exit 0
fi

current_target="$(route_file_current_upstream "$HOST_CADDY_UPSTREAM_FILE" || true)"
case "$current_target" in
    "$APP_GREEN_HOST_PORT")
        ACTIVE="green"
        STANDBY="blue"
        TARGET_HOST_PORT="$APP_BLUE_HOST_PORT"
        ;;
    *)
        ACTIVE="blue"
        STANDBY="green"
        TARGET_HOST_PORT="$APP_GREEN_HOST_PORT"
        ;;
esac

echo "=== Current active: $ACTIVE, deploying to: $STANDBY ==="

docker compose -f "$COMPOSE_FILE" pull "app-${STANDBY}"

if [[ "$STANDBY" = "green" ]]; then
    docker compose -f "$COMPOSE_FILE" --profile green up --pull never -d "app-${STANDBY}"
else
    docker compose -f "$COMPOSE_FILE" up --pull never -d "app-${STANDBY}"
fi

echo "=== Waiting for app-${STANDBY} to become healthy ==="
deadline=$((SECONDS + TIMEOUT_SECONDS))
until docker inspect --format='{{.State.Health.Status}}' "${APP_CONTAINER_PREFIX}-${STANDBY}" 2>/dev/null | grep -q "healthy"; do
    if (( SECONDS >= deadline )); then
        echo "ERROR: app-${STANDBY} did not become healthy within ${TIMEOUT_SECONDS}s" >&2
        docker compose -f "$COMPOSE_FILE" logs "app-${STANDBY}" --tail 50
        docker compose -f "$COMPOSE_FILE" stop "app-${STANDBY}"
        exit 1
    fi
    sleep 2
done
echo "=== app-${STANDBY} is healthy ==="

switch_proxy_target "${TARGET_HOST_PORT}"
echo "=== Host Caddy switched to app-${STANDBY} ==="

if ! TIMEOUT_SECONDS=30 "${APP_DIR}/cutover-smoke-check.sh" "${SMOKE_BASE_URL}"; then
    echo "ERROR: Smoke check failed, rolling back to app-${ACTIVE}" >&2
    if [[ "$ACTIVE" == "green" ]]; then
        switch_proxy_target "${APP_GREEN_HOST_PORT}"
    else
        switch_proxy_target "${APP_BLUE_HOST_PORT}"
    fi
    docker compose -f "$COMPOSE_FILE" stop "app-${STANDBY}"
    exit 1
fi

echo "=== Draining app-${ACTIVE} for ${CUTOVER_DRAIN_SECONDS}s ==="
sleep "$CUTOVER_DRAIN_SECONDS"

docker compose -f "$COMPOSE_FILE" stop -t "$APP_STOP_TIMEOUT_SECONDS" "app-${ACTIVE}"
echo "=== Deployment complete: app-${STANDBY} is now active ==="

docker system prune -f || true
