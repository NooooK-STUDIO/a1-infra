#!/usr/bin/env bash
set -euo pipefail

PROMETHEUS_URL="${PROMETHEUS_URL:-http://127.0.0.1:9090}"
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
  PostgresExporterDown
  PostgresConnectionsHigh
  PostgresDeadlocksDetected
)

rules_file="$(mktemp)"
alerts_file="$(mktemp)"
trap 'rm -f "$rules_file" "$alerts_file"' EXIT

curl -fsS "${PROMETHEUS_URL}/api/v1/rules" > "$rules_file"
curl -fsS "${PROMETHEUS_URL}/api/v1/alerts" > "$alerts_file"

python3 - "$rules_file" "$alerts_file" "${EXPECTED_ALERT_RULES[@]}" <<'PY'
import json
import sys

rules_path, alerts_path, *expected = sys.argv[1:]

with open(rules_path, encoding="utf-8") as rules_handle:
    rules_response = json.load(rules_handle)

with open(alerts_path, encoding="utf-8") as alerts_handle:
    alerts_response = json.load(alerts_handle)

if rules_response.get("status") != "success":
    raise SystemExit("Prometheus rules API did not return success")

if alerts_response.get("status") != "success":
    raise SystemExit("Prometheus alerts API did not return success")

rule_names = {}
rule_health = {}
for group in rules_response.get("data", {}).get("groups", []):
    for rule in group.get("rules", []):
        name = rule.get("name")
        if name:
            rule_names[name] = rule.get("state", "unknown")
            rule_health[name] = rule.get("health", "unknown")

missing = [name for name in expected if name not in rule_names]
unhealthy = [name for name in expected if rule_health.get(name) != "ok"]

print("Expected alert rules")
for name in expected:
    state = rule_names.get(name, "missing")
    health = rule_health.get(name, "missing")
    print(f"- {name}: state={state} health={health}")

alerts = alerts_response.get("data", {}).get("alerts", [])
active = [
    alert for alert in alerts
    if alert.get("state") in {"pending", "firing"}
]

print("")
print("Active alerts")
if not active:
    print("- none")
else:
    for alert in active:
        labels = alert.get("labels", {})
        annotations = alert.get("annotations", {})
        name = labels.get("alertname", "unknown")
        state = alert.get("state", "unknown")
        severity = labels.get("severity", "unknown")
        summary = annotations.get("summary", "")
        print(f"- {name}: state={state} severity={severity} summary={summary}")

if missing:
    raise SystemExit(f"Missing expected alert rules: {', '.join(missing)}")

if unhealthy:
    raise SystemExit(f"Unhealthy expected alert rules: {', '.join(unhealthy)}")

if active:
    raise SystemExit("One or more alerts are pending or firing")
PY
