#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT_DIR"

ruby <<'RUBY'
require 'yaml'
require 'json'
root = 'deploy/monitoring'
def assert(condition, message)
  abort(message) unless condition
end
config = YAML.load_file("#{root}/prometheus/prometheus.yml")
jobs = config.fetch('scrape_configs').to_h { |j| [j.fetch('job_name'), j] }
apps = {'reading-garden' => ['reading-garden-kotlin', %w[127.0.0.1:19080 127.0.0.1:19081], 'readinggarden.duckdns.org'], 'pawtogether' => ['pawtogether', %w[127.0.0.1:19110 127.0.0.1:19111], 'pawtogether.duckdns.org']}
apps.each do |project, (service, targets, hostname)|
  app = jobs.fetch("#{project}-prod-app")
  assert(app['metrics_path'] == '/actuator/prometheus' && app['static_configs'][0]['targets'] == targets && app['static_configs'][0]['labels']['service'] == service, "#{project} app scrape")
  %w[blackbox-public-http blackbox-local-caddy].each do |name|
    target = jobs.fetch(name).fetch('static_configs').find { |t| t['labels']['service'] == service }
    assert(target && (name == 'blackbox-public-http' ? target['targets'].include?("https://#{hostname}/api/health") : target['labels']['hostname'] == hostname && target['targets'].include?('https://127.0.0.1/api/health')), "#{project} #{name}")
  end
  rules = YAML.load_file("#{root}/prometheus/rules/#{project}-prod.yml").fetch('groups').first.fetch('rules')
  assert(rules.size == 6 && rules.all? { |r| r['labels']['service'] == service }, "#{project} rules")
  assert(rules[0]['expr'].include?('or vector(0)') && rules[1..2].all? { |r| r['expr'].include?("service=\"#{service}\"") && r['expr'].include?('absent(') }, "#{project} absent and probe isolation")
  dash = JSON.parse(File.read("#{root}/grafana/dashboards/#{project}-logs.json"))
  assert(dash['panels'].to_s.include?(service), "#{project} dashboard labels")
end
%w[alloy loki grafana].zip(%w[12345 3100 3000]).each { |name, port| assert(jobs.fetch(name)['static_configs'][0]['targets'] == ["127.0.0.1:#{port}"], "#{name} scrape") }
alloy = File.read("#{root}/alloy/config.alloy")
assert(alloy.include?('(reading-garden|pawtogether)-prod-.*') && apps.keys.all? { |p| alloy.include?("/var/log/caddy/#{p}-prod-access.log") } && apps.values.all? { |v| alloy.include?(v[0]) }, 'log collection')
# Alloy positions are keyed by path and all non-reserved source labels.
file_match = alloy[/local\.file_match "caddy_access" \{(.*?)\n\}/m, 1]
assert(file_match, 'Caddy file discovery must exist')
targets = file_match.scan(/\{([^{}]*)\}/m).map do |body|
  body.first.scan(/(\w+)\s*=\s*"([^"]*)"/).to_h
end
old_labels = {'env' => 'prod', 'host' => 'oracle-a1', 'service' => 'caddy', 'source' => 'caddy_access'}
apps.each_key do |project|
  target = targets.find { |t| t['__path__'] == "/var/log/caddy/#{project}-prod-access.log" }
  assert(target && target.reject { |key, _| key.start_with?('__') } == old_labels, "#{project} source labels must preserve the old positions key")
end
source = alloy[/loki\.source\.file "caddy_access" \{(.*?)\n\}/m, 1]
assert(source && source.include?('forward_to = [loki.relabel.caddy_access.receiver]'), 'File logs must pass through downstream relabeling')
relabel = alloy[/loki\.relabel "caddy_access" \{(.*?)\n\}/m, 1]
assert(relabel && relabel.include?('forward_to = [loki.write.local.receiver]'), 'Relabeled Caddy logs must reach Loki')
relabel_rules = relabel.scan(/rule \{(.*?)\}/m).map(&:first)
apps.each do |project, (service, _, _)|
  labels = old_labels.merge('filename' => "/var/log/caddy/#{project}-prod-access.log")
  relabel_rules.each do |rule|
    values = rule.scan(/(\w+)\s*=\s*("(?:\\.|[^"\\])*"|\["\w+"\])/).to_h.transform_values { |v| JSON.parse(v) }
    next if values['source_labels'] && !Regexp.new("\\A(?:#{values.fetch('regex')})\\z").match?(labels.fetch(values['source_labels'].first))
    labels[values.fetch('target_label')] = values.fetch('replacement')
  end
  assert(labels['service'] == service && labels['component'] == 'caddy', "#{project} downstream labels must identify the service")
