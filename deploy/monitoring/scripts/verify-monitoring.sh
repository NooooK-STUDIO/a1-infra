#!/usr/bin/env bash
set -euo pipefail

MONITORING_DIR="${MONITORING_DIR:-/opt/infra/monitoring}"
COMPOSE_FILE="${MONITORING_DIR}/docker-compose.yml"
ENV_FILE="${MONITORING_DIR}/.env"
GRAFANA_URL="${GRAFANA_URL:-http://127.0.0.1:3000}"
PROMETHEUS_URL="${PROMETHEUS_URL:-http://127.0.0.1:9090}"
LOKI_URL="${LOKI_URL:-http://127.0.0.1:3100}"
VERIFY_TIMEOUT_SECONDS="${VERIFY_TIMEOUT_SECONDS:-120}"
EXPECTED_ALERT_RULES=()
while IFS= read -r name; do
  EXPECTED_ALERT_RULES+=("$name")
done < <(awk '
  function emit() { if (name != "") print name "|" service "|" environment }
  /^[[:space:]]*- alert:/ { emit(); name=$3; service=""; environment="" }
  /^[[:space:]]+service:/ { service=$2 }
  /^[[:space:]]+env:/ { environment=$2 }
  END { emit() }
' "${MONITORING_DIR}"/prometheus/rules/*.yml)
if [ "${#EXPECTED_ALERT_RULES[@]}" -eq 0 ]; then
  echo "No expected Prometheus alert rules found" >&2
  exit 1
fi

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

  until curl --connect-timeout 5 --max-time 15 -fsS "$url" >/dev/null; do
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

  until curl --connect-timeout 5 --max-time 15 -fsS -G --data-urlencode "query=${query}" "${PROMETHEUS_URL}/api/v1/query" | grep -Fq '"result":[{'; do
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

  until curl --connect-timeout 5 --max-time 15 -fsS -G \
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
  printf '%s' "$1" | python3 -c '
import json, sys
from collections import Counter
response = json.load(sys.stdin)
rules = [r for g in response.get("data", {}).get("groups", []) for r in g.get("rules", [])]
counts = Counter("|".join([r.get("name", ""), r.get("labels", {}).get("service", ""), r.get("labels", {}).get("env", "")]) for r in rules)
expected = sys.argv[1:]
valid = response.get("status") == "success" and bool(expected)
valid = valid and not (Counter(expected) - counts)
valid = valid and all(r.get("health") == "ok" for r in rules)
sys.exit(0 if valid else 1)
' "${EXPECTED_ALERT_RULES[@]}"
}

wait_for_prometheus_rules() {
  local deadline=$((SECONDS + VERIFY_TIMEOUT_SECONDS))
  local response

  until response="$(curl --connect-timeout 5 --max-time 15 -fsS "${PROMETHEUS_URL}/api/v1/rules")" &&
    response_has_expected_alert_rules "$response"; do
    if (( SECONDS >= deadline )); then
      echo "Prometheus did not load the expected healthy alert rules within ${VERIFY_TIMEOUT_SECONDS}s" >&2
      exit 1
    fi
    sleep 2
  done
}

wait_for_grafana_datasource() {
  local deadline=$((SECONDS + VERIFY_TIMEOUT_SECONDS))

  until curl --connect-timeout 5 --max-time 15 -fsS -u "${GRAFANA_ADMIN_USER}:${GRAFANA_ADMIN_PASSWORD}" \
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

  until curl --connect-timeout 5 --max-time 15 -fsS -u "${GRAFANA_ADMIN_USER}:${GRAFANA_ADMIN_PASSWORD}" \
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
  local prod_dashboard_url="${GRAFANA_URL}/api/dashboards/uid/reading-garden-prod-overview"
  local postgres_dashboard_url="${GRAFANA_URL}/api/dashboards/uid/reading-garden-postgres-overview"
  local response

  until response="$(curl --connect-timeout 5 --max-time 15 -fsS -u "${GRAFANA_ADMIN_USER}:${GRAFANA_ADMIN_PASSWORD}" "$prod_dashboard_url")" &&
    printf '%s' "$response" | grep -Fq "Average Response Time" &&
    printf '%s' "$response" | grep -Fq "p95 Response Time" &&
    printf '%s' "$response" | grep -Fq "Error Logs (30m)" &&
    printf '%s' "$response" | grep -Fq "Firing Metric Alerts" &&
    printf '%s' "$response" | grep -Fq "HTTP 5xx Requests / sec" &&
    printf '%s' "$response" | grep -Fq "Active DB Connections" &&
    response="$(curl --connect-timeout 5 --max-time 15 -fsS -u "${GRAFANA_ADMIN_USER}:${GRAFANA_ADMIN_PASSWORD}" "$postgres_dashboard_url")" &&
    printf '%s' "$response" | grep -Fq "PostgreSQL Health" &&
    printf '%s' "$response" | grep -Fq "Connection Usage" &&
    printf '%s' "$response" | grep -Fq "Storage by Database" &&
    printf '%s' "$response" | grep -Fq "Deadlocks"; do
    if (( SECONDS >= deadline )); then
      echo "Grafana app dashboards did not load expected panels within ${VERIFY_TIMEOUT_SECONDS}s" >&2
      exit 1
    fi
    sleep 2
  done
}

