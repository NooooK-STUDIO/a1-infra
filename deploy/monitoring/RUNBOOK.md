# ReadingGarden Monitoring Runbook

## Host Layout

- Monitoring directory: `/opt/infra/monitoring`
- Compose file: `/opt/infra/monitoring/docker-compose.yml`
- Host-local env file: `/opt/infra/monitoring/.env`
- Grafana, Prometheus, and Loki host ports are bound to `127.0.0.1` only.

## SSH Tunnel

```bash
ssh -i <ssh-key-path> -L 3000:127.0.0.1:3000 <ssh-user>@<oci-host>
```

Open `http://localhost:3000`.

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
```

## Verify

```bash
cd /opt/infra/monitoring
./scripts/verify-monitoring.sh
```

Expected checks:

- Prometheus readiness succeeds.
- Prometheus active targets include `reading-garden-dev-app`, `reading-garden-prod-app`, `caddy`, `node-exporter`, `cadvisor`, and `blackbox-http`.
- Loki is ready and has Docker container logs plus Caddy systemd logs.
- The dev app scrape uses localhost management ports `19090` and `19091`.
- The prod app scrape uses localhost management ports `19080` and `19081`; at least one blue/green target must be up.
- Grafana Prometheus and Loki datasources are healthy.
- Grafana includes `ReadingGarden Dev Overview`, `ReadingGarden Prod Overview`, and `ReadingGarden Logs`.
- dev `/api/health` and `/v3/api-docs` respond.

## Logs

Open Grafana through the SSH tunnel and use the `ReadingGarden Logs` dashboard.

Useful Loki queries:

```logql
{source="docker"}
{container=~"reading-garden-prod-.*"}
{container=~"reading-garden-dev-.*"}
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

## Rollback

This stops only the monitoring stack:

```bash
docker compose -f /opt/infra/monitoring/docker-compose.yml down
```

Do not delete monitoring volumes unless explicitly approved.

## Discord Later

Add Grafana Alerting and a Discord contact point in a separate change after the webhook exists. Keep the webhook URL only in `/opt/infra/monitoring/.env`.

## postgres_exporter Later

Add postgres_exporter after creating a dedicated PostgreSQL monitoring role. Track `pg_up`, connections, locks, cache hit rate, database size, and baseline transaction/query metrics.

## Alertmanager Later

Add Alertmanager only if Grafana Alerting is not enough for grouping, deduplication, silencing, inhibition, repeat intervals, or multi-receiver routing.