end
shared = YAML.load_file("#{root}/prometheus/rules/shared-infra.yml")['groups'][0]['rules']
assert(shared.any? { |r| r['alert'] == 'ContainerMetricsMissing' && r['expr'].include?('unless on() container_last_seen') }, 'cAdvisor missing container data')
core = shared.find { |r| r['alert'] == 'MonitoringTargetDown' }['expr']
assert(%w[alloy loki grafana].all? { |x| core.include?("absent(up{job=\"#{x}\"})") } && shared.any? { |r| r['alert'] == 'AlloyLogDeliveryDropped' }, 'monitoring availability')
a = YAML.load_file("#{root}/grafana/provisioning/alerting/reading-garden-alerts.yml")
rules = a.fetch('groups').flat_map { |g| g.fetch('rules') }
forward = rules.find { |r| r['uid'] == 'prometheus-alert-forwarder' }
assert(rules.size == 3 && forward['noDataState'] == 'OK' && forward['execErrState'] == 'Alerting' && forward['data'][0]['model']['expr'].include?('label_replace(ALERTS{alertstate="firing"}, "source_alert", "$1", "alertname"'), 'forwarder')
assert(%w[grafana-prod-local-caddy-health grafana-prod-public-external-health grafana-prod-app-metrics grafana-caddy-metrics grafana-host-disk-full].all? { |uid| a['deleteRules'].any? { |r| r['uid'] == uid } }, 'obsolete rules')
assert(rules.select { |r| r['uid'].include?('app-error-logs') }.map { |r| r['labels']['service'] }.sort == %w[pawtogether reading-garden-kotlin], 'separate log alerts')
policy = YAML.load_file("#{root}/grafana/provisioning/alerting/notification-policies.yml")['policies'][0]
assert(policy['receiver'] == 'nooook-discord' && policy['routes'].size == 1 && policy['routes'][0]['receiver'] == 'reading-garden-discord-prod' && policy['routes'][0]['object_matchers'].include?(['service', '=', 'reading-garden-kotlin']) && policy['routes'][0]['object_matchers'].include?(['env', '=', 'prod']) && policy['group_by'].include?('source_alert'), 'routing')
assert(File.read("#{root}/grafana/provisioning/alerting/notification-templates.yml").scan('source_alert').size >= 2, 'notification source name')
assert(File.read("#{root}/grafana/dashboards/reading-garden-postgres-overview.json").include?('pawtogether_prod'), 'database dashboard')
puts 'Monitoring coverage configuration checks passed'
RUBY

TEST_DIR="$(mktemp -d)"
trap 'rm -r "$TEST_DIR"' EXIT
cat > "$TEST_DIR/rules-test.yml" <<'YAML'
rule_files:
  - /rules/reading-garden-prod.yml
  - /rules/pawtogether-prod.yml
  - /rules/shared-infra.yml
