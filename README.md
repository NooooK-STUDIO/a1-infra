# A1 Infrastructure

Infrastructure and deployment assets for services running on OCI A1.

## Contents

- `deploy/docker-compose.oci.yml`: blue/green application container template.
- `deploy/blue-green-deploy.sh`: blue/green cutover script for host-managed Caddy.
- `deploy/host-caddy/`: host `systemd` Caddy configuration templates.
- `deploy/postgres/` and `deploy/docker-compose.postgres-shared.yml`: shared PostgreSQL bootstrap assets.
- `deploy/monitoring/`: Phase 1 monitoring assets for Prometheus, Grafana, cAdvisor, node-exporter, and blackbox exporter. Alertmanager is deferred.
- `deploy/tests/`: shell tests for deployment configuration.

## Verification

Run deployment configuration tests from the repository root:

```bash
for test_script in deploy/tests/*.sh; do
  bash "$test_script"
done
```

## Secrets

Do not commit runtime `.env` files, service account JSON files, SSH keys, or host-specific credentials. Use the provided example files as templates only.

## ReadingGarden dev retirement

ReadingGarden prod, PawTogether dev/prod, and shared infrastructure remain configured.
The host Caddy bootstrap removes only the retired ReadingGarden dev site and upstream;
it does not delete access logs, databases, roles, or secret files. The monitoring
provider removes the retired file-provisioned dashboard, while Grafana alert and
contact point tombstones remove their provisioned resources. Apply the host Caddy,
PostgreSQL, and monitoring targets to propagate these changes; monitoring deployment
replaces its managed config directories. Existing database data, credentials, logs,
and historical monitoring data require separate teardown under the operator's plan.
