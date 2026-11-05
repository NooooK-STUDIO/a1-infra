#!/usr/bin/env bash
set -euo pipefail

PROMETHEUS_URL="${PROMETHEUS_URL:-http://127.0.0.1:9090}"
MONITORING_DIR="${MONITORING_DIR:-/opt/infra/monitoring}"
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
  echo "No expected alert rules found" >&2
  exit 1
fi

rules_file="$(mktemp)"
alerts_file="$(mktemp)"
trap 'rm -f "$rules_file" "$alerts_file"' EXIT

curl --connect-timeout 5 --max-time 15 -fsS "${PROMETHEUS_URL}/api/v1/rules" > "$rules_file"
curl --connect-timeout 5 --max-time 15 -fsS "${PROMETHEUS_URL}/api/v1/alerts" > "$alerts_file"

python3 - "$rules_file" "$alerts_file" "${EXPECTED_ALERT_RULES[@]}" <<'PY'
import json
from collections import Counter
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

all_rules = [r for g in rules_response.get("data", {}).get("groups", []) for r in g.get("rules", [])]

missing = list((Counter(expected) - Counter("|".join([r.get("name", ""), r.get("labels", {}).get("service", ""), r.get("labels", {}).get("env", "")]) for r in all_rules)).elements())
unhealthy = [r.get("name", "unnamed") for r in all_rules if r.get("health") != "ok"]

print("Expected alert rules")
for rule in all_rules:
    service = rule.get("labels", {}).get("service", "unknown")
    print(f"- {service}/{rule.get('name')}: state={rule.get('state')} health={rule.get('health')}")

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
