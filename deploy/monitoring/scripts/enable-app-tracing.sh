#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -ne 2 ]; then
  echo "Usage: $0 APP_DIR SERVICE_NAME" >&2
  exit 1
fi
app_dir=$1
service_name=$2
case "$service_name" in
  reading-garden-kotlin|pawtogether) ;;
  *) echo "Unsupported service name" >&2; exit 1 ;;
esac
endpoint=${TRACING_OTLP_ENDPOINT:-http://172.24.0.1:4318}
if [[ ! "$endpoint" =~ ^https?://[a-zA-Z0-9._:/-]+$ ]]; then
  echo "Invalid tracing endpoint" >&2
  exit 1
fi
for file in "$app_dir/.env" "$app_dir/.runtime.env"; do
  if [ ! -f "$file" ] || [ ! -r "$file" ]; then
    echo "Required environment file missing or unreadable: $file" >&2
    exit 1
  fi
  if grep -Eq '^[[:space:]]*(export[[:space:]]+)?(JAVA_TOOL_OPTIONS|LOGGING_PATTERN_LEVEL)([[:space:]]*=|[[:space:]]*$)' "$file"; then
    echo "Tracing conflicts with existing settings in $file" >&2
    exit 1
  fi
done

umask 077
tmp_dir=$(mktemp -d "${app_dir}/.tracing-install.XXXXXXXX")
agent_tmp=''
trap 'rm -rf "$tmp_dir"; if [ -n "$agent_tmp" ]; then rm -f "$agent_tmp"; fi' EXIT
cat > "$tmp_dir/tracing.env" <<ENV
# Managed by enable-app-tracing.sh
JAVA_TOOL_OPTIONS=-javaagent:/opt/observability/opentelemetry-javaagent-2.33.1.jar
OTEL_SERVICE_NAME=${service_name}
OTEL_RESOURCE_ATTRIBUTES=deployment.environment.name=prod
OTEL_EXPORTER_OTLP_ENDPOINT=${endpoint}
OTEL_EXPORTER_OTLP_PROTOCOL=http/protobuf
OTEL_TRACES_EXPORTER=otlp
OTEL_METRICS_EXPORTER=none
OTEL_LOGS_EXPORTER=none
OTEL_TRACES_SAMPLER=parentbased_traceidratio
OTEL_TRACES_SAMPLER_ARG=1.0
LOGGING_PATTERN_LEVEL='%5p [trace_id=%X{trace_id:-} span_id=%X{span_id:-}]'
ENV
if [ -e "$app_dir/.tracing.env" ] || [ -L "$app_dir/.tracing.env" ]; then
  if [ ! -f "$app_dir/.tracing.env" ] || [ -L "$app_dir/.tracing.env" ] || ! cmp -s "$tmp_dir/tracing.env" "$app_dir/.tracing.env"; then
    echo "Existing .tracing.env is not the requested managed configuration; preserve it and resolve manually" >&2
    exit 1
  fi
fi

curl -fLsS --retry 3 -o "$tmp_dir/agent.jar" \
  https://github.com/open-telemetry/opentelemetry-java-instrumentation/releases/download/v2.33.1/opentelemetry-javaagent.jar
printf '%s  %s\n' 'e43a270df53c6f423e0ab157be9c27ccc01d5dc3232e162fe54777573db2f149' "$tmp_dir/agent.jar" | sha256sum -c - >/dev/null || {
  echo "Java agent checksum mismatch" >&2
  exit 1
}
mkdir -p "$app_dir/observability"
chmod 755 "$app_dir/observability"
agent_tmp=$(mktemp "$app_dir/observability/.agent.XXXXXXXX")
cp "$tmp_dir/agent.jar" "$agent_tmp"
chmod 644 "$agent_tmp"
chmod 600 "$tmp_dir/tracing.env"
mv -f "$agent_tmp" "$app_dir/observability/opentelemetry-javaagent-2.33.1.jar"
agent_tmp=''
mv -f "$tmp_dir/tracing.env" "$app_dir/.tracing.env"
echo "Tracing configured for $service_name; recreate the app containers to apply it."
