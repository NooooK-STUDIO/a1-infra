#!/usr/bin/env bash
set -euo pipefail

MONITORING_DIR="${MONITORING_DIR:-/opt/infra/monitoring}"
COMPOSE_FILE="${MONITORING_DIR}/docker-compose.yml"
ENV_FILE="${MONITORING_DIR}/.env"
GRAFANA_URL="${GRAFANA_URL:-http://127.0.0.1:3000}"
PROMETHEUS_URL="${PROMETHEUS_URL:-http://127.0.0.1:9090}"
LOKI_URL="${LOKI_URL:-http://127.0.0.1:3100}"
DEV_BASE_URL="${DEV_BASE_URL:-https://readinggarden-dev.duckdns.org}"
VERIFY_TIMEOUT_SECONDS="${VERIFY_TIMEOUT_SECONDS:-60}"
EXPECTED_ALERT_RULES=(
  DevAppMetricsDown
  DevExternalHealthDown
  Dev5xxRateHigh
  DevAvgLatencyHigh
  HikariPendingConnections
  ProdAppMetricsDown
  ProdExternalHealthDown
  Prod5xxRateHigh
  ProdAvgLatencyHigh
  ProdHikariPendingConnections
  CaddyMetricsDown
  CaddyRequestLatencyHigh
  CaddyReloadFailed
  ContainerExporterDown
  HostDiskAlmostFull
  HostMemoryHigh
  MonitoringTargetDown
)

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

assert_loki_query_has_result() {
  local query="$1"
  local label="$2"
  local deadline=$((SECONDS + VERIFY_TIMEOUT_SECONDS))

  until curl -fsS -G \
    --data-urlencode "query=${query}" \
    --data-urlencode "limit=1" \
    "${LOKI_URL}/loki/api/v1/query_range" | grep -Fq '"result":[{'; do
    if (( SECONDS >= deadline )); then
      echo "Loki query returned no log streams within ${VERIFY_TIMEOUT_SECONDS}s for ${label}: ${query}" >&2
      exit 1
    fi
    sleep 2
  done
}

response_has_expected_alert_rules() {
  local response="$1"
  local expected_alert

  printf '%s' "$response" | grep -Fq '"status":"success"' || return 1
  printf '%s' "$response" | grep -Fq '"health":"ok"' || return 1

  for expected_alert in "${EXPECTED_ALERT_RULES[@]}"; do
    printf '%s' "$response" | grep -Fq "\"name\":\"${expected_alert}\"" || return 1
  done
}

