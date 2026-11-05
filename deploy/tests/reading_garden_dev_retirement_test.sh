#!/usr/bin/env bash
set -euo pipefail

ruby <<'RUBY'
require 'yaml'
require 'json'
alerts = YAML.load_file('deploy/monitoring/grafana/provisioning/alerting/reading-garden-alerts.yml')
expected = %w[grafana-dev-external-health grafana-dev-local-caddy-health grafana-dev-public-external-health grafana-dev-app-metrics grafana-dev-app-error-logs]
deleted = alerts.fetch('deleteRules').select { |r| r['orgId'] == 1 }.map { |r| r.fetch('uid') }
raise 'missing Grafana rule tombstones' unless (expected - deleted).empty?
rules = alerts.fetch('groups').flat_map { |g| g.fetch('rules') }
raise 'retired rules remain active' unless (rules.map { |r| r.fetch('uid') } & expected).empty?
raise 'production rules missing' unless rules.any? { |r| r['uid'] == 'prometheus-alert-forwarder' }
contacts = YAML.load_file('deploy/monitoring/grafana/provisioning/alerting/contact-points.yml')
raise 'missing contact point tombstone' unless contacts.fetch('deleteContactPoints').any? { |r| r['orgId'] == 1 && r['uid'] == 'reading-garden-discord-dev' }
raise 'retired contact point active' if contacts.fetch('contactPoints').any? { |r| r['name'] == 'reading-garden-discord-dev' }
raise 'production contact point missing' unless contacts.fetch('contactPoints').any? { |r| r['name'] == 'reading-garden-discord-prod' }
policy = YAML.load_file('deploy/monitoring/grafana/provisioning/alerting/notification-policies.yml')
routes = policy.fetch('policies').flat_map { |r| r.fetch('routes') }
raise 'retired route active' if routes.any? { |r| r['receiver'] == 'reading-garden-discord-dev' }
raise 'production route missing' unless routes.any? { |r| r['receiver'] == 'reading-garden-discord-prod' }
config = YAML.load_file('deploy/monitoring/prometheus/prometheus.yml')
raise 'retired scrape job active' if config.fetch('scrape_configs').any? { |c| c['job_name'] == 'reading-garden-dev-app' }
raise 'production scrape job missing' unless config.fetch('scrape_configs').any? { |c| c['job_name'] == 'reading-garden-prod-app' }
shared = YAML.load_file('deploy/monitoring/prometheus/rules/shared-infra.yml').fetch('groups').flat_map { |g| g.fetch('rules') }.map { |r| r.fetch('alert') }
raise 'shared alerts missing' unless (%w[CaddyMetricsDown HostMemoryHigh PostgresExporterDown PostgresConnectionsHigh PostgresDeadlocksDetected] - shared).empty?
%w[reading-garden-logs.json reading-garden-postgres-overview.json].each do |file|
  dashboard = JSON.parse(File.read("deploy/monitoring/grafana/dashboards/#{file}"))
  raise 'retired panel remains' if dashboard.fetch('panels').any? { |panel| panel.fetch('title', '').start_with?('Dev ') }
end
RUBY

for file in deploy/monitoring/grafana/dashboards/reading-garden-dev-overview.json deploy/monitoring/prometheus/rules/reading-garden-dev.yml deploy/host-caddy/sites/reading-garden-dev.caddy; do
  test ! -e "$file"
done
if rg -n 'READING_GARDEN_DEV_|reading_garden_dev|readinggarden-dev\.duckdns\.org|reading-garden-dev-app|GRAFANA_DISCORD_DEV_WEBHOOK_URL' deploy/monitoring deploy/bootstrap-shared-postgres.sh deploy/postgres/init deploy/docker-compose.postgres-shared.yml .github/workflows; then
  echo 'retired ReadingGarden dev configuration remains' >&2
  exit 1
fi
echo PASS
