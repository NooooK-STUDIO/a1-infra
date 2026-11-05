# A1 Infrastructure

Infrastructure and deployment assets for services running on OCI A1.

## Contents

- `deploy/docker-compose.oci.yml`: blue/green application container template.
- `deploy/blue-green-deploy.sh`: blue/green cutover script for host-managed Caddy.
- `deploy/host-caddy/`: host `systemd` Caddy configuration templates.
- `deploy/postgres/` and `deploy/docker-compose.postgres-shared.yml`: shared PostgreSQL bootstrap assets.
- `deploy/monitoring/`: Monitoring for ReadingGarden, PawTogether, and shared services using Prometheus, Grafana, Loki, Alloy, and exporters. Grafana forwards firing Prometheus alerts to the existing Discord receivers.
- `deploy/tests/`: shell tests for deployment configuration.

## Grafana organization

Dashboards and Grafana alert rules are grouped by ownership:

- `A1 Shared`: A1 Shared Overview for host/proxy/collector health, Shared PostgreSQL
  Overview for database capacity and activity, A1 Shared Logs for Caddy service
  events, and the Prometheus alert forwarder.
- `ReadingGarden`: production overview, application logs, and application log alerts.
- `PawTogether`: production overview, application logs, and application log alerts.

Dashboard and alert UIDs stay unchanged so existing links keep working. The shared
PostgreSQL dashboard retains the legacy `reading-garden-postgres-overview` UID.
Notification routing continues to use service/environment labels.
ReadingGarden production alerts use `reading-garden-discord-prod`, PawTogether
production alerts use `pawtogether-discord-prod`, and shared infrastructure alerts
use the default `nooook-discord` receiver. Set `GRAFANA_DISCORD_PAW_WEBHOOK_URL` in
the host's monitoring `.env` before deploying; all three webhook values remain
host-local secrets. Each receiver sends both firing and resolved notifications.
Application overviews show only that application's health, traffic, runtime resources,
and connection pool. Overview links retain the selected time range when moving
between applications, shared infrastructure, PostgreSQL, and application logs.
Each application log dashboard shows errors, application output, and its own HTTP
access logs without duplicate application panels. Caddy service events belong to
the shared log dashboard. Log dashboard links retain the selected time range when
returning to an overview or moving between log dashboards.
Application output includes older logs collected before service labels were added.
An empty log panel can mean no matching entries in the selected range or missing
collection; it does not by itself prove the application is healthy.

## Verification

Run deployment configuration tests from the repository root:

```bash
for test_script in deploy/tests/*.sh; do
  bash "$test_script"
done
```

The alert-delivery integration test runs real Grafana and Prometheus against a local
Discord-compatible receiver, without contacting Discord:

```bash
python3 deploy/tests/monitoring_alert_delivery_test.py
```

## Secrets

Do not commit runtime `.env` files, service account JSON files, SSH keys, or host-specific credentials. Use the provided example files as templates only.

## Development environment retirement

ReadingGarden dev and PawTogether dev are retired. Both production environments and
shared infrastructure remain configured. The host Caddy bootstrap removes the retired
development sites and upstreams;
it does not delete access logs, databases, roles, or secret files. The monitoring
provider removes the retired file-provisioned dashboard, while Grafana alert and
contact point tombstones remove their provisioned resources. Apply the host Caddy,
PostgreSQL, and monitoring targets to propagate these changes; monitoring deployment
replaces its managed config directories. Existing database data, credentials, logs,
and historical monitoring data require separate teardown under the operator's plan.
