#!/usr/bin/env bash
set -euo pipefail

test -f deploy/monitoring/prometheus/prometheus.yml
test -f deploy/monitoring/prometheus/rules/reading-garden-dev.yml
test -f deploy/monitoring/prometheus/rules/reading-garden-prod.yml
test -f deploy/monitoring/blackbox/blackbox.yml
test -f deploy/monitoring/loki/loki.yml
test -f deploy/monitoring/alloy/config.alloy
test -f deploy/monitoring/SECURITY.md
test -f deploy/monitoring/grafana/provisioning/datasources/datasources.yml
test -f deploy/monitoring/grafana/provisioning/dashboards/dashboards.yml
test -f deploy/monitoring/grafana/provisioning/alerting/contact-points.yml
test -f deploy/monitoring/grafana/provisioning/alerting/notification-policies.yml
test -f deploy/monitoring/grafana/provisioning/alerting/notification-templates.yml
test -f deploy/monitoring/grafana/provisioning/alerting/reading-garden-alerts.yml
ruby -e 'require "yaml"; YAML.load_file(ARGV.fetch(0))' deploy/monitoring/grafana/provisioning/alerting/reading-garden-alerts.yml
test -f deploy/monitoring/grafana/dashboards/reading-garden-dev-overview.json
test -f deploy/monitoring/grafana/dashboards/reading-garden-prod-overview.json
test -f deploy/monitoring/grafana/dashboards/reading-garden-logs.json
test -f deploy/monitoring/grafana/dashboards/reading-garden-postgres-overview.json
test -x deploy/monitoring/scripts/bootstrap-monitoring.sh
test -x deploy/monitoring/scripts/verify-monitoring.sh
test -x deploy/monitoring/scripts/check-alerts.sh
test -x deploy/monitoring/scripts/backup-grafana-state.sh
test -f deploy/monitoring/RUNBOOK.md

grep -Fq 'retention.time=7d' deploy/monitoring/docker-compose.monitoring.yml
grep -Fq 'container_name: a1-monitoring-prometheus' deploy/monitoring/docker-compose.monitoring.yml
grep -Fq 'container_name: a1-monitoring-grafana' deploy/monitoring/docker-compose.monitoring.yml
grep -Fq 'container_name: a1-monitoring-loki' deploy/monitoring/docker-compose.monitoring.yml
grep -Fq 'container_name: a1-monitoring-alloy' deploy/monitoring/docker-compose.monitoring.yml
grep -Fq 'container_name: a1-monitoring-node-exporter' deploy/monitoring/docker-compose.monitoring.yml
grep -Fq 'container_name: a1-monitoring-cadvisor' deploy/monitoring/docker-compose.monitoring.yml
grep -Fq 'container_name: a1-monitoring-blackbox-exporter' deploy/monitoring/docker-compose.monitoring.yml
grep -Fq 'container_name: a1-monitoring-postgres-exporter' deploy/monitoring/docker-compose.monitoring.yml
if rg -n 'container_name: reading-garden-monitoring-' deploy/monitoring/docker-compose.monitoring.yml; then
  echo 'Monitoring container names must be A1-generic, not ReadingGarden-specific.' >&2
  exit 1
