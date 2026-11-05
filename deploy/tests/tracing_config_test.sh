#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."
ruby <<'RUBY'
require 'yaml'
require 'json'
require 'uri'
tempo = YAML.load_file('deploy/monitoring/tempo/tempo.yml')
abort 'Tempo must stay private' unless tempo['server']['http_listen_address'] == '127.0.0.1' && tempo['server']['grpc_listen_address'] == '127.0.0.1' && tempo.dig('distributor', 'receivers', 'otlp', 'protocols', 'grpc', 'endpoint') == '127.0.0.1:14317'
abort 'Retention missing' unless tempo.dig('backend_scheduler', 'provider', 'compaction', 'compaction', 'block_retention') == '72h'
sources = YAML.load_file('deploy/monitoring/grafana/provisioning/datasources/datasources.yml')['datasources'].to_h { |s| [s['uid'], s] }
field = sources['loki']['jsonData']['derivedFields'].first
abort 'Log trace link missing' unless field['datasourceUid'] == 'tempo' && field['url'] == '$${__value.raw}'
sample_id = 'a' * 32
abort 'Trace ID extraction broken' unless Regexp.new(field['matcherRegex']).match("INFO [trace_id=#{sample_id} span_id=bbbbbbbbbbbbbbbb]")[1] == sample_id
abort 'Trace log mapping broken' unless sources.dig('tempo', 'jsonData', 'tracesToLogsV2', 'tags') == [{'key' => 'service.name', 'value' => 'service'}]
{'reading-garden' => 'reading-garden-kotlin', 'pawtogether' => 'pawtogether'}.each do |project, service|
  %W[#{project}-prod-overview #{project}-logs].each do |dashboard|
    data = JSON.parse(File.read("deploy/monitoring/grafana/dashboards/#{project}/#{dashboard}.json"))
    url = data['links'].find { |l| l['title'] == 'Traces' }.fetch('url')
    panes = JSON.parse(URI.decode_www_form(url.split('?', 2).last).to_h.fetch('panes'))
    abort 'Dashboard time range must be passed into Explore' unless panes.values.first['range'] == {'from' => '${__from}', 'to' => '${__to}'} && url.include?('${__from}') && url.include?('${__to}')
    query = panes.values.first.fetch('queries').first
    abort 'Trace link crosses services' unless query['query'] == "{ resource.service.name = \"#{service}\" }" && query['datasource']['uid'] == 'tempo'
  end
end
puts 'PASS: trace retention, private listeners, log correlation and service-scoped navigation'
RUBY
