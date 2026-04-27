#!/usr/bin/env bash
set -euo pipefail

MONITORING_DIR="${MONITORING_DIR:-/opt/infra/monitoring}"
COMPOSE_FILE="${MONITORING_DIR}/docker-compose.yml"
ENV_FILE="${MONITORING_DIR}/.env"
GRAFANA_URL="${GRAFANA_URL:-http://127.0.0.1:3000}"
PROMETHEUS_URL="${PROMETHEUS_URL:-http://127.0.0.1:9090}"
DEV_BASE_URL="${DEV_BASE_URL:-https://readinggarden-dev.duckdns.org}"
VERIFY_TIMEOUT_SECONDS="${VERIFY_TIMEOUT_SECONDS:-60}"

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

wait_for_http() {
  local url="$1"
  local label="$2"
  local deadline=$((SECONDS + VERIFY_TIMEOUT_SECONDS))

  until curl -fsS "$url" >/dev/null; do
    if (( SECONDS >= deadline )); then
      echo "${label} did not become ready within ${VERIFY_TIMEOUT_SECONDS}s: ${url}" >&2
      exit 1
    fi
    sleep 2
  done
}

assert_prometheus_query_has_result() {
  local query="$1"
  local label="$2"
  local deadline=$((SECONDS + VERIFY_TIMEOUT_SECONDS))

  until curl -fsS -G --data-urlencode "query=${query}" "${PROMETHEUS_URL}/api/v1/query" | grep -Fq '"result":[{'; do
    if (( SECONDS >= deadline )); then
      echo "Prometheus query returned no active result within ${VERIFY_TIMEOUT_SECONDS}s for ${label}: ${query}" >&2
      exit 1
    fi
    sleep 2
  done
}

wait_for_grafana_datasource() {
  local deadline=$((SECONDS + VERIFY_TIMEOUT_SECONDS))

  until curl -fsS -u "${GRAFANA_ADMIN_USER}:${GRAFANA_ADMIN_PASSWORD}" \
    "${GRAFANA_URL}/api/datasources/uid/prometheus/health" | grep -Fq '"status":"OK"'; do
    if (( SECONDS >= deadline )); then
      echo "Grafana Prometheus datasource did not become healthy within ${VERIFY_TIMEOUT_SECONDS}s" >&2
      exit 1
    fi
    sleep 2
  done
}

wait_for_http "${PROMETHEUS_URL}/-/ready" "Prometheus readiness"
assert_prometheus_query_has_result 'up{job="prometheus"} == 1' 'prometheus'
assert_prometheus_query_has_result 'sum(up{job="reading-garden-dev-app"}) > 0' 'reading-garden-dev-app'
assert_prometheus_query_has_result 'up{job="caddy"} == 1' 'caddy'
assert_prometheus_query_has_result 'up{job="node-exporter"} == 1' 'node-exporter'
assert_prometheus_query_has_result 'up{job="cadvisor"} == 1' 'cadvisor'
assert_prometheus_query_has_result 'up{job="blackbox-http"} == 1' 'blackbox-http'

wait_for_grafana_datasource

curl -fsS "${DEV_BASE_URL}/api/health" | grep -Fq '"UP"'
curl -fsS "${DEV_BASE_URL}/v3/api-docs" >/dev/null

echo "PASS: monitoring verification completed"
