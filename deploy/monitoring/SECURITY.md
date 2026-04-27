# Monitoring Security Notes

## Sensitive access

The monitoring stack uses host-level access in these places:

- node-exporter runs with `pid: host` and mounts the host root filesystem at `/host` read-only so it can collect host CPU, memory, disk, and filesystem metrics.
- cAdvisor mounts Docker and kernel paths so it can collect container resource metrics.
- Alloy mounts the Docker socket read-only so it can discover containers and read Docker logs.
- Alloy mounts `/var/log/journal` and `/run/log/journal` read-only so it can read Caddy systemd journal logs.

These mounts are sensitive because they expose host and container metadata to the monitoring containers.

## Mitigations

- Grafana and Prometheus bind only to `127.0.0.1`.
- Loki binds only to `127.0.0.1`.
- node-exporter, cAdvisor, and blackbox_exporter publish only `127.0.0.1` host ports.
- Caddy metrics are exposed only on `http://127.0.0.1:2019/metrics` and are not exposed through a public site.
- No Discord webhook, database credential, postgres_exporter, or Alertmanager service is committed.
- Loki retains local logs for 72 hours.

## Rollback

To remove phase 1 monitoring access, stop the monitoring stack:

```bash
docker compose -f /opt/infra/monitoring/docker-compose.yml down
```

Do not delete volumes unless explicitly approved.