evaluation_interval: 15s
tests:
  - interval: 15s
    input_series:
      - series: 'up{job="reading-garden-prod-app",instance="blue"}'
        values: '1x8'
      - series: 'up{job="reading-garden-prod-app",instance="green"}'
        values: '0x8'
      - series: 'up{job="pawtogether-prod-app",instance="blue"}'
        values: '1x8'
      - series: 'up{job="pawtogether-prod-app",instance="green"}'
        values: '0x8'
    alert_rule_test:
      - eval_time: 2m
        alertname: ProdAppMetricsDown
        exp_alerts: []
  - interval: 15s
    input_series:
      - series: 'up{job="reading-garden-prod-app",instance="blue"}'
        values: '1x8'
      - series: 'up{job="pawtogether-prod-app",instance="blue"}'
        values: '0x8'
      - series: 'up{job="pawtogether-prod-app",instance="green"}'
        values: '0x8'
    alert_rule_test:
      - eval_time: 2m
        alertname: ProdAppMetricsDown
        exp_alerts:
          - exp_labels:
              severity: critical
              env: prod
              service: pawtogether
              component: app
            exp_annotations:
              summary: PawTogether prod actuator metrics target is down
  - interval: 15s
    alert_rule_test:
      - eval_time: 2m
        alertname: ProdAppMetricsDown
        exp_alerts:
          - exp_labels:
              severity: critical
              env: prod
              service: pawtogether
              component: app
            exp_annotations:
              summary: PawTogether prod actuator metrics target is down
          - exp_labels:
              severity: critical
              env: prod
              service: reading-garden-kotlin
              component: app
            exp_annotations:
              summary: ReadingGarden prod actuator metrics target is down
  - interval: 15s
    input_series:
      - series: 'up{job="cadvisor",instance="localhost:18082"}'
        values: '1x12'
      - series: 'container_last_seen{job="cadvisor",name="pawtogether-prod-blue"}'
        values: '1x12'
    alert_rule_test:
      - eval_time: 3m
        alertname: ContainerMetricsMissing
        exp_alerts: []
  - interval: 15s
    input_series:
      - series: 'up{job="cadvisor",instance="localhost:18082"}'
        values: '1x12'
    alert_rule_test:
      - eval_time: 3m
        alertname: ContainerMetricsMissing
        exp_alerts:
          - exp_labels:
              instance: localhost:18082
              job: cadvisor
              severity: warning
              env: infra
              service: docker
              component: container
            exp_annotations:
              summary: cAdvisor is up but named container metrics are missing
  - interval: 15s
    input_series:
      - series: 'up{job="cadvisor",instance="localhost:18082"}'
        values: '0x12'
    alert_rule_test:
      - eval_time: 3m
        alertname: ContainerMetricsMissing
        exp_alerts: []

YAML

ruby - "$TEST_DIR/rules-test.yml" <<'RUBY'
require 'yaml'
path = ARGV.fetch(0)
suite = YAML.load_file(path)
projects = {'reading-garden' => ['reading-garden-kotlin', 'ReadingGarden'], 'pawtogether' => ['pawtogether', 'PawTogether']}
metrics = %w[container_cpu_usage_seconds_total container_memory_working_set_bytes]
# The other project stays fully present, so it cannot mask missing CPU or memory.
cases = [[nil, [], 1], [nil, [], 0], [nil, [], nil]]
projects.each_key do |project|
  cases.concat([[project, [metrics[0]], 1], [project, [metrics[1]], 1], [project, metrics, 1], [project, metrics, 0], [project, metrics, nil]])
end
cases.each do |missing_project, missing_metrics, exporter_up|
  input = []
  input << {'series' => 'up{job="cadvisor",instance="localhost:18082"}', 'values' => "#{exporter_up}x12"} unless exporter_up.nil?
  projects.each_key do |project|
    metrics.each do |metric|
      next if project == missing_project && missing_metrics.include?(metric)
      # Zero CPU/memory is present data, not absence.
      input << {'series' => "#{metric}{job=\"cadvisor\",name=\"#{project}-prod-blue\"}", 'values' => '0x12'}
    end
  end
  expected = []
  if missing_project && exporter_up == 1
    service, title = projects.fetch(missing_project)
    expected << {
      'exp_labels' => {'instance' => 'localhost:18082', 'job' => 'cadvisor', 'severity' => 'warning', 'env' => 'prod', 'service' => service, 'component' => 'container'},
      'exp_annotations' => {'summary' => "#{title} container CPU or memory metrics are missing while cAdvisor is up"}
    }
  end
  suite.fetch('tests') << {
    'name' => "#{missing_project || 'healthy'} missing #{missing_metrics.join(',')} exporter=#{exporter_up.inspect}",
    'interval' => '15s', 'input_series' => input,
    'alert_rule_test' => [{'eval_time' => '3m', 'alertname' => 'ProdContainerMetricsMissing', 'exp_alerts' => expected}]
  }
end
File.write(path, YAML.dump(suite))
RUBY

docker run --rm --network none -v "$ROOT_DIR/deploy/monitoring/prometheus/rules:/rules:ro" -v "$TEST_DIR:/tests:ro" --entrypoint promtool prom/prometheus:v3.4.0 test rules /tests/rules-test.yml
