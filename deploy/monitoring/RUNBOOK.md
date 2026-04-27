# ReadingGarden Monitoring Runbook

## Host Layout

- Monitoring directory: `/opt/infra/monitoring`
- Compose file: `/opt/infra/monitoring/docker-compose.yml`
- Host-local env file: `/opt/infra/monitoring/.env`
- Grafana, Prometheus, and Loki host ports are bound to `127.0.0.1` only.

## Grafana Access

Grafana is published through host Caddy at:

- `https://nooook-monitoring.duckdns.org`

The Grafana process still listens on `127.0.0.1:3000` only. Caddy terminates public HTTPS and proxies to that loopback port.

SSH tunnel access remains available for fallback:

```bash
ssh -i <ssh-key-path> -L 3000:127.0.0.1:3000 <ssh-user>@<oci-host>
```

## Deploy Or Update

From the repository root:

```bash
rsync -av --delete \
  --exclude '.env' \
  -e 'ssh -i <ssh-key-path>' \
  deploy/monitoring/ \
  <ssh-user>@<oci-host>:/opt/infra/monitoring/

ssh -i <ssh-key-path> <ssh-user>@<oci-host> \
  'cd /opt/infra/monitoring && cp docker-compose.monitoring.yml docker-compose.yml && chmod +x scripts/*.sh'
```

On the host:

```bash
cd /opt/infra/monitoring
./scripts/bootstrap-monitoring.sh
```

## Required Host `.env`

`/opt/infra/monitoring/.env` must exist on the host and must not be committed:

```dotenv
GRAFANA_HOST_PORT=3000
GRAFANA_ADMIN_USER=admin
GRAFANA_ADMIN_PASSWORD=<host-local-password>
GRAFANA_ROOT_URL=https://nooook-monitoring.duckdns.org
NOOOOK_DISCORD_WEBHOOK_URL=<host-local-discord-webhook-url>
GRAFANA_DISCORD_DEV_WEBHOOK_URL=<host-local-dev-discord-webhook-url>
GRAFANA_DISCORD_PROD_WEBHOOK_URL=<host-local-prod-discord-webhook-url>
POSTGRES_EXPORTER_PASSWORD=<host-local-postgres-exporter-password>
```

## Verify

```bash
cd /opt/infra/monitoring
./scripts/verify-monitoring.sh
```

Expected checks:

- Prometheus readiness succeeds.
- Prometheus active targets include `reading-garden-dev-app`, `reading-garden-prod-app`, `caddy`, `node-exporter`, `cadvisor`, `postgres-exporter`, and `blackbox-http`.
- Loki is ready and has Docker container logs plus Caddy systemd logs.
- The dev app scrape uses localhost management ports `19090` and `19091`.
- The prod app scrape uses localhost management ports `19080` and `19081`; at least one blue/green target must be up.
- Grafana Prometheus and Loki datasources are healthy.
- Grafana Alerting has the Discord contact point, notification policy, and provisioned ReadingGarden alert rules.
- Grafana includes `ReadingGarden Dev Overview`, `ReadingGarden Prod Overview`, `ReadingGarden Postgres Overview`, and `ReadingGarden Logs`.
- dev `/api/health` and `/v3/api-docs` respond.

## Logs

Open Grafana through the SSH tunnel and use the `ReadingGarden Logs` dashboard.

The dashboard starts with `Prod Recent Error Logs` and `Dev Recent Error Logs`.
These panels use the same filter as the Discord log alerts, so they are the
first place to check when `GrafanaProdAppErrorLogsDetected` or
`GrafanaDevAppErrorLogsDetected` fires. The Discord payload includes a
`logs_dashboard` annotation that opens this dashboard for the last 30 minutes.

Useful Loki queries:

```logql
{source="docker"}
{container=~"reading-garden-prod-.*"}
{container=~"reading-garden-dev-.*"}
{container=~"reading-garden-prod-.*"} |~ "(?i)(\\bERROR\\b|exception|traceback|NullPointerException|IllegalStateException|DataAccessException|ResponseStatusException)" !~ "(?i)(no error|error page|error dispatch)"
{container=~"reading-garden-dev-.*"} |~ "(?i)(\\bERROR\\b|exception|traceback|NullPointerException|IllegalStateException|DataAccessException|ResponseStatusException)" !~ "(?i)(no error|error page|error dispatch)"
{container="reading-garden-prod-blue"}
{container="reading-garden-prod-green"}
{unit="caddy.service"}
{source="caddy_access",env="prod"}
{source="caddy_access",env="dev"}
{container="reading-garden-dev-blue"}
{container="reading-garden-dev-green"}
```