fi
grep -Fq 'gcr.io/cadvisor/cadvisor:v0.52.1' deploy/monitoring/docker-compose.monitoring.yml
grep -Fq 'prom/blackbox-exporter' deploy/monitoring/docker-compose.monitoring.yml
grep -Fq 'grafana/loki' deploy/monitoring/docker-compose.monitoring.yml
grep -Fq 'grafana/loki:3.5.2' deploy/monitoring/docker-compose.monitoring.yml
grep -Fq 'grafana/alloy' deploy/monitoring/docker-compose.monitoring.yml
grep -Fq 'quay.io/prometheuscommunity/postgres-exporter:v0.19.1' deploy/monitoring/docker-compose.monitoring.yml
grep -Fq -- '--web.listen-address=127.0.0.1:9187' deploy/monitoring/docker-compose.monitoring.yml
grep -Fq 'DATA_SOURCE_URI: 127.0.0.1:15432/postgres?sslmode=disable' deploy/monitoring/docker-compose.monitoring.yml
grep -Fq 'DATA_SOURCE_USER: reading_garden_monitoring' deploy/monitoring/docker-compose.monitoring.yml
grep -Fq 'DATA_SOURCE_PASS: ${POSTGRES_EXPORTER_PASSWORD:?POSTGRES_EXPORTER_PASSWORD is required}' deploy/monitoring/docker-compose.monitoring.yml
grep -Fq 'PG_EXPORTER_AUTO_DISCOVER_DATABASES: "true"' deploy/monitoring/docker-compose.monitoring.yml
grep -Fq 'GF_METRICS_ENABLED: "true"' deploy/monitoring/docker-compose.monitoring.yml
grep -Fq 'GF_SERVER_ROOT_URL: ${GRAFANA_ROOT_URL:-https://nooook-monitoring.duckdns.org}' deploy/monitoring/docker-compose.monitoring.yml
grep -Fq 'NOOOOK_DISCORD_WEBHOOK_URL: ${NOOOOK_DISCORD_WEBHOOK_URL:?NOOOOK_DISCORD_WEBHOOK_URL is required}' deploy/monitoring/docker-compose.monitoring.yml
grep -Fq 'GRAFANA_DISCORD_DEV_WEBHOOK_URL: ${GRAFANA_DISCORD_DEV_WEBHOOK_URL:?GRAFANA_DISCORD_DEV_WEBHOOK_URL is required}' deploy/monitoring/docker-compose.monitoring.yml
grep -Fq 'GRAFANA_DISCORD_PROD_WEBHOOK_URL: ${GRAFANA_DISCORD_PROD_WEBHOOK_URL:?GRAFANA_DISCORD_PROD_WEBHOOK_URL is required}' deploy/monitoring/docker-compose.monitoring.yml
grep -Fq 'network_mode: host' deploy/monitoring/docker-compose.monitoring.yml
grep -Fq -- '--web.listen-address=127.0.0.1:9090' deploy/monitoring/docker-compose.monitoring.yml
grep -Fq 'GF_SERVER_HTTP_ADDR: 127.0.0.1' deploy/monitoring/docker-compose.monitoring.yml
grep -Fq 'uid: prometheus' deploy/monitoring/grafana/provisioning/datasources/datasources.yml
grep -Fq 'uid: loki' deploy/monitoring/grafana/provisioning/datasources/datasources.yml
grep -Fq 'url: http://127.0.0.1:3100' deploy/monitoring/grafana/provisioning/datasources/datasources.yml
grep -Fq 'reading-garden-dev-overview' deploy/monitoring/grafana/dashboards/reading-garden-dev-overview.json
grep -Fq 'reading-garden-prod-overview' deploy/monitoring/grafana/dashboards/reading-garden-prod-overview.json
grep -Fq 'reading-garden-logs' deploy/monitoring/grafana/dashboards/reading-garden-logs.json
grep -Fq 'reading-garden-postgres-overview' deploy/monitoring/grafana/dashboards/reading-garden-postgres-overview.json
grep -Fq 'ReadingGarden Postgres Overview' deploy/monitoring/grafana/dashboards/reading-garden-postgres-overview.json
grep -Fq 'Postgres Exporter Up' deploy/monitoring/grafana/dashboards/reading-garden-postgres-overview.json
grep -Fq 'Postgres Connections Percent' deploy/monitoring/grafana/dashboards/reading-garden-postgres-overview.json
grep -Fq 'pg_up{job=\"postgres-exporter\"}' deploy/monitoring/grafana/dashboards/reading-garden-postgres-overview.json
grep -Fq 'pg_database_size_bytes{job=\"postgres-exporter\",datname=\"reading_garden_prod\"}' deploy/monitoring/grafana/dashboards/reading-garden-postgres-overview.json
grep -Fq 'ReadingGarden Logs' deploy/monitoring/grafana/dashboards/reading-garden-logs.json
grep -Fq '{source=\"docker\"}' deploy/monitoring/grafana/dashboards/reading-garden-logs.json
grep -Fq '{container=~\"reading-garden-prod-.*\"}' deploy/monitoring/grafana/dashboards/reading-garden-logs.json
grep -Fq '{container=~\"reading-garden-dev-.*\"}' deploy/monitoring/grafana/dashboards/reading-garden-logs.json
grep -Fq '{unit=\"caddy.service\"}' deploy/monitoring/grafana/dashboards/reading-garden-logs.json
grep -Fq '{source=\"caddy_access\",env=\"prod\"}' deploy/monitoring/grafana/dashboards/reading-garden-logs.json
grep -Fq '{source=\"caddy_access\",env=\"dev\"}' deploy/monitoring/grafana/dashboards/reading-garden-logs.json
grep -Fq 'loki.source.docker "containers"' deploy/monitoring/alloy/config.alloy
grep -Fq 'local.file_match "caddy_access"' deploy/monitoring/alloy/config.alloy
grep -Fq 'loki.source.file "caddy_access"' deploy/monitoring/alloy/config.alloy
grep -Fq '__path__ = "/var/log/caddy/reading-garden-prod-access.log"' deploy/monitoring/alloy/config.alloy
grep -Fq '__path__ = "/var/log/caddy/reading-garden-dev-access.log"' deploy/monitoring/alloy/config.alloy
grep -Fq 'loki.source.journal "caddy"' deploy/monitoring/alloy/config.alloy
grep -Fq 'action        = "keep"' deploy/monitoring/alloy/config.alloy
grep -Fq 'regex         = "/reading-garden-(prod|dev)-.*"' deploy/monitoring/alloy/config.alloy
grep -Fq 'loki.relabel "app_containers"' deploy/monitoring/alloy/config.alloy
grep -Fq 'regex         = "reading-garden-(prod|dev)-.*"' deploy/monitoring/alloy/config.alloy
if rg -n 'a1-monitoring-loki|shared-postgres' deploy/monitoring/grafana/dashboards/reading-garden-logs.json deploy/monitoring/alloy/config.alloy; then
    echo "log collection must avoid monitoring self-log loops and shared-postgres noise" >&2
    exit 1
