#!/usr/bin/env bash
set -euo pipefail

test -f deploy/monitoring/prometheus/prometheus.yml
test -f deploy/monitoring/prometheus/rules/reading-garden-dev.yml
test -f deploy/monitoring/prometheus/rules/reading-garden-prod.yml
test -f deploy/monitoring/blackbox/blackbox.yml
test -f deploy/monitoring/SECURITY.md
test -f deploy/monitoring/grafana/provisioning/datasources/datasources.yml
test -f deploy/monitoring/grafana/provisioning/dashboards/dashboards.yml
test -f deploy/monitoring/grafana/dashboards/reading-garden-dev-overview.json
test -f deploy/monitoring/grafana/dashboards/reading-garden-prod-overview.json
test -x deploy/monitoring/scripts/bootstrap-monitoring.sh
test -x deploy/monitoring/scripts/verify-monitoring.sh
test -f deploy/monitoring/RUNBOOK.md

grep -Fq 'retention.time=7d' deploy/monitoring/docker-compose.monitoring.yml
grep -Fq 'container_name: a1-monitoring-prometheus' deploy/monitoring/docker-compose.monitoring.yml
grep -Fq 'container_name: a1-monitoring-grafana' deploy/monitoring/docker-compose.monitoring.yml
grep -Fq 'container_name: a1-monitoring-node-exporter' deploy/monitoring/docker-compose.monitoring.yml
grep -Fq 'container_name: a1-monitoring-cadvisor' deploy/monitoring/docker-compose.monitoring.yml
grep -Fq 'container_name: a1-monitoring-blackbox-exporter' deploy/monitoring/docker-compose.monitoring.yml
if rg -n 'container_name: reading-garden-monitoring-' deploy/monitoring/docker-compose.monitoring.yml; then
  echo 'Monitoring container names must be A1-generic, not ReadingGarden-specific.' >&2
  exit 1
fi
grep -Fq 'gcr.io/cadvisor/cadvisor:v0.52.1' deploy/monitoring/docker-compose.monitoring.yml
grep -Fq 'prom/blackbox-exporter' deploy/monitoring/docker-compose.monitoring.yml
grep -Fq 'GF_METRICS_ENABLED: "true"' deploy/monitoring/docker-compose.monitoring.yml
grep -Fq 'network_mode: host' deploy/monitoring/docker-compose.monitoring.yml
grep -Fq -- '--web.listen-address=127.0.0.1:9090' deploy/monitoring/docker-compose.monitoring.yml
grep -Fq 'GF_SERVER_HTTP_ADDR: 127.0.0.1' deploy/monitoring/docker-compose.monitoring.yml
grep -Fq 'uid: prometheus' deploy/monitoring/grafana/provisioning/datasources/datasources.yml
grep -Fq 'reading-garden-dev-overview' deploy/monitoring/grafana/dashboards/reading-garden-dev-overview.json
grep -Fq 'reading-garden-prod-overview' deploy/monitoring/grafana/dashboards/reading-garden-prod-overview.json
grep -Fq '127.0.0.1:19090' deploy/monitoring/prometheus/prometheus.yml
grep -Fq '127.0.0.1:19091' deploy/monitoring/prometheus/prometheus.yml
grep -Fq '127.0.0.1:19080' deploy/monitoring/prometheus/prometheus.yml
grep -Fq '127.0.0.1:19081' deploy/monitoring/prometheus/prometheus.yml
grep -Fq '127.0.0.1:2019' deploy/monitoring/prometheus/prometheus.yml
grep -Fq '127.0.0.1:18082' deploy/monitoring/prometheus/prometheus.yml
grep -Fq '127.0.0.1:9115' deploy/monitoring/prometheus/prometheus.yml
grep -Fq 'job_name: caddy' deploy/monitoring/prometheus/prometheus.yml
grep -Fq 'job_name: cadvisor' deploy/monitoring/prometheus/prometheus.yml
grep -Fq 'job_name: blackbox-http' deploy/monitoring/prometheus/prometheus.yml
grep -Fq 'job_name: reading-garden-prod-app' deploy/monitoring/prometheus/prometheus.yml
grep -Fq 'https://readinggarden-dev.duckdns.org/api/health' deploy/monitoring/prometheus/prometheus.yml
grep -Fq 'https://readinggarden.duckdns.org/api/health' deploy/monitoring/prometheus/prometheus.yml
grep -Fq 'DevExternalHealthDown' deploy/monitoring/prometheus/rules/reading-garden-dev.yml
grep -Fq 'ProdExternalHealthDown' deploy/monitoring/prometheus/rules/reading-garden-prod.yml
grep -Fq 'HostMemoryHigh' deploy/monitoring/prometheus/rules/reading-garden-dev.yml
grep -Fq 'reading-garden-prod-app' deploy/monitoring/grafana/dashboards/reading-garden-prod-overview.json
grep -Fq 'docker compose -f "$COMPOSE_FILE" --env-file "$ENV_FILE" up -d' deploy/monitoring/scripts/bootstrap-monitoring.sh
grep -Fq '/api/datasources/uid/prometheus/health' deploy/monitoring/scripts/verify-monitoring.sh
grep -Fq 'postgres_exporter Later' deploy/monitoring/RUNBOOK.md
grep -Fq 'Loki And Alloy Later' deploy/monitoring/RUNBOOK.md
grep -Fq 'Alertmanager Later' deploy/monitoring/RUNBOOK.md

if rg -n 'discord(app)?\.com/api/webhooks/[0-9]+|DISCORD_WEBHOOK_URL|type: discord|alertmanager|loki:|alloy:|postgres-exporter:' deploy/monitoring; then
    echo "deferred secrets or services must not be committed in phase 1" >&2
    exit 1
fi

echo "PASS"