wait_for_grafana_logs_dashboard_panels() {
  local deadline=$((SECONDS + VERIFY_TIMEOUT_SECONDS))
  local dashboard_uid expected response

  while IFS='|' read -r dashboard_uid expected; do
    until response="$(curl --connect-timeout 5 --max-time 15 -fsS -u "${GRAFANA_ADMIN_USER}:${GRAFANA_ADMIN_PASSWORD}" \
      "${GRAFANA_URL}/api/dashboards/uid/${dashboard_uid}")" &&
      printf '%s' "$response" | python3 -c '
import json, sys
panels = json.load(sys.stdin)["dashboard"]["panels"]
expected = json.loads(sys.argv[1])
actual = {str(p["id"]): p["title"] for p in panels if p.get("type") == "logs"}
sys.exit(0 if len(panels) == len(expected) and actual == expected else 1)
' "$expected"; do
      if (( SECONDS >= deadline )); then
        echo "Grafana logs dashboard ${dashboard_uid} did not load expected panels within ${VERIFY_TIMEOUT_SECONDS}s" >&2
        exit 1
      fi
      sleep 2
    done
  done <<'LOG_DASHBOARDS'
reading-garden-logs|{"7":"Application Errors","1":"Application Logs","5":"HTTP Access Logs"}
pawtogether-logs|{"7":"Application Errors","1":"Application Logs","5":"HTTP Access Logs"}
a1-shared-logs|{"4":"Caddy Service Logs"}
LOG_DASHBOARDS
}

wait_for_grafana_alerting() {
  local deadline=$((SECONDS + VERIFY_TIMEOUT_SECONDS))
  local contact_points_url="${GRAFANA_URL}/api/v1/provisioning/contact-points"
  local policies_url="${GRAFANA_URL}/api/v1/provisioning/policies"
  local alert_rule_uids=(
    prometheus-alert-forwarder
    grafana-prod-app-error-logs
    grafana-paw-prod-app-error-logs
  )
  local response
  local rule_uid
  local all_rules_loaded

  until response="$(curl --connect-timeout 5 --max-time 15 -fsS -u "${GRAFANA_ADMIN_USER}:${GRAFANA_ADMIN_PASSWORD}" "$contact_points_url")" &&
    printf '%s' "$response" | grep -Fq '"name":"nooook-discord"' &&
    printf '%s' "$response" | grep -Fq '"name":"reading-garden-discord-prod"' &&
    printf '%s' "$response" | grep -Fq '"name":"pawtogether-discord-prod"' &&
    printf '%s' "$response" | grep -Fq '"type":"discord"' &&
    response="$(curl --connect-timeout 5 --max-time 15 -fsS -u "${GRAFANA_ADMIN_USER}:${GRAFANA_ADMIN_PASSWORD}" "${GRAFANA_URL}/api/v1/provisioning/templates/reading-garden-discord-template")" &&
    printf '%s' "$response" | grep -Fq 'reading_garden_discord.message' &&
    response="$(curl --connect-timeout 5 --max-time 15 -fsS -u "${GRAFANA_ADMIN_USER}:${GRAFANA_ADMIN_PASSWORD}" "$policies_url")" &&
    printf '%s' "$response" | grep -Fq '"receiver":"nooook-discord"' &&
    printf '%s' "$response" | grep -Fq '"receiver":"reading-garden-discord-prod"' &&
    printf '%s' "$response" | grep -Fq '"receiver":"pawtogether-discord-prod"'; do
    if (( SECONDS >= deadline )); then
      echo "Grafana Discord alerting contact point or notification policy did not load within ${VERIFY_TIMEOUT_SECONDS}s" >&2
      exit 1
    fi
    sleep 2
  done

  while true; do
    all_rules_loaded=true
    for rule_uid in "${alert_rule_uids[@]}"; do
      if ! response="$(curl --connect-timeout 5 --max-time 15 -fsS -u "${GRAFANA_ADMIN_USER}:${GRAFANA_ADMIN_PASSWORD}" \
        "${GRAFANA_URL}/api/v1/provisioning/alert-rules/${rule_uid}")" ||
        ! printf '%s' "$response" | grep -Fq '"ruleGroup":"monitoring-alerts"'; then
        all_rules_loaded=false
        break
      fi
    done

    if [ "$all_rules_loaded" = true ]; then
      return 0
    fi

    if (( SECONDS >= deadline )); then
      echo "Grafana did not load the expected monitoring alert rules within ${VERIFY_TIMEOUT_SECONDS}s" >&2
      exit 1
    fi
    sleep 2
  done
}