wait_for_prometheus_rules() {
  local deadline=$((SECONDS + VERIFY_TIMEOUT_SECONDS))
  local response

  until response="$(curl -fsS "${PROMETHEUS_URL}/api/v1/rules")" &&
    response_has_expected_alert_rules "$response"; do
    if (( SECONDS >= deadline )); then
      echo "Prometheus did not load the expected phase 1 alert rules within ${VERIFY_TIMEOUT_SECONDS}s" >&2
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

wait_for_grafana_loki_datasource() {
  local deadline=$((SECONDS + VERIFY_TIMEOUT_SECONDS))

  until curl -fsS -u "${GRAFANA_ADMIN_USER}:${GRAFANA_ADMIN_PASSWORD}" \
    "${GRAFANA_URL}/api/datasources/uid/loki/health" | grep -Fq '"status":"OK"'; do
    if (( SECONDS >= deadline )); then
      echo "Grafana Loki datasource did not become healthy within ${VERIFY_TIMEOUT_SECONDS}s" >&2
      exit 1
    fi
    sleep 2
  done
}

wait_for_grafana_dashboard_panels() {
  local deadline=$((SECONDS + VERIFY_TIMEOUT_SECONDS))
  local dev_dashboard_url="${GRAFANA_URL}/api/dashboards/uid/reading-garden-dev-overview"
  local prod_dashboard_url="${GRAFANA_URL}/api/dashboards/uid/reading-garden-prod-overview"
  local response

  until response="$(curl -fsS -u "${GRAFANA_ADMIN_USER}:${GRAFANA_ADMIN_PASSWORD}" "$dev_dashboard_url")" &&
    printf '%s' "$response" | grep -Fq "Dev Avg Latency" &&
    printf '%s' "$response" | grep -Fq "Caddy p95 Duration" &&
    printf '%s' "$response" | grep -Fq "Host CPU Usage Percent" &&
    printf '%s' "$response" | grep -Fq "Hikari Active Connections" &&
    response="$(curl -fsS -u "${GRAFANA_ADMIN_USER}:${GRAFANA_ADMIN_PASSWORD}" "$prod_dashboard_url")" &&
    printf '%s' "$response" | grep -Fq "Prod Avg Latency" &&
    printf '%s' "$response" | grep -Fq "Prod 5xx Rate" &&
    printf '%s' "$response" | grep -Fq "Hikari Active Connections"; do
    if (( SECONDS >= deadline )); then
      echo "Grafana app dashboards did not load expected panels within ${VERIFY_TIMEOUT_SECONDS}s" >&2
      exit 1
    fi
    sleep 2
  done
}

wait_for_grafana_logs_dashboard_panels() {
  local deadline=$((SECONDS + VERIFY_TIMEOUT_SECONDS))
  local dashboard_url="${GRAFANA_URL}/api/dashboards/uid/reading-garden-logs"
  local response

  until response="$(curl -fsS -u "${GRAFANA_ADMIN_USER}:${GRAFANA_ADMIN_PASSWORD}" "$dashboard_url")" &&
    printf '%s' "$response" | grep -Fq "App Container Logs" &&
    printf '%s' "$response" | grep -Fq "Prod App Logs" &&
    printf '%s' "$response" | grep -Fq "Dev App Logs" &&
    printf '%s' "$response" | grep -Fq "Caddy Systemd Logs" &&
    printf '%s' "$response" | grep -Fq "Prod Caddy Access Logs" &&
    printf '%s' "$response" | grep -Fq "Dev Caddy Access Logs"; do
    if (( SECONDS >= deadline )); then
      echo "Grafana logs dashboard did not load expected panels within ${VERIFY_TIMEOUT_SECONDS}s" >&2
      exit 1
    fi
    sleep 2
  done
}

wait_for_grafana_alerting() {
  local deadline=$((SECONDS + VERIFY_TIMEOUT_SECONDS))
  local contact_points_url="${GRAFANA_URL}/api/v1/provisioning/contact-points"
  local policies_url="${GRAFANA_URL}/api/v1/provisioning/policies"
  local alert_rule_uids=(
    grafana-dev-external-health
    grafana-prod-external-health
    grafana-dev-app-metrics
    grafana-prod-app-metrics
    grafana-caddy-metrics
    grafana-host-disk-full
  )
  local response
  local rule_uid
  local all_rules_loaded

  until response="$(curl -fsS -u "${GRAFANA_ADMIN_USER}:${GRAFANA_ADMIN_PASSWORD}" "$contact_points_url")" &&
    printf '%s' "$response" | grep -Fq '"name":"reading-garden-discord"' &&
    printf '%s' "$response" | grep -Fq '"type":"discord"' &&
    response="$(curl -fsS -u "${GRAFANA_ADMIN_USER}:${GRAFANA_ADMIN_PASSWORD}" "$policies_url")" &&
    printf '%s' "$response" | grep -Fq '"receiver":"reading-garden-discord"'; do
    if (( SECONDS >= deadline )); then
      echo "Grafana Discord alerting contact point or notification policy did not load within ${VERIFY_TIMEOUT_SECONDS}s" >&2
      exit 1
    fi
    sleep 2
  done

  while true; do
    all_rules_loaded=true
    for rule_uid in "${alert_rule_uids[@]}"; do
      if ! response="$(curl -fsS -u "${GRAFANA_ADMIN_USER}:${GRAFANA_ADMIN_PASSWORD}" \
        "${GRAFANA_URL}/api/v1/provisioning/alert-rules/${rule_uid}")" ||
        ! printf '%s' "$response" | grep -Fq '"ruleGroup":"reading-garden-alerts"'; then
        all_rules_loaded=false
        break
      fi
    done

    if [ "$all_rules_loaded" = true ]; then
      return 0
    fi

    if (( SECONDS >= deadline )); then
      echo "Grafana did not load the expected ReadingGarden alert rules within ${VERIFY_TIMEOUT_SECONDS}s" >&2
      exit 1
    fi
    sleep 2
  done
}

wait_for_http "${PROMETHEUS_URL}/-/ready" "Prometheus readiness"
wait_for_http "${LOKI_URL}/ready" "Loki readiness"
wait_for_prometheus_rules
assert_prometheus_query_has_result 'up{job="prometheus"} == 1' 'prometheus'
assert_prometheus_query_has_result 'sum(up{job="reading-garden-dev-app"}) > 0' 'reading-garden-dev-app'
assert_prometheus_query_has_result 'sum(up{job="reading-garden-prod-app"}) > 0' 'reading-garden-prod-app'
assert_prometheus_query_has_result 'probe_success{job="blackbox-http",instance="https://readinggarden.duckdns.org/api/health"} == 1' 'prod public health blackbox'
assert_prometheus_query_has_result 'up{job="caddy"} == 1' 'caddy'
assert_prometheus_query_has_result 'up{job="node-exporter"} == 1' 'node-exporter'
assert_prometheus_query_has_result 'up{job="cadvisor"} == 1' 'cadvisor'
assert_prometheus_query_has_result 'up{job="blackbox-http"} == 1' 'blackbox-http'
assert_loki_query_has_result '{unit="caddy.service"}' 'caddy systemd logs'

wait_for_grafana_datasource
wait_for_grafana_loki_datasource
wait_for_grafana_dashboard_panels
wait_for_grafana_logs_dashboard_panels
wait_for_grafana_alerting

curl -fsS "${DEV_BASE_URL}/api/health" | grep -Fq '"UP"'
curl -fsS "${DEV_BASE_URL}/v3/api-docs" >/dev/null

echo "PASS: monitoring verification completed"
