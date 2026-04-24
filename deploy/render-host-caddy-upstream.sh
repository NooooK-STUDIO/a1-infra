#!/usr/bin/env bash
set -euo pipefail

TARGET_HOST_PORT="${1:?usage: render-host-caddy-upstream.sh <host-port>}"

case "$TARGET_HOST_PORT" in
    ''|*[!0-9]*)
        echo "host port must be numeric: $TARGET_HOST_PORT" >&2
        exit 1
        ;;
esac

cat <<EOF
reverse_proxy 127.0.0.1:${TARGET_HOST_PORT} {
    header_up Host {host}
    header_up X-Real-IP {remote_host}
    header_up X-Forwarded-For {remote_host}
    header_up X-Forwarded-Proto {scheme}
}
EOF