fi
grep -Fq 'matches       = "SYSLOG_IDENTIFIER=caddy"' deploy/monitoring/alloy/config.alloy
grep -Fq 'path          = "/var/log/journal"' deploy/monitoring/alloy/config.alloy
grep -Fq 'retention_period: 72h' deploy/monitoring/loki/loki.yml
grep -Fq 'allow_structured_metadata: false' deploy/monitoring/loki/loki.yml
grep -Fq '"from": "now-6h"' deploy/monitoring/grafana/dashboards/reading-garden-logs.json
grep -Fq 'Dev Avg Latency' deploy/monitoring/grafana/dashboards/reading-garden-dev-overview.json
grep -Fq 'Dev Max Latency' deploy/monitoring/grafana/dashboards/reading-garden-dev-overview.json
grep -Fq 'Dev 5xx Rate' deploy/monitoring/grafana/dashboards/reading-garden-dev-overview.json
grep -Fq 'Dev p95 Latency' deploy/monitoring/grafana/dashboards/reading-garden-dev-overview.json
grep -Fq 'Dev Recent Error Logs' deploy/monitoring/grafana/dashboards/reading-garden-dev-overview.json
grep -Fq 'Dev Active Alerts' deploy/monitoring/grafana/dashboards/reading-garden-dev-overview.json
grep -Fq 'Dev Request Rate' deploy/monitoring/grafana/dashboards/reading-garden-dev-overview.json
grep -Fq 'histogram_quantile(0.95, sum by (le) (rate(http_server_requests_seconds_bucket{job=\"reading-garden-dev-app\"}[5m])))' deploy/monitoring/grafana/dashboards/reading-garden-dev-overview.json
grep -Fq 'sum(ALERTS{env=\"dev\",alertstate=\"firing\"}) or vector(0)' deploy/monitoring/grafana/dashboards/reading-garden-dev-overview.json
grep -Fq 'Hikari Active Connections' deploy/monitoring/grafana/dashboards/reading-garden-dev-overview.json
grep -Fq 'Process Uptime' deploy/monitoring/grafana/dashboards/reading-garden-dev-overview.json
grep -Fq 'Caddy Request Rate' deploy/monitoring/grafana/dashboards/reading-garden-dev-overview.json
grep -Fq 'Caddy p95 Duration' deploy/monitoring/grafana/dashboards/reading-garden-dev-overview.json
grep -Fq 'Host CPU Usage Percent' deploy/monitoring/grafana/dashboards/reading-garden-dev-overview.json
grep -Fq 'Host Load 1m' deploy/monitoring/grafana/dashboards/reading-garden-dev-overview.json
grep -Fq 'jvm_threads_live_threads{job=\"reading-garden-dev-app\"}' deploy/monitoring/grafana/dashboards/reading-garden-dev-overview.json
grep -Fq 'caddy_config_last_reload_successful{job=\"caddy\"}' deploy/monitoring/grafana/dashboards/reading-garden-dev-overview.json
grep -Fq 'Prod Avg Latency' deploy/monitoring/grafana/dashboards/reading-garden-prod-overview.json
grep -Fq 'Prod Max Latency' deploy/monitoring/grafana/dashboards/reading-garden-prod-overview.json
grep -Fq 'Prod 5xx Rate' deploy/monitoring/grafana/dashboards/reading-garden-prod-overview.json
grep -Fq 'Prod p95 Latency' deploy/monitoring/grafana/dashboards/reading-garden-prod-overview.json
grep -Fq 'Prod Recent Error Logs' deploy/monitoring/grafana/dashboards/reading-garden-prod-overview.json
grep -Fq 'Prod Active Alerts' deploy/monitoring/grafana/dashboards/reading-garden-prod-overview.json
grep -Fq 'Prod Request Rate' deploy/monitoring/grafana/dashboards/reading-garden-prod-overview.json
grep -Fq 'histogram_quantile(0.95, sum by (le) (rate(http_server_requests_seconds_bucket{job=\"reading-garden-prod-app\"}[5m])))' deploy/monitoring/grafana/dashboards/reading-garden-prod-overview.json
grep -Fq 'sum(ALERTS{env=\"prod\",alertstate=\"firing\"}) or vector(0)' deploy/monitoring/grafana/dashboards/reading-garden-prod-overview.json
grep -Fq 'Hikari Active Connections' deploy/monitoring/grafana/dashboards/reading-garden-prod-overview.json
grep -Fq 'Process Uptime' deploy/monitoring/grafana/dashboards/reading-garden-prod-overview.json
grep -Fq 'jvm_threads_live_threads{job=\"reading-garden-prod-app\"}' deploy/monitoring/grafana/dashboards/reading-garden-prod-overview.json
grep -Fq '127.0.0.1:19090' deploy/monitoring/prometheus/prometheus.yml
grep -Fq '127.0.0.1:19091' deploy/monitoring/prometheus/prometheus.yml
grep -Fq 'job_name: reading-garden-prod-app' deploy/monitoring/prometheus/prometheus.yml
grep -Fq '127.0.0.1:19080' deploy/monitoring/prometheus/prometheus.yml
grep -Fq '127.0.0.1:19081' deploy/monitoring/prometheus/prometheus.yml
grep -Fq '127.0.0.1:2019' deploy/monitoring/prometheus/prometheus.yml
grep -Fq '127.0.0.1:18082' deploy/monitoring/prometheus/prometheus.yml
grep -Fq '127.0.0.1:9115' deploy/monitoring/prometheus/prometheus.yml
grep -Fq '127.0.0.1:9187' deploy/monitoring/prometheus/prometheus.yml
grep -Fq 'job_name: caddy' deploy/monitoring/prometheus/prometheus.yml
grep -Fq 'job_name: cadvisor' deploy/monitoring/prometheus/prometheus.yml
grep -Fq 'job_name: blackbox-http' deploy/monitoring/prometheus/prometheus.yml
grep -Fq 'job_name: postgres-exporter' deploy/monitoring/prometheus/prometheus.yml
grep -Fq 'https://readinggarden-dev.duckdns.org/api/health' deploy/monitoring/prometheus/prometheus.yml
grep -Fq 'https://readinggarden.duckdns.org/api/health' deploy/monitoring/prometheus/prometheus.yml
grep -Fq 'DevExternalHealthDown' deploy/monitoring/prometheus/rules/reading-garden-dev.yml
grep -Fq 'Dev5xxRateHigh' deploy/monitoring/prometheus/rules/reading-garden-dev.yml
grep -Fq 'DevAvgLatencyHigh' deploy/monitoring/prometheus/rules/reading-garden-dev.yml
grep -Fq 'HikariPendingConnections' deploy/monitoring/prometheus/rules/reading-garden-dev.yml
grep -Fq 'ContainerExporterDown' deploy/monitoring/prometheus/rules/reading-garden-dev.yml
grep -Fq 'CaddyRequestLatencyHigh' deploy/monitoring/prometheus/rules/reading-garden-dev.yml
grep -Fq 'CaddyReloadFailed' deploy/monitoring/prometheus/rules/reading-garden-dev.yml
grep -Fq 'HostMemoryHigh' deploy/monitoring/prometheus/rules/reading-garden-dev.yml
grep -Fq 'PostgresExporterDown' deploy/monitoring/prometheus/rules/reading-garden-dev.yml
grep -Fq 'PostgresConnectionsHigh' deploy/monitoring/prometheus/rules/reading-garden-dev.yml
grep -Fq 'PostgresDeadlocksDetected' deploy/monitoring/prometheus/rules/reading-garden-dev.yml
grep -Fq 'ProdAppMetricsDown' deploy/monitoring/prometheus/rules/reading-garden-prod.yml
grep -Fq 'ProdExternalHealthDown' deploy/monitoring/prometheus/rules/reading-garden-prod.yml
grep -Fq 'Prod5xxRateHigh' deploy/monitoring/prometheus/rules/reading-garden-prod.yml
grep -Fq 'ProdAvgLatencyHigh' deploy/monitoring/prometheus/rules/reading-garden-prod.yml
grep -Fq 'ProdHikariPendingConnections' deploy/monitoring/prometheus/rules/reading-garden-prod.yml
grep -Fq 'sum(rate(http_server_requests_seconds_count{job="reading-garden-prod-app",status=~"5.."}[5m])) > 0' deploy/monitoring/prometheus/rules/reading-garden-prod.yml
grep -Fq 'sum(rate(http_server_requests_seconds_sum{job="reading-garden-prod-app"}[5m])) / sum(rate(http_server_requests_seconds_count{job="reading-garden-prod-app"}[5m])) > 0.75' deploy/monitoring/prometheus/rules/reading-garden-prod.yml
grep -A2 'alert: Prod5xxRateHigh' deploy/monitoring/prometheus/rules/reading-garden-prod.yml | grep -Fq 'for: 1m'
grep -A2 'alert: ProdAvgLatencyHigh' deploy/monitoring/prometheus/rules/reading-garden-prod.yml | grep -Fq 'for: 5m'
grep -A2 'alert: ProdHikariPendingConnections' deploy/monitoring/prometheus/rules/reading-garden-prod.yml | grep -Fq 'for: 2m'
grep -Fq 'type: discord' deploy/monitoring/grafana/provisioning/alerting/contact-points.yml
grep -Fq 'name: reading-garden-discord-template' deploy/monitoring/grafana/provisioning/alerting/notification-templates.yml
grep -Fq '{{ define "reading_garden_discord.title" -}}' deploy/monitoring/grafana/provisioning/alerting/notification-templates.yml
grep -Fq '{{ define "reading_garden_discord.message" -}}' deploy/monitoring/grafana/provisioning/alerting/notification-templates.yml
grep -Fq '{{ template "reading_garden_discord.title" . }}' deploy/monitoring/grafana/provisioning/alerting/contact-points.yml
grep -Fq '{{ template "reading_garden_discord.message" . }}' deploy/monitoring/grafana/provisioning/alerting/contact-points.yml
grep -Fq 'name: nooook-discord' deploy/monitoring/grafana/provisioning/alerting/contact-points.yml
grep -Fq 'url: $NOOOOK_DISCORD_WEBHOOK_URL' deploy/monitoring/grafana/provisioning/alerting/contact-points.yml
grep -Fq 'deleteContactPoints:' deploy/monitoring/grafana/provisioning/alerting/contact-points.yml
grep -Fq 'uid: reading-garden-discord' deploy/monitoring/grafana/provisioning/alerting/contact-points.yml
if rg -n --pcre2 'name: reading-garden-discord(?!-(dev|prod|template))|GRAFANA_DISCORD_WEBHOOK_URL' deploy/monitoring .github; then
    echo "old host/common ReadingGarden Discord receiver and env key must not remain" >&2
    exit 1
