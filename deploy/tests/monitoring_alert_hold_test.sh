#!/usr/bin/env bash
set -euo pipefail
repo_dir=$(cd "$(dirname "$0")/../.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
chmod 755 "$tmp"

ruby - "$repo_dir" "$tmp" <<'RUBY'
require 'yaml'
require 'json'
root, output = ARGV
files = Dir["#{root}/deploy/monitoring/prometheus/rules/*.yml"]
rules = files.flat_map { |path| YAML.load_file(path).fetch('groups').flat_map { |g| g.fetch('rules') } }
abort('Every forwarded alert must survive the 60s poll and 30s notification wait') unless
  rules.all? { |r| r['keep_firing_for'] == '2m' }

cases = [
  ['ProdAppMetricsDown', 'reading-garden-kotlin', 'reading-garden-prod-app'],
  ['ProdAppMetricsDown', 'pawtogether', 'pawtogether-prod-app'],
  ['CaddyMetricsDown', 'caddy', 'caddy'],
]
tests = cases.map do |name, service, job|
  rule = rules.find { |r| r['alert'] == name && r['labels']['service'] == service }
  labels = rule.fetch('labels').merge('__name__' => 'ALERTS', 'alertname' => name, 'alertstate' => 'firing')
  labels['job'] = job if name == 'CaddyMetricsDown'
  # The outage fires at 60s and recovers at 105s, between Grafana polls at 50s/110s.
  checks = {'50s' => false, '75s' => true, '110s' => true, '210s' => true, '225s' => false}
  {
    'interval' => '15s',
    'input_series' => [{'series' => "up{job=\"#{job}\"}", 'values' => '0 0 0 0 0 0 0 1+0x12'}],
    'promql_expr_test' => checks.map do |time, firing|
      {
        'expr' => "ALERTS{alertname=\"#{name}\",service=\"#{service}\",alertstate=\"firing\"}",
        'eval_time' => time,
        'exp_samples' => firing ? [{'labels' => '{' + labels.map { |k,v| "#{k}=#{v.to_json}" }.join(',') + '}', 'value' => 1}] : [],
      }
    end,
  }
end
File.write("#{output}/test.yml", {
  'rule_files' => files.map { |p| "/rules/#{File.basename(p)}" },
  'evaluation_interval' => '15s',
  'tests' => tests,
}.to_yaml)
RUBY

docker run --rm --network none --entrypoint promtool \
  -v "$repo_dir/deploy/monitoring/prometheus/rules:/rules:ro" \
  -v "$tmp:/tests:ro" prom/prometheus:v3.4.0 test rules /tests/test.yml
echo 'PASS: brief application and infrastructure alerts remain visible until notification'