ReadingGarden app container logs are collected through the Docker socket. Monitoring containers and shared PostgreSQL are intentionally excluded to avoid self-log loops and noisy database history. Host Caddy logs are collected from the systemd journal and labeled with `unit="caddy.service"`.
Caddy access logs are written per public environment to `/var/log/caddy/reading-garden-prod-access.log` and `/var/log/caddy/reading-garden-dev-access.log`, then collected by Alloy with `source="caddy_access"` and `env="prod"` or `env="dev"`.

## Alert Status

Use this while tuning thresholds before adding notifications:

```bash
cd /opt/infra/monitoring
./scripts/check-alerts.sh
```

The script reads Prometheus `/api/v1/rules` and `/api/v1/alerts`, prints all expected Phase 1 alert rules, and exits non-zero when any expected rule is missing, unhealthy, pending, or firing.

## Backup

Provisioned dashboards, datasources, alert rules, contact points, and
notification policies are stored in this repository. Grafana runtime state is
stored in the host-local Docker volume mounted at `/var/lib/grafana` and can
contain encrypted secrets, UI preferences, and local state. Keep backups on the
host and do not commit them.

```bash
cd /opt/infra/monitoring
./scripts/backup-grafana-state.sh
```

By default this writes a mode `600` archive under
`/opt/infra/monitoring/backups`. Override `BACKUP_DIR` only with another
host-local, non-public path.

## Rollback

This stops only the monitoring stack:

```bash
docker compose -f /opt/infra/monitoring/docker-compose.yml down
```

Do not delete monitoring volumes unless explicitly approved.

## Discord Alerts

Discord alert delivery uses Grafana Alerting. Keep the webhook URL only in `/opt/infra/monitoring/.env` as `NOOOOK_DISCORD_WEBHOOK_URL`; never commit the real URL.

Grafana provisions:

- `nooook-discord` contact point.
- `reading-garden-discord-dev` and `reading-garden-discord-prod` contact points.
- `reading-garden-discord` notification template group for concise Discord messages.
- Notification policy routes `env=dev` alerts to the dev Discord webhook and `env=prod` alerts to the prod Discord webhook.
- Host/common alerts use the default `nooook-discord` contact point.
- Grafana-managed alert rules for dev/prod external health, dev/prod app metrics, dev/prod app error logs, Caddy metrics, PostgreSQL metrics, and host disk usage.

Prod alert thresholds are intentionally more sensitive than dev for user-facing
signals:

- `Prod5xxRateHigh`: any 5xx rate for 1 minute.
- `ProdAvgLatencyHigh`: average HTTP latency above 750 ms for 5 minutes.
- `ProdHikariPendingConnections`: pending DB pool connections for 2 minutes.
- `GrafanaProdAppErrorLogsDetected`: matching app error logs for 1 minute.
- `GrafanaDevAppErrorLogsDetected`: matching app error logs for 2 minutes.

## PostgreSQL Metrics

PostgreSQL metrics use `postgres_exporter` on `127.0.0.1:9187`. The exporter
uses host networking and connects to shared PostgreSQL through `127.0.0.1:15432/postgres` as the
dedicated `reading_garden_monitoring` role.

Keep the exporter password in both host-local places:

- `/opt/infra/postgresql/secrets/postgres_exporter.password`
- `/opt/infra/monitoring/.env` as `POSTGRES_EXPORTER_PASSWORD`

`deploy/bootstrap-shared-postgres.sh` creates or updates the
`reading_garden_monitoring` role and grants `pg_monitor` when
`POSTGRES_EXPORTER_PASSWORD` is available. The `ReadingGarden Postgres Overview`
dashboard tracks `pg_up`, connection usage, database size, deadlocks, and
transaction rate.

## Alertmanager Later

Add Alertmanager only if Grafana Alerting is not enough for grouping, deduplication, silencing, inhibition, repeat intervals, or multi-receiver routing.
