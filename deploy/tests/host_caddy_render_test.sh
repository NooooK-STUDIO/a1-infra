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
grep -Fq 'output file /var/log/caddy/reading-garden-dev-access.log' deploy/host-caddy/sites/reading-garden-dev.caddy
grep -Fq 'output file /var/log/caddy/reading-garden-prod-access.log' deploy/host-caddy/sites/reading-garden-prod.caddy
grep -Fq 'nooook-monitoring.duckdns.org' deploy/host-caddy/sites/nooook-monitoring.caddy
grep -Fq 'reverse_proxy 127.0.0.1:3000' deploy/host-caddy/sites/nooook-monitoring.caddy
grep -Fq 'output file /var/log/caddy/nooook-monitoring-access.log' deploy/host-caddy/sites/nooook-monitoring.caddy
grep -Fq 'format json' deploy/host-caddy/sites/reading-garden-dev.caddy
grep -Fq 'format json' deploy/host-caddy/sites/reading-garden-prod.caddy
grep -Fq 'format json' deploy/host-caddy/sites/nooook-monitoring.caddy
grep -Fq 'HOST_CADDY_LOG_DIR="${HOST_CADDY_LOG_DIR:-/var/log/caddy}"' deploy/bootstrap-host-caddy.sh
grep -Fq 'reading-garden-dev-access.log' deploy/bootstrap-host-caddy.sh
grep -Fq 'reading-garden-prod-access.log' deploy/bootstrap-host-caddy.sh
grep -Fq 'nooook-monitoring-access.log' deploy/bootstrap-host-caddy.sh

if bash deploy/render-host-caddy-upstream.sh abc 2>/dev/null; then
    echo "non-numeric port must fail" >&2
    exit 1
fi

echo "PASS"
