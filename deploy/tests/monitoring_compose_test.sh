#!/usr/bin/env bash
set -euo pipefail

CONFIG_OUTPUT="$(
  GRAFANA_ADMIN_PASSWORD=secret-admin \
  NOOOOK_DISCORD_WEBHOOK_URL=https://example.invalid/nooook-discord-webhook \
  GRAFANA_DISCORD_DEV_WEBHOOK_URL=https://example.invalid/dev-discord-webhook \
  GRAFANA_DISCORD_PROD_WEBHOOK_URL=https://example.invalid/prod-discord-webhook \
  docker compose -f deploy/monitoring/docker-compose.monitoring.yml config
)"

assert_localhost_port() {
    local service="$1"
    local published_port="$2"
    local target_port="$3"

    if ! printf '%s\n' "$CONFIG_OUTPUT" | awk -v service="$service" -v published="$published_port" -v target="$target_port" '
        function reset_binding() {
            host_matches = 0
            target_matches = 0
            published_matches = 0
        }
        function check_binding() {
            if (in_service && in_ports && host_matches && target_matches && published_matches) {
                found = 1
            }
        }
        function leave_ports() {
            check_binding()
            reset_binding()
            in_ports = 0
        }
        function leave_service() {
            if (in_ports) {
                leave_ports()
            }
            in_service = 0
        }
        $0 == "  " service ":" {
            leave_service()
            in_service = 1
            next
        }
        /^  [A-Za-z0-9_-]+:$/ && in_service {
            leave_service()
        }
        in_service && /^    ports:$/ {
            in_ports = 1
            next
        }
        in_service && in_ports && /^    [A-Za-z0-9_-]+:/ {
            leave_ports()
        }
        in_service && in_ports && /^      - / {
            check_binding()
            reset_binding()
            next
        }
        in_service && in_ports && $1 == "host_ip:" && $2 == "127.0.0.1" {
            host_matches = 1
        }
        in_service && in_ports && $1 == "target:" && $2 == target {
            target_matches = 1
        }
        in_service && in_ports && $1 == "published:" && $2 == "\"" published "\"" {
            published_matches = 1
        }
        END {
            check_binding()
            exit found ? 0 : 1
        }
    '; then
        echo "${service} must publish ${published_port}->${target_port} on 127.0.0.1 only" >&2
        exit 1
    fi
}

assert_no_published_ports() {
    local service="$1"

    if printf '%s\n' "$CONFIG_OUTPUT" | awk -v service="$service" '
        $0 == "  " service ":" {
            in_service = 1
            next
        }
        /^  [A-Za-z0-9_-]+:$/ && in_service {
            in_service = 0
        }
        in_service && /^    ports:$/ {
            found = 1
        }
        END {
            exit found ? 0 : 1
        }
    '; then
        echo "${service} must not publish host ports" >&2
        exit 1
    fi
}

printf '%s\n' "$CONFIG_OUTPUT" | grep -q 'prometheus:'
printf '%s\n' "$CONFIG_OUTPUT" | grep -q 'grafana:'
printf '%s\n' "$CONFIG_OUTPUT" | grep -q 'loki:'
printf '%s\n' "$CONFIG_OUTPUT" | grep -q 'alloy:'
printf '%s\n' "$CONFIG_OUTPUT" | grep -q 'node-exporter:'
printf '%s\n' "$CONFIG_OUTPUT" | grep -q 'cadvisor:'
printf '%s\n' "$CONFIG_OUTPUT" | grep -q 'blackbox-exporter:'
printf '%s\n' "$CONFIG_OUTPUT" | grep -q 'container_name: a1-monitoring-loki'
printf '%s\n' "$CONFIG_OUTPUT" | grep -q 'container_name: a1-monitoring-alloy'
printf '%s\n' "$CONFIG_OUTPUT" | grep -q '/etc/grafana/provisioning'
printf '%s\n' "$CONFIG_OUTPUT" | grep -q '/var/lib/grafana/dashboards'
printf '%s\n' "$CONFIG_OUTPUT" | grep -q '/etc/loki/loki.yml'
printf '%s\n' "$CONFIG_OUTPUT" | grep -q '/etc/alloy/config.alloy'
printf '%s\n' "$CONFIG_OUTPUT" | grep -q '/var/run/docker.sock'
printf '%s\n' "$CONFIG_OUTPUT" | grep -q '/var/log/journal'
printf '%s\n' "$CONFIG_OUTPUT" | grep -q '/run/log/journal'
printf '%s\n' "$CONFIG_OUTPUT" | grep -q '/var/log/caddy'
printf '%s\n' "$CONFIG_OUTPUT" | grep -q 'network_mode: host'
printf '%s\n' "$CONFIG_OUTPUT" | grep -q 'GF_SERVER_HTTP_ADDR: 127.0.0.1'
printf '%s\n' "$CONFIG_OUTPUT" | grep -q 'GF_SERVER_ROOT_URL: https://nooook-monitoring.duckdns.org'
printf '%s\n' "$CONFIG_OUTPUT" | grep -q 'NOOOOK_DISCORD_WEBHOOK_URL: https://example.invalid/nooook-discord-webhook'
printf '%s\n' "$CONFIG_OUTPUT" | grep -q 'GRAFANA_DISCORD_DEV_WEBHOOK_URL: https://example.invalid/dev-discord-webhook'
printf '%s\n' "$CONFIG_OUTPUT" | grep -q 'GRAFANA_DISCORD_PROD_WEBHOOK_URL: https://example.invalid/prod-discord-webhook'

assert_no_published_ports prometheus
assert_no_published_ports grafana
assert_no_published_ports loki
assert_no_published_ports alloy
assert_localhost_port node-exporter 9100 9100
assert_localhost_port cadvisor 18082 8080
assert_localhost_port blackbox-exporter 9115 9115

if printf '%s\n' "$CONFIG_OUTPUT" | rg -q 'alertmanager:|postgres-exporter:|discord(app)?\.com/api/webhooks/[0-9]+'; then
    echo "deferred services and real Discord webhook URLs must not be present" >&2
    exit 1
fi

echo "PASS"