wait_for_http "${PROMETHEUS_URL}/-/ready" "Prometheus readiness"
wait_for_http "${LOKI_URL}/ready" "Loki readiness"
wait_for_http "http://127.0.0.1:12345/-/ready" "Alloy readiness"
wait_for_prometheus_rules
assert_prometheus_query_has_result 'up{job="prometheus"} == 1' 'prometheus'
assert_prometheus_query_has_result 'sum(up{job="reading-garden-prod-app"}) > 0' 'reading-garden-prod-app'
assert_prometheus_query_has_result 'sum(up{job="pawtogether-prod-app"}) > 0' 'pawtogether-prod-app'
assert_prometheus_query_has_result 'probe_success{job="blackbox-public-http",instance="https://pawtogether.duckdns.org/api/health"} == 1' 'PawTogether public health'
assert_prometheus_query_has_result 'probe_success{job="blackbox-local-caddy",instance="pawtogether.duckdns.org"} == 1' 'PawTogether local Caddy health'
for service in reading-garden pawtogether; do
  assert_prometheus_query_has_result "container_memory_working_set_bytes{job=\"cadvisor\",name=~\"${service}-prod-.*\"} > 0" "${service} container memory"
  assert_prometheus_query_has_result "container_cpu_usage_seconds_total{job=\"cadvisor\",name=~\"${service}-prod-.*\"} >= 0" "${service} container CPU"
done
for job in alloy loki grafana; do
  assert_prometheus_query_has_result "up{job=\"${job}\"} == 1" "$job"
done
assert_prometheus_query_has_result 'probe_success{job="blackbox-public-http",instance="https://readinggarden.duckdns.org/api/health"} == 1' 'prod public health blackbox'
assert_prometheus_query_has_result 'probe_success{job="blackbox-local-caddy",instance="readinggarden.duckdns.org"} == 1' 'prod local caddy health blackbox'
assert_prometheus_query_has_result 'up{job="caddy"} == 1' 'caddy'
assert_prometheus_query_has_result 'up{job="node-exporter"} == 1' 'node-exporter'
assert_prometheus_query_has_result 'up{job="cadvisor"} == 1' 'cadvisor'
assert_prometheus_query_has_result 'up{job="postgres-exporter"} == 1' 'postgres-exporter'
assert_prometheus_query_has_result 'pg_up{job="postgres-exporter"} == 1' 'postgres database'
assert_prometheus_query_has_result 'up{job="blackbox-public-http"} == 1' 'blackbox-public-http'
assert_prometheus_query_has_result 'up{job="blackbox-local-caddy"} == 1' 'blackbox-local-caddy'
assert_loki_query_has_result '{unit="caddy.service"}' 'caddy systemd logs'

wait_for_grafana_datasource
wait_for_grafana_loki_datasource
wait_for_grafana_dashboard_panels
wait_for_grafana_logs_dashboard_panels
wait_for_grafana_alerting

deadline=$((SECONDS + VERIFY_TIMEOUT_SECONDS))
until curl --connect-timeout 5 --max-time 15 -fsS -u "${GRAFANA_ADMIN_USER}:${GRAFANA_ADMIN_PASSWORD}" \
  "${GRAFANA_URL}/api/prometheus/grafana/api/v1/rules" | python3 -c '
import json, sys
response = json.load(sys.stdin)
rules = [r for g in response.get("data", {}).get("groups", []) for r in g.get("rules", [])]
assert len(rules) == 3, "Expected forwarding and both application log rules"
assert all(r.get("health") == "ok" for r in rules), "Grafana rule evaluation failed"
'; do
  if (( SECONDS >= deadline )); then
    echo "Grafana alert evaluation did not become healthy" >&2
    exit 1
  fi
  sleep 2
done

while IFS='|' read -r dashboard folder title; do
  curl --connect-timeout 5 --max-time 15 -fsS -u "${GRAFANA_ADMIN_USER}:${GRAFANA_ADMIN_PASSWORD}" \
    "${GRAFANA_URL}/api/dashboards/uid/${dashboard}" | python3 -c '
import json, sys
response = json.load(sys.stdin)
assert response["dashboard"]["panels"], "Missing dashboard panels"
assert response["meta"]["folderTitle"] == sys.argv[1], "Incorrect dashboard folder"
assert response["dashboard"]["title"] == sys.argv[2], "Incorrect dashboard title"
' "$folder" "$title"
done <<'DASHBOARDS'
reading-garden-prod-overview|ReadingGarden|ReadingGarden Overview
reading-garden-logs|ReadingGarden|ReadingGarden Logs
pawtogether-prod-overview|PawTogether|PawTogether Overview
pawtogether-logs|PawTogether|PawTogether Logs
reading-garden-postgres-overview|A1 Shared|Shared PostgreSQL Overview
a1-shared-overview|A1 Shared|A1 Shared Overview
a1-shared-logs|A1 Shared|A1 Shared Logs
DASHBOARDS

for service in reading-garden-kotlin pawtogether; do
  assert_loki_query_has_result "{source=\"caddy_access\",service=\"${service}\"}" "${service} access logs"
done

echo "PASS: monitoring verification completed"
