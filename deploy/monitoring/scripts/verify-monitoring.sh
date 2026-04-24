#!/usr/bin/env bash
set -euo pipefail

MONITORING_DIR="${MONITORING_DIR:-/opt/infra/monitoring}"
COMPOSE_FILE="${MONITORING_DIR}/docker-compose.yml"
ENV_FILE="${MONITORING_DIR}/.env"
GRAFANA_URL="${GRAFANA_URL:-http://127.0.0.1:3000}"
PROMETHEUS_URL="${PROMETHEUS_URL:-http://127.0.0.1:9090}"
DEV_BASE_URL="${DEV_BASE_URL:-https://readinggarden-dev.duckdns.org}"
PROD_BASE_URL="${PROD_BASE_URL:-https://readinggarden.duckdns.org}"

read_env_file() {
  local key="$1"

  awk -F= -v key="$key" '$1 == key { sub(/^[^=]*=/, ""); print; exit }' "$ENV_FILE"
}

GRAFANA_ADMIN_USER="${GRAFANA_ADMIN_USER:-$(read_env_file GRAFANA_ADMIN_USER)}"
GRAFANA_ADMIN_USER="${GRAFANA_ADMIN_USER:-admin}"
GRAFANA_ADMIN_PASSWORD="${GRAFANA_ADMIN_PASSWORD:-$(read_env_file GRAFANA_ADMIN_PASSWORD)}"

if [ -z "$GRAFANA_ADMIN_PASSWORD" ]; then
  echo "GRAFANA_ADMIN_PASSWORD is required in the environment or ${ENV_FILE}" >&2
  exit 1
fi

docker compose -f "$COMPOSE_FILE" --env-file "$ENV_FILE" ps

assert_prometheus_query_has_result() {
  local query="$1"
  local label="$2"

  if ! curl -fsS -G --data-urlencode "query=${query}" "${PROMETHEUS_URL}/api/v1/query" | grep -Fq '"result":[{'; then
    echo "Prometheus query returned no active result for ${label}: ${query}" >&2
    exit 1
  fi
}

curl -fsS "${PROMETHEUS_URL}/-/ready" >/dev/null
assert_prometheus_query_has_result 'up{job="prometheus"} == 1' 'prometheus'
assert_prometheus_query_has_result 'sum(up{job="reading-garden-dev-app"}) > 0' 'reading-garden-dev-app'
assert_prometheus_query_has_result 'sum(up{job="reading-garden-prod-app"}) > 0' 'reading-garden-prod-app'
assert_prometheus_query_has_result 'up{job="caddy"} == 1' 'caddy'
assert_prometheus_query_has_result 'up{job="node-exporter"} == 1' 'node-exporter'
assert_prometheus_query_has_result 'up{job="cadvisor"} == 1' 'cadvisor'
assert_prometheus_query_has_result 'up{job="blackbox-http"} == 1' 'blackbox-http'

curl -fsS -u "${GRAFANA_ADMIN_USER}:${GRAFANA_ADMIN_PASSWORD}" \
  "${GRAFANA_URL}/api/datasources/uid/prometheus/health" | grep -Fq '"status":"OK"'

curl -fsS "${DEV_BASE_URL}/api/health" | grep -Fq '"UP"'
curl -fsS "${DEV_BASE_URL}/v3/api-docs" >/dev/null
curl -fsS "${PROD_BASE_URL}/api/health" | grep -Fq '"UP"'
curl -fsS "${PROD_BASE_URL}/v3/api-docs" >/dev/null

echo "PASS: monitoring verification completed"