fi
grep -Fq 'url: $GRAFANA_DISCORD_DEV_WEBHOOK_URL' deploy/monitoring/grafana/provisioning/alerting/contact-points.yml
grep -Fq 'url: $GRAFANA_DISCORD_PROD_WEBHOOK_URL' deploy/monitoring/grafana/provisioning/alerting/contact-points.yml
grep -Fq 'receiver: reading-garden-discord-dev' deploy/monitoring/grafana/provisioning/alerting/notification-policies.yml
grep -Fq 'receiver: reading-garden-discord-prod' deploy/monitoring/grafana/provisioning/alerting/notification-policies.yml
grep -Fq 'receiver: nooook-discord' deploy/monitoring/grafana/provisioning/alerting/notification-policies.yml
grep -Fq 'GrafanaDevExternalHealthDown' deploy/monitoring/grafana/provisioning/alerting/reading-garden-alerts.yml
grep -Fq 'GrafanaProdExternalHealthDown' deploy/monitoring/grafana/provisioning/alerting/reading-garden-alerts.yml
grep -Fq 'GrafanaDevAppMetricsDown' deploy/monitoring/grafana/provisioning/alerting/reading-garden-alerts.yml
grep -Fq 'GrafanaProdAppMetricsDown' deploy/monitoring/grafana/provisioning/alerting/reading-garden-alerts.yml
grep -Fq 'GrafanaDevAppErrorLogsDetected' deploy/monitoring/grafana/provisioning/alerting/reading-garden-alerts.yml
grep -Fq 'GrafanaProdAppErrorLogsDetected' deploy/monitoring/grafana/provisioning/alerting/reading-garden-alerts.yml
grep -Fq 'GrafanaCaddyMetricsDown' deploy/monitoring/grafana/provisioning/alerting/reading-garden-alerts.yml
grep -Fq 'GrafanaHostDiskAlmostFull' deploy/monitoring/grafana/provisioning/alerting/reading-garden-alerts.yml
grep -Fq 'for: 1m' deploy/monitoring/grafana/provisioning/alerting/reading-garden-alerts.yml
grep -Fq '{container=~"reading-garden-prod-.*"} |~ "(?i)(\\bERROR\\b|exception|traceback|NullPointerException|IllegalStateException|DataAccessException|ResponseStatusException)" !~ "(?i)(no error|error page|error dispatch)"' deploy/monitoring/grafana/provisioning/alerting/reading-garden-alerts.yml
grep -Fq '{container=~"reading-garden-dev-.*"} |~ "(?i)(\\bERROR\\b|exception|traceback|NullPointerException|IllegalStateException|DataAccessException|ResponseStatusException)" !~ "(?i)(no error|error page|error dispatch)"' deploy/monitoring/grafana/provisioning/alerting/reading-garden-alerts.yml
grep -Fq 'logs_dashboard: https://nooook-monitoring.duckdns.org/d/reading-garden-logs?orgId=1&from=now-30m&to=now' deploy/monitoring/grafana/provisioning/alerting/reading-garden-alerts.yml
grep -Fq 'logs_query: '\''{container=~"reading-garden-prod-.*"} |~ "(?i)(\\bERROR\\b|exception|traceback|NullPointerException|IllegalStateException|DataAccessException|ResponseStatusException)"' deploy/monitoring/grafana/provisioning/alerting/reading-garden-alerts.yml
grep -Fq 'logs_query: '\''{container=~"reading-garden-dev-.*"} |~ "(?i)(\\bERROR\\b|exception|traceback|NullPointerException|IllegalStateException|DataAccessException|ResponseStatusException)"' deploy/monitoring/grafana/provisioning/alerting/reading-garden-alerts.yml
grep -Fq 'FCM (HTTP error|send failed): .*?(fcmErrorCode|errorCode)=(UNREGISTERED|messaging/registration-token-not-registered)' deploy/monitoring/grafana/provisioning/alerting/reading-garden-alerts.yml
grep -Fq 'signal: logs' deploy/monitoring/grafana/provisioning/alerting/reading-garden-alerts.yml
grep -A55 'uid: grafana-dev-app-error-logs' deploy/monitoring/grafana/provisioning/alerting/reading-garden-alerts.yml | grep -Fq 'for: 2m'
grep -A55 'uid: grafana-prod-app-error-logs' deploy/monitoring/grafana/provisioning/alerting/reading-garden-alerts.yml | grep -Fq 'for: 1m'
grep -Fq 'NOOOOK_DISCORD_WEBHOOK_URL=' deploy/monitoring/.env.example
grep -Fq 'GRAFANA_DISCORD_DEV_WEBHOOK_URL=' deploy/monitoring/.env.example
grep -Fq 'GRAFANA_DISCORD_PROD_WEBHOOK_URL=' deploy/monitoring/.env.example
grep -Fq 'POSTGRES_EXPORTER_PASSWORD=' deploy/monitoring/.env.example
grep -Fq 'docker compose -f "$COMPOSE_FILE" --env-file "$ENV_FILE" up -d --force-recreate' deploy/monitoring/scripts/bootstrap-monitoring.sh
grep -Fq 'NOOOOK_DISCORD_WEBHOOK_URL' deploy/monitoring/scripts/bootstrap-monitoring.sh
grep -Fq '/api/datasources/uid/prometheus/health' deploy/monitoring/scripts/verify-monitoring.sh
grep -Fq 'VERIFY_TIMEOUT_SECONDS' deploy/monitoring/scripts/verify-monitoring.sh
grep -Fq 'wait_for_http "${PROMETHEUS_URL}/-/ready" "Prometheus readiness"' deploy/monitoring/scripts/verify-monitoring.sh
grep -Fq 'wait_for_prometheus_rules' deploy/monitoring/scripts/verify-monitoring.sh
grep -Fq '/api/v1/rules' deploy/monitoring/scripts/verify-monitoring.sh
grep -Fq 'Dev5xxRateHigh' deploy/monitoring/scripts/verify-monitoring.sh
grep -Fq 'DevAvgLatencyHigh' deploy/monitoring/scripts/verify-monitoring.sh
grep -Fq 'HikariPendingConnections' deploy/monitoring/scripts/verify-monitoring.sh
grep -Fq 'Prod5xxRateHigh' deploy/monitoring/scripts/verify-monitoring.sh
grep -Fq 'ProdAvgLatencyHigh' deploy/monitoring/scripts/verify-monitoring.sh
grep -Fq 'ProdHikariPendingConnections' deploy/monitoring/scripts/verify-monitoring.sh
grep -Fq 'CaddyRequestLatencyHigh' deploy/monitoring/scripts/verify-monitoring.sh
grep -Fq 'CaddyReloadFailed' deploy/monitoring/scripts/verify-monitoring.sh
grep -Fq 'wait_for_grafana_datasource' deploy/monitoring/scripts/verify-monitoring.sh
grep -Fq 'wait_for_grafana_dashboard_panels' deploy/monitoring/scripts/verify-monitoring.sh
grep -Fq 'wait_for_grafana_alerting' deploy/monitoring/scripts/verify-monitoring.sh
grep -Fq 'GRAFANA_CONTAINER="${GRAFANA_CONTAINER:-a1-monitoring-grafana}"' deploy/monitoring/scripts/backup-grafana-state.sh
grep -Fq 'BACKUP_DIR="${BACKUP_DIR:-/opt/infra/monitoring/backups}"' deploy/monitoring/scripts/backup-grafana-state.sh
grep -Fq -- '--entrypoint sh' deploy/monitoring/scripts/backup-grafana-state.sh
grep -Fq -- '--volumes-from "${GRAFANA_CONTAINER}:ro"' deploy/monitoring/scripts/backup-grafana-state.sh
grep -Fq 'chmod 600' deploy/monitoring/scripts/backup-grafana-state.sh
grep -Fq '/api/v1/provisioning/contact-points' deploy/monitoring/scripts/verify-monitoring.sh
grep -Fq '/api/v1/provisioning/alert-rules/${rule_uid}' deploy/monitoring/scripts/verify-monitoring.sh
grep -Fq 'grafana-dev-external-health' deploy/monitoring/scripts/verify-monitoring.sh
grep -Fq 'grafana-dev-app-error-logs' deploy/monitoring/scripts/verify-monitoring.sh
grep -Fq 'nooook-discord' deploy/monitoring/scripts/verify-monitoring.sh
grep -Fq 'reading-garden-discord-dev' deploy/monitoring/scripts/verify-monitoring.sh
grep -Fq 'reading-garden-discord-prod' deploy/monitoring/scripts/verify-monitoring.sh
grep -Fq '/api/dashboards/uid/reading-garden-dev-overview' deploy/monitoring/scripts/verify-monitoring.sh
grep -Fq '/api/dashboards/uid/reading-garden-prod-overview' deploy/monitoring/scripts/verify-monitoring.sh
grep -Fq '/api/datasources/uid/loki/health' deploy/monitoring/scripts/verify-monitoring.sh
grep -Fq '/api/dashboards/uid/reading-garden-logs' deploy/monitoring/scripts/verify-monitoring.sh
grep -Fq '/loki/api/v1/query_range' deploy/monitoring/scripts/verify-monitoring.sh
grep -Fq '"result":[{' deploy/monitoring/scripts/verify-monitoring.sh
if rg -n 'assert_loki_query_has_result .*source="docker"' deploy/monitoring/scripts/verify-monitoring.sh; then
    echo "monitoring verification must not require app container logs on every run" >&2
    exit 1
