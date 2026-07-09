#!/usr/bin/env bash
set -euo pipefail

HOST_CADDY_REQUIRE_ROOT="${HOST_CADDY_REQUIRE_ROOT:-true}"
HOST_CADDY_STAGE_DIR="${HOST_CADDY_STAGE_DIR:-/tmp/reading-garden-host-caddy}"
HOST_CADDY_CONFIG_DIR="${HOST_CADDY_CONFIG_DIR:-/etc/caddy}"
HOST_CADDY_LOG_DIR="${HOST_CADDY_LOG_DIR:-/var/log/caddy}"
HOST_CADDY_SYSTEMD_OVERRIDE_DIR="${HOST_CADDY_SYSTEMD_OVERRIDE_DIR:-/etc/systemd/system/caddy.service.d}"
HOST_CADDY_SYSTEMD_OVERRIDE_SOURCE="${HOST_CADDY_SYSTEMD_OVERRIDE_SOURCE:-${HOST_CADDY_STAGE_DIR}/systemd/caddy.service.d/override.conf}"
HOST_CADDY_IMPORT_DOCKER_STATE="${HOST_CADDY_IMPORT_DOCKER_STATE:-false}"
HOST_CADDY_DOCKER_DATA_DIR="${HOST_CADDY_DOCKER_DATA_DIR:-/var/lib/docker/volumes/reading-garden_caddy_data/_data/caddy}"
HOST_CADDY_DOCKER_CONFIG_DIR="${HOST_CADDY_DOCKER_CONFIG_DIR:-/var/lib/docker/volumes/reading-garden_caddy_config/_data/caddy}"
HOST_CADDY_STATE_DATA_DIR="${HOST_CADDY_STATE_DATA_DIR:-/var/lib/caddy/.local/share/caddy}"
HOST_CADDY_STATE_CONFIG_DIR="${HOST_CADDY_STATE_CONFIG_DIR:-/var/lib/caddy/.config/caddy}"
HOST_CADDY_STATE_OWNER="${HOST_CADDY_STATE_OWNER-caddy:caddy}"

if [[ "$HOST_CADDY_REQUIRE_ROOT" == "true" && "${EUID}" -ne 0 ]]; then
    echo "bootstrap-host-caddy.sh must run as root" >&2
    exit 1
fi

if ! command -v caddy >/dev/null 2>&1; then
    echo "caddy command is required before bootstrapping host Caddy" >&2
    exit 1
fi

if [[ ! -f "${HOST_CADDY_STAGE_DIR}/Caddyfile" ]]; then
    echo "Missing staged host Caddy file: ${HOST_CADDY_STAGE_DIR}/Caddyfile" >&2
    exit 1
fi

install -d -m 755 \
    "${HOST_CADDY_CONFIG_DIR}" \
    "${HOST_CADDY_CONFIG_DIR}/common" \
    "${HOST_CADDY_CONFIG_DIR}/sites" \
    "${HOST_CADDY_CONFIG_DIR}/upstreams"

install -d -m 755 "${HOST_CADDY_LOG_DIR}"
touch \
    "${HOST_CADDY_LOG_DIR}/reading-garden-dev-access.log" \
    "${HOST_CADDY_LOG_DIR}/reading-garden-prod-access.log" \
    "${HOST_CADDY_LOG_DIR}/pawtogether-dev-access.log" \
    "${HOST_CADDY_LOG_DIR}/pawtogether-prod-access.log" \
    "${HOST_CADDY_LOG_DIR}/nooook-monitoring-access.log"
if id caddy >/dev/null 2>&1; then
    caddy_group="$(id -gn caddy)"
    chown caddy:"${caddy_group}" \
        "${HOST_CADDY_LOG_DIR}" \
        "${HOST_CADDY_LOG_DIR}/reading-garden-dev-access.log" \
        "${HOST_CADDY_LOG_DIR}/reading-garden-prod-access.log" \
        "${HOST_CADDY_LOG_DIR}/pawtogether-dev-access.log" \
        "${HOST_CADDY_LOG_DIR}/pawtogether-prod-access.log" \
        "${HOST_CADDY_LOG_DIR}/nooook-monitoring-access.log"
    chmod 644 \
        "${HOST_CADDY_LOG_DIR}/reading-garden-dev-access.log" \
        "${HOST_CADDY_LOG_DIR}/reading-garden-prod-access.log" \
        "${HOST_CADDY_LOG_DIR}/pawtogether-dev-access.log" \
        "${HOST_CADDY_LOG_DIR}/pawtogether-prod-access.log" \
        "${HOST_CADDY_LOG_DIR}/nooook-monitoring-access.log"
fi

install -m 644 "${HOST_CADDY_STAGE_DIR}/Caddyfile" "${HOST_CADDY_CONFIG_DIR}/Caddyfile"

if [[ -d "${HOST_CADDY_STAGE_DIR}/common" ]]; then
    find "${HOST_CADDY_STAGE_DIR}/common" -maxdepth 1 -type f -name '*.caddy' -print0 |
        while IFS= read -r -d '' file_path; do
            install -m 644 "$file_path" "${HOST_CADDY_CONFIG_DIR}/common/$(basename "$file_path")"
        done
fi

if [[ -d "${HOST_CADDY_STAGE_DIR}/sites" ]]; then
    find "${HOST_CADDY_STAGE_DIR}/sites" -maxdepth 1 -type f -name '*.caddy' -print0 |
        while IFS= read -r -d '' file_path; do
            install -m 644 "$file_path" "${HOST_CADDY_CONFIG_DIR}/sites/$(basename "$file_path")"
        done
fi

install_default_upstream() {
    local name="$1"
    local port="$2"
    local target="${HOST_CADDY_CONFIG_DIR}/upstreams/${name}.caddy"

    if [[ ! -f "$target" ]]; then
        printf 'reverse_proxy 127.0.0.1:%s\n' "$port" > "$target"
    fi
}

install_default_upstream reading-garden-dev 18090
install_default_upstream reading-garden-prod 18080
install_default_upstream pawtogether-dev 18100
install_default_upstream pawtogether-prod 18110

if [[ -f "${HOST_CADDY_SYSTEMD_OVERRIDE_SOURCE}" ]]; then
    install -d -m 755 "${HOST_CADDY_SYSTEMD_OVERRIDE_DIR}"
    install -m 644 "${HOST_CADDY_SYSTEMD_OVERRIDE_SOURCE}" "${HOST_CADDY_SYSTEMD_OVERRIDE_DIR}/override.conf"
    systemctl daemon-reload
fi

if [[ "$HOST_CADDY_IMPORT_DOCKER_STATE" == "true" ]]; then
    install -d -m 755 "${HOST_CADDY_STATE_DATA_DIR}" "${HOST_CADDY_STATE_CONFIG_DIR}"

    if [[ -d "${HOST_CADDY_DOCKER_DATA_DIR}" ]]; then
        cp -a "${HOST_CADDY_DOCKER_DATA_DIR}/." "${HOST_CADDY_STATE_DATA_DIR}/"
    fi

    if [[ -d "${HOST_CADDY_DOCKER_CONFIG_DIR}" ]]; then
        cp -a "${HOST_CADDY_DOCKER_CONFIG_DIR}/." "${HOST_CADDY_STATE_CONFIG_DIR}/"
    fi

    if [[ -n "$HOST_CADDY_STATE_OWNER" ]]; then
        chown -R "$HOST_CADDY_STATE_OWNER" "$(dirname "${HOST_CADDY_STATE_DATA_DIR}")" "$(dirname "${HOST_CADDY_STATE_CONFIG_DIR}")"
    fi
fi
