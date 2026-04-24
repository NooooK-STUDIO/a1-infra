#!/usr/bin/env bash
set -euo pipefail

OUTPUT="$(bash deploy/render-host-caddy-upstream.sh 18080)"
CONFIG_OUTPUT="$(cat deploy/host-caddy/Caddyfile)"
printf '%s\n' "$OUTPUT" | grep -q 'reverse_proxy 127.0.0.1:18080'
printf '%s\n' "$CONFIG_OUTPUT" | grep -q 'admin unix//var/lib/caddy/caddy-admin.sock'
printf '%s\n' "$CONFIG_OUTPUT" | grep -q 'metrics {'
printf '%s\n' "$CONFIG_OUTPUT" | grep -q 'per_host'
printf '%s\n' "$CONFIG_OUTPUT" | grep -q 'http://127.0.0.1:2019'
printf '%s\n' "$CONFIG_OUTPUT" | grep -q 'metrics /metrics'

if bash deploy/render-host-caddy-upstream.sh abc 2>/dev/null; then
    echo "non-numeric port must fail" >&2
    exit 1
fi

echo "PASS"
