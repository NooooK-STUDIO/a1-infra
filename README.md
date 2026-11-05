# A1 Infrastructure

Infrastructure and deployment assets for services running on OCI A1.

## Contents

- `deploy/docker-compose.oci.yml`: blue/green application container template.
- `deploy/blue-green-deploy.sh`: blue/green cutover script for host-managed Caddy.
- `deploy/host-caddy/`: host `systemd` Caddy configuration templates.
- `deploy/postgres/` and `deploy/docker-compose.postgres-shared.yml`: shared PostgreSQL bootstrap assets.
- `deploy/monitoring/`: Monitoring for ReadingGarden, PawTogether, and shared services using Prometheus, Grafana, Loki, Tempo, Alloy, and exporters. Grafana forwards firing Prometheus alerts to the existing Discord receivers.
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
Prometheus keeps firing alerts active for two minutes after recovery so Grafana's
60-second polling and 30-second notification wait do not miss brief incidents.
Recovery notifications are delayed by that hold and the normal notification schedule.
Application overviews show only that application's health, traffic, runtime resources,
and connection pool. Overview links retain the selected time range when moving
between applications, shared infrastructure, PostgreSQL, and application logs.
Both application slots export HTTP request histograms through their Compose
environment settings, providing the buckets needed by the p95 response-time panels.
Copy the updated app Compose template and redeploy the current application image
to enable this on existing containers; monitoring verification checks for buckets.
Each application log dashboard shows errors, application output, and its own HTTP
access logs without duplicate application panels. Caddy service events belong to
the shared log dashboard. Log dashboard links retain the selected time range when
returning to an overview or moving between log dashboards.
Application output includes older logs collected before service labels were added.
An empty log panel can mean no matching entries in the selected range or missing
collection; it does not by itself prove the application is healthy.

## Request traces

Both backends can opt in to OpenTelemetry Java agent instrumentation without
rebuilding their application image. HTTP and JDBC spans travel through Alloy to
single-node Tempo. Trace storage is a Docker volume with 72-hour retention; it is
local diagnostic storage, not an audit archive. Agent 2.33.1 is pinned and checked
against its release SHA-256 before installation. Java 25 is supported upstream.

1. Deploy the monitoring assets and start Tempo, Alloy, Grafana, and Prometheus.
   Alloy's OTLP HTTP receiver binds only the shared application bridge gateway,
   `172.24.0.1:4318`. Verify the gateway with `docker network inspect
   reading-garden-shared-backend`; set `OTLP_HTTP_LISTEN_ADDRESS` in monitoring
   `.env` if it differs. Tempo's query and gRPC endpoints bind only loopback.
   On the OCI host, run `sudo /opt/infra/monitoring/scripts/configure-tracing-firewall.sh`
   once to allow only the shared bridge/subnet → gateway TCP 4318 connection. This
   validates and adds just that rule to the existing `/etc/iptables/rules.v4`, so
   it survives reboot without snapshotting or reloading unrelated Docker rules.
   Rerun it if the shared Docker network is recreated.
2. Copy `deploy/docker-compose.oci.yml` to each application's `docker-compose.yml`.
   Run the installer with the existing app directory and stable service name:
   ```bash
   /opt/infra/monitoring/scripts/enable-app-tracing.sh /opt/apps/reading-garden/prod reading-garden-kotlin
   /opt/infra/monitoring/scripts/enable-app-tracing.sh /opt/apps/pawtogether/prod pawtogether
   ```
   Set `TRACING_OTLP_ENDPOINT=http://<bridge-gateway>:4318` when changing the gateway.
   The installer preserves existing JVM/logging options by refusing conflicting
   files. Review a conflict without printing environment values. `.tracing.env`
   and `observability/` are app-local and survive ordinary bootstrap/deploy runs.
   Compose 2.24+ is required for the optional env file.
3. Redeploy each current image through the usual blue/green script. Only newly
   started JVMs load the agent. Both slots read the same tracing configuration.
4. Open an application's **Traces** dashboard link, or select **Explore → Tempo**.
   Search `{ resource.service.name = "reading-garden-kotlin" }` or
   `{ resource.service.name = "pawtogether" }`. Open a result to inspect its spans.
   Application logs with `trace_id` expose a **View trace** link; a span's logs link
   searches Loki using the same service name and trace ID. Startup/background logs
   without an active span do not have a request trace, and quiet requests may not
   produce application log lines.

The initial sampler records all new root requests and honors incoming parent
sampling decisions. Metrics remain in Prometheus and logs remain in Loki; the
agent's metrics/log exporters are disabled. Alloy removes full/query URLs and SQL
statement attributes before storage, preserving routes, DB operations, durations,
and errors. This does not sanitize arbitrary application logs or exception text.
No request/response-body or HTTP-header capture is enabled. Historical traces
cannot be reconstructed from existing logs or metrics.

To disable tracing, remove the app's `.tracing.env` and redeploy its current image.
The optional env file keeps future uninstrumented app deployments working. Retain
the agent directory until both instrumented slots have stopped. Tempo is scraped
by Prometheus and included in the shared monitoring availability alert.

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

The trace integration test starts isolated Alloy and Tempo containers and checks
OTLP delivery, trace lookup, and removal of synthetic sensitive attributes:

```bash
python3 deploy/tests/tracing_pipeline_test.py
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
