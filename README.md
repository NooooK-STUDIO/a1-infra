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

- `A1 Shared`: Shared PostgreSQL Overview and the Prometheus alert forwarder.
- `ReadingGarden`: production overview, application logs, and application log alerts.
- `PawTogether`: production overview, application logs, and application log alerts.

Dashboard and alert UIDs stay unchanged so existing links keep working. The shared
PostgreSQL dashboard retains the legacy `reading-garden-postgres-overview` UID.
Notification routing continues to use service/environment labels.

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
