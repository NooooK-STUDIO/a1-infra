#!/usr/bin/env bash
set -euo pipefail

repo_dir=$(cd "$(dirname "$0")/../.." && pwd)
installer="$repo_dir/deploy/monitoring/scripts/enable-app-tracing.sh"
tmp_dir=$(mktemp -d)
trap 'rm -rf "$tmp_dir"' EXIT
app="$tmp_dir/app"
mkdir -p "$app" "$tmp_dir/bin"
touch "$app/.env" "$app/.runtime.env"
cat > "$tmp_dir/bin/curl" <<'MOCK'
#!/usr/bin/env bash
while [ "$#" -gt 0 ]; do
  if [ "$1" = -o ]; then shift; output=$1; fi
  shift
done
printf 'local test payload\n' > "$output"
MOCK
cat > "$tmp_dir/bin/sha256sum" <<'MOCK'
#!/usr/bin/env bash
read -r expected file
[ "$expected" = e43a270df53c6f423e0ab157be9c27ccc01d5dc3232e162fe54777573db2f149 ]
[ -f "$file" ]
[ "${TEST_CHECKSUM_FAIL:-0}" != 1 ]
MOCK
chmod +x "$tmp_dir/bin/curl" "$tmp_dir/bin/sha256sum"
export PATH="$tmp_dir/bin:$PATH"

compose_config() {
  IMAGE_REF=example:test APP_HOST_DIR="$app" APP_CONTAINER_PREFIX=test \
  APP_BLUE_HOST_PORT=18080 APP_GREEN_HOST_PORT=18081 \
  APP_BLUE_MANAGEMENT_HOST_PORT=19080 APP_GREEN_MANAGEMENT_HOST_PORT=19081 \
  docker compose --profile green -f "$repo_dir/deploy/docker-compose.oci.yml" config --format json
}
compose_config > "$tmp_dir/without.json"
"$installer" "$app" pawtogether
cp "$app/.tracing.env" "$tmp_dir/expected.env"
cp "$app/observability/opentelemetry-javaagent-2.33.1.jar" "$tmp_dir/expected.jar"
"$installer" "$app" pawtogether
cmp "$app/.tracing.env" "$tmp_dir/expected.env"
cmp "$app/observability/opentelemetry-javaagent-2.33.1.jar" "$tmp_dir/expected.jar"
[ "$(stat -c %a "$app/.tracing.env" 2>/dev/null || stat -f %Lp "$app/.tracing.env")" = 600 ]
[ "$(stat -c %a "$app/observability/opentelemetry-javaagent-2.33.1.jar" 2>/dev/null || stat -f %Lp "$app/observability/opentelemetry-javaagent-2.33.1.jar")" = 644 ]
[ "$(stat -c %a "$app/observability" 2>/dev/null || stat -f %Lp "$app/observability")" = 755 ]
if TEST_CHECKSUM_FAIL=1 "$installer" "$app" pawtogether; then
  echo 'Checksum failure accepted' >&2; exit 1
fi
cmp "$app/.tracing.env" "$tmp_dir/expected.env"
cmp "$app/observability/opentelemetry-javaagent-2.33.1.jar" "$tmp_dir/expected.jar"
for file in .env .runtime.env; do
  for key in JAVA_TOOL_OPTIONS LOGGING_PATTERN_LEVEL; do
    printf 'export %s=private-value\n' "$key" > "$app/$file"
    if "$installer" "$app" pawtogether > "$tmp_dir/error" 2>&1; then
      echo "Conflict accepted: $file $key" >&2; exit 1
    fi
    if grep -q private-value "$tmp_dir/error"; then echo 'Conflict value leaked' >&2; exit 1; fi
    : > "$app/$file"
  done
done
printf 'USER_SETTING=keep\n' > "$app/.tracing.env"
if "$installer" "$app" pawtogether; then echo 'User env overwritten' >&2; exit 1; fi
grep -qx 'USER_SETTING=keep' "$app/.tracing.env"
cp "$tmp_dir/expected.env" "$app/.tracing.env"
printf 'OTEL_SERVICE_NAME=base\n' > "$app/.env"
printf 'OTEL_SERVICE_NAME=runtime\n' > "$app/.runtime.env"
compose_config > "$tmp_dir/with.json"
python3 - "$tmp_dir/without.json" "$tmp_dir/with.json" "$app" <<'PY'
import json, sys
without, with_tracing = (json.load(open(path)) for path in sys.argv[1:3])
for service in ('app-blue', 'app-green'):
    assert 'OTEL_SERVICE_NAME' not in without['services'][service].get('environment', {})
    config = with_tracing['services'][service]
    env = config['environment']
    assert env['OTEL_SERVICE_NAME'] == 'pawtogether'
    assert env['LOGGING_PATTERN_LEVEL'] == '%5p [trace_id=%X{trace_id:-} span_id=%X{span_id:-}]'
    assert env['JAVA_TOOL_OPTIONS'] == '-javaagent:/opt/observability/opentelemetry-javaagent-2.33.1.jar'
    assert any(v['source'] == sys.argv[3] + '/observability' and v['target'] == '/opt/observability' and v['read_only'] for v in config['volumes'])
PY
[ -z "$(find "$app" -maxdepth 1 -name '.tracing-install.*' -print -quit)" ]
echo PASS