fi
grep -Fq 'Dev Avg Latency' deploy/monitoring/scripts/verify-monitoring.sh
grep -Fq 'Dev p95 Latency' deploy/monitoring/scripts/verify-monitoring.sh
grep -Fq 'Dev Recent Error Logs' deploy/monitoring/scripts/verify-monitoring.sh
grep -Fq 'Dev Active Alerts' deploy/monitoring/scripts/verify-monitoring.sh
grep -Fq 'Prod Avg Latency' deploy/monitoring/scripts/verify-monitoring.sh
grep -Fq 'Prod p95 Latency' deploy/monitoring/scripts/verify-monitoring.sh
grep -Fq 'Prod Recent Error Logs' deploy/monitoring/scripts/verify-monitoring.sh
grep -Fq 'Prod Active Alerts' deploy/monitoring/scripts/verify-monitoring.sh
grep -Fq 'Caddy p95 Duration' deploy/monitoring/scripts/verify-monitoring.sh
grep -Fq 'App Container Logs' deploy/monitoring/scripts/verify-monitoring.sh
grep -Fq 'Prod App Logs' deploy/monitoring/scripts/verify-monitoring.sh
grep -Fq 'Dev App Logs' deploy/monitoring/scripts/verify-monitoring.sh
grep -Fq 'Prod Recent Error Logs' deploy/monitoring/grafana/dashboards/reading-garden-logs.json
grep -Fq 'Dev Recent Error Logs' deploy/monitoring/grafana/dashboards/reading-garden-logs.json
grep -Fq '|~ \"(?i)(\\\\bERROR\\\\b|exception|traceback|NullPointerException|IllegalStateException|DataAccessException|ResponseStatusException)\"' deploy/monitoring/grafana/dashboards/reading-garden-logs.json
grep -Fq '!~ \"(?i)(no error|error page|error dispatch)\"' deploy/monitoring/grafana/dashboards/reading-garden-logs.json
grep -Fq 'FCM (HTTP error|send failed): .*?(fcmErrorCode|errorCode)=(UNREGISTERED|messaging/registration-token-not-registered)' deploy/monitoring/grafana/dashboards/reading-garden-logs.json
grep -Fq 'Caddy Systemd Logs' deploy/monitoring/scripts/verify-monitoring.sh
grep -Fq 'Prod Caddy Access Logs' deploy/monitoring/scripts/verify-monitoring.sh
grep -Fq 'Dev Caddy Access Logs' deploy/monitoring/scripts/verify-monitoring.sh
grep -Fq '/api/v1/alerts' deploy/monitoring/scripts/check-alerts.sh
grep -Fq '/api/v1/rules' deploy/monitoring/scripts/check-alerts.sh
grep -Fq 'python3' deploy/monitoring/scripts/check-alerts.sh
grep -Fq 'Active alerts' deploy/monitoring/scripts/check-alerts.sh
grep -Fq 'Expected alert rules' deploy/monitoring/scripts/check-alerts.sh
grep -Fq 'PostgresExporterDown' deploy/monitoring/scripts/check-alerts.sh
grep -Fq 'PostgresConnectionsHigh' deploy/monitoring/scripts/check-alerts.sh
grep -Fq 'PostgresDeadlocksDetected' deploy/monitoring/scripts/check-alerts.sh
grep -Fq '"legendFormat": "{{datname}}"' deploy/monitoring/grafana/dashboards/reading-garden-postgres-overview.json
grep -Fq '"legendFormat": "{{status}}"' deploy/monitoring/grafana/dashboards/reading-garden-dev-overview.json
grep -Fq '"legendFormat": "{{status}}"' deploy/monitoring/grafana/dashboards/reading-garden-prod-overview.json
grep -Fq '"legendFormat": "{{id}}"' deploy/monitoring/grafana/dashboards/reading-garden-dev-overview.json
grep -Fq '"legendFormat": "{{id}}"' deploy/monitoring/grafana/dashboards/reading-garden-prod-overview.json
grep -Fq '"legendFormat": "{{code}}"' deploy/monitoring/grafana/dashboards/reading-garden-dev-overview.json
grep -Fq '"legendFormat": "{{code}}"' deploy/monitoring/grafana/dashboards/reading-garden-prod-overview.json
grep -Fq './scripts/check-alerts.sh' deploy/monitoring/RUNBOOK.md
if rg -n 'PROD_BASE_URL|readinggarden.duckdns.org/v3/api-docs' deploy/monitoring/scripts/verify-monitoring.sh; then
    echo "monitoring verification must not require prod live docs" >&2
    exit 1
