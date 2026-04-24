# A1 Infrastructure

Infrastructure and deployment assets for services running on OCI A1.

## Contents

- `deploy/docker-compose.oci.yml`: blue/green application container template.
- `deploy/blue-green-deploy.sh`: blue/green cutover script for host-managed Caddy.
- `deploy/host-caddy/`: host `systemd` Caddy configuration templates.
- `deploy/postgres/` and `deploy/docker-compose.postgres-shared.yml`: shared PostgreSQL bootstrap assets.
- `deploy/monitoring/`: Prometheus, Grafana, Alertmanager, cAdvisor, node-exporter, and blackbox exporter assets.
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
