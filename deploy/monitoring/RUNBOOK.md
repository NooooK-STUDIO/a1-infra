# ReadingGarden Monitoring Runbook

## Host Layout

- Monitoring directory: `/opt/infra/monitoring`
- Compose file: `/opt/infra/monitoring/docker-compose.yml`
- Host-local env file: `/opt/infra/monitoring/.env`
- Grafana and Prometheus host ports are bound to `127.0.0.1` only.

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
- Prometheus active targets include `reading-garden-dev-app`, `caddy`, `node-exporter`, `cadvisor`, and `blackbox-http`.
- The app scrape uses localhost management ports `19090` and `19091`.
- Grafana Prometheus datasource is healthy.
- dev `/api/health` and `/v3/api-docs` respond.

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

## Loki And Alloy Later

Add Loki and Alloy after metrics and DB monitoring are stable. Use Alloy to collect Docker container logs and host Caddy journald logs.

## Alertmanager Later

Add Alertmanager only if Grafana Alerting is not enough for grouping, deduplication, silencing, inhibition, repeat intervals, or multi-receiver routing.