fi
grep -Fq 'PostgreSQL Metrics' deploy/monitoring/RUNBOOK.md
grep -Fq 'reading_garden_monitoring' deploy/monitoring/RUNBOOK.md
grep -Fq 'POSTGRES_EXPORTER_PASSWORD' deploy/monitoring/RUNBOOK.md
grep -Fq './scripts/verify-monitoring.sh' deploy/monitoring/RUNBOOK.md
grep -Fq 'ReadingGarden Logs' deploy/monitoring/RUNBOOK.md
grep -Fq '{container=~"reading-garden-prod-.*"}' deploy/monitoring/RUNBOOK.md
grep -Fq 'Prod Recent Error Logs' deploy/monitoring/RUNBOOK.md
grep -Fq 'Dev Recent Error Logs' deploy/monitoring/RUNBOOK.md
grep -Fq 'logs_dashboard' deploy/monitoring/RUNBOOK.md
grep -Fq 'stale FCM token cleanup logs' deploy/monitoring/RUNBOOK.md
grep -Fq './scripts/backup-grafana-state.sh' deploy/monitoring/RUNBOOK.md
grep -Fq '/opt/infra/monitoring/backups' deploy/monitoring/RUNBOOK.md
grep -Fq 'self-log loops' deploy/monitoring/RUNBOOK.md
grep -Fq 'Alertmanager Later' deploy/monitoring/RUNBOOK.md

if rg -n 'discord(app)?\.com/api/webhooks/[0-9]+/[A-Za-z0-9_-]+' deploy/monitoring; then
    echo "Discord webhook URLs must not be committed" >&2
    exit 1
fi

if rg -n 'alertmanager' deploy/monitoring; then
    echo "deferred services must not be committed in this phase" >&2
    exit 1
fi

echo "PASS"
