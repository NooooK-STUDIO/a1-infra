#!/usr/bin/env bash
set -euo pipefail

WORKFLOW_FILE=".github/workflows/infra-deploy.yml"

test -f "$WORKFLOW_FILE"

grep -Fq 'Host-local file preserved: /opt/infra/monitoring/.env' "$WORKFLOW_FILE"
grep -Fq 'sudo mkdir -p /opt/infra/monitoring' "$WORKFLOW_FILE"
grep -Fq 'sudo rm -rf /opt/infra/monitoring/alloy /opt/infra/monitoring/blackbox /opt/infra/monitoring/grafana /opt/infra/monitoring/loki /opt/infra/monitoring/prometheus /opt/infra/monitoring/scripts' "$WORKFLOW_FILE"
grep -Fq 'sudo rm -f /opt/infra/monitoring/SECURITY.md /opt/infra/monitoring/RUNBOOK.md /opt/infra/monitoring/.env.example /opt/infra/monitoring/docker-compose.yml /opt/infra/monitoring/docker-compose.monitoring.yml' "$WORKFLOW_FILE"

if rg -n 'rm -rf /opt/infra/monitoring($|[^/])|rm -f /opt/infra/monitoring/\.env($|[^.[:alnum:]_-])' "$WORKFLOW_FILE"; then
    echo "monitoring apply must preserve /opt/infra/monitoring/.env and must not wipe the whole monitoring directory" >&2
    exit 1
fi

echo "PASS"
