#!/usr/bin/env bash
set -euo pipefail

python3 <<'PY'
import json
import pathlib
import subprocess

script = pathlib.Path('deploy/monitoring/scripts/verify-monitoring.sh').read_text()
start = script.index('response_has_expected_alert_rules() {')
end = script.index('\nwait_for_prometheus_rules()', start)
function = script[start:end]

def verify(rules):
    response = json.dumps({'status': 'success', 'data': {'groups': [{'rules': rules}]}})
    command = 'EXPECTED_ALERT_RULES=("AppDown|reading-garden-kotlin|prod" "AppDown|pawtogether|prod" "DatabaseDown|postgres|infra")\n' + function
    command += '\nresponse_has_expected_alert_rules "$(cat)"'
    return subprocess.run(['bash', '-c', command], input=response, text=True).returncode

healthy = [{'name': name, 'health': 'ok', 'labels': {'service': service, 'env': env}} for name, service, env in [('AppDown', 'reading-garden-kotlin', 'prod'), ('AppDown', 'pawtogether', 'prod'), ('DatabaseDown', 'postgres', 'infra')]]
assert verify(healthy) == 0
broken = [dict(r) for r in healthy]
broken[0]['health'] = 'err'
assert verify(broken) != 0, 'One unhealthy rule must fail even if the same name has another healthy rule'
assert verify([healthy[0], healthy[0], healthy[2]]) != 0, 'A duplicate ReadingGarden rule must not conceal a missing PawTogether rule'
assert verify(healthy[1:]) != 0, 'Both service-specific rules must be loaded'
assert verify(healthy + [{'name': 'Unexpected', 'health': 'err'}]) != 0
print('PASS: verifier rejects unhealthy and missing rules, including duplicate names')
PY

python3 <<'PY'
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

script = Path('deploy/monitoring/scripts/verify-monitoring.sh').read_text()
credentials = script[script.index('read_grafana_setting() {'):script.index('\ndocker compose -f "$COMPOSE_FILE" --env-file "$ENV_FILE" ps')]
compose = Path('deploy/monitoring/docker-compose.monitoring.yml')

with tempfile.TemporaryDirectory() as directory:
    root = Path(directory)
    shutil.copyfile(compose, root / 'docker-compose.yml')
    base_env = {key: value for key, value in os.environ.items() if key not in {
        'GRAFANA_ADMIN_USER', 'GRAFANA_ADMIN_PASSWORD', 'NOOOOK_DISCORD_WEBHOOK_URL',
        'GRAFANA_DISCORD_PROD_WEBHOOK_URL', 'GRAFANA_DISCORD_PAW_WEBHOOK_URL',
        'POSTGRES_EXPORTER_PASSWORD', 'CREDENTIAL_PART',
    }}
    base_env.update(COMPOSE_FILE=str(root / 'docker-compose.yml'), ENV_FILE=str(root / '.env'))
    extras = '\nNOOOOK_DISCORD_WEBHOOK_URL=other-secret\nGRAFANA_DISCORD_PROD_WEBHOOK_URL=fixture\nGRAFANA_DISCORD_PAW_WEBHOOK_URL=fixture\nPOSTGRES_EXPORTER_PASSWORD=fixture\n'
    shell = 'set -euo pipefail\n' + credentials + '''
[[ "$GRAFANA_ADMIN_USER" == "$EXPECTED_USER" && "$GRAFANA_ADMIN_PASSWORD" == "$EXPECTED_PASSWORD" ]]
'''

    def verify(contents, user, password, overrides=None, success=True):
        (root / '.env').write_text(contents + extras)
        env = {**base_env, 'EXPECTED_USER': user, 'EXPECTED_PASSWORD': password, **(overrides or {})}
        result = subprocess.run(['bash', '-c', shell], env=env, capture_output=True, text=True)
        assert (result.returncode == 0) == success, 'credential verification returned unexpected status'
        for secret in (user, password, 'other-secret'):
            assert not secret or secret not in result.stdout + result.stderr, 'credential or unrelated secret leaked'

    verify('GRAFANA_ADMIN_USER=plain-user\nGRAFANA_ADMIN_PASSWORD=plain-password', 'plain-user', 'plain-password')
    verify('CREDENTIAL_PART=expanded\nGRAFANA_ADMIN_PASSWORD=unquoted-${CREDENTIAL_PART}', 'admin', 'unquoted-expanded')
    verify("GRAFANA_ADMIN_USER='single user'\nGRAFANA_ADMIN_PASSWORD='single $CREDENTIAL_PART secret'", 'single user', 'single $CREDENTIAL_PART secret')
    verify("GRAFANA_ADMIN_PASSWORD='literal $$ token'", 'admin', 'literal $$ token')
    verify("GRAFANA_ADMIN_PASSWORD='trailing\n\n'", 'admin', 'trailing\n\n')
    verify('CREDENTIAL_PART=expanded\nGRAFANA_ADMIN_USER="double user"\nGRAFANA_ADMIN_PASSWORD="double ${CREDENTIAL_PART} secret"', 'double user', 'double expanded secret')
    verify('GRAFANA_ADMIN_USER=file-user\nGRAFANA_ADMIN_PASSWORD=file-password', 'override user', 'override password', {'GRAFANA_ADMIN_USER': 'override user', 'GRAFANA_ADMIN_PASSWORD': 'override password'})
    verify('GRAFANA_ADMIN_USER=file-user\nGRAFANA_ADMIN_PASSWORD="file secret"', 'override user', 'file secret', {'GRAFANA_ADMIN_USER': 'override user'})
    verify('GRAFANA_ADMIN_USER="file user"\nGRAFANA_ADMIN_PASSWORD=file-password', 'file user', 'override $$ password', {'GRAFANA_ADMIN_PASSWORD': 'override $$ password'})
    verify('GRAFANA_ADMIN_USER=file-user\nGRAFANA_ADMIN_PASSWORD="unterminated secret', 'file-user', 'unterminated secret', success=False)

print('PASS: real Compose credential parsing, overrides, and secret-free output')
PY

python3 <<'PY'
import os
from pathlib import Path
import subprocess

script = Path('deploy/monitoring/scripts/verify-monitoring.sh').read_text()
function = script[script.index('assert_prometheus_query_has_result() {'):script.index('\nassert_loki_query_has_result()', script.index('assert_prometheus_query_has_result() {'))]
checks = [line for line in script.splitlines() if line.startswith('assert_prometheus_query_has_result ') and 'http_server_requests_seconds_bucket' in line]
assert len(checks) == 2
for job in ('reading-garden-prod-app', 'pawtogether-prod-app'):
    assert any(f'count(http_server_requests_seconds_bucket{{job="{job}"}}) > 0' in check for check in checks)

for missing in ('', 'reading-garden-prod-app', 'pawtogether-prod-app'):
    shell = '''set -euo pipefail
PROMETHEUS_URL=http://prometheus
VERIFY_TIMEOUT_SECONDS=0
curl() {
  if [[ -n "$MISSING_JOB" && "$*" == *"$MISSING_JOB"* ]]; then
    printf '%s' '{"result":[]}'
  else
    printf '%s' '{"result":[{}]}'
  fi
}
''' + function + '\n' + '\n'.join(checks)
    result = subprocess.run(['bash', '-c', shell], env={'PATH': os.environ['PATH'], 'MISSING_JOB': missing}, capture_output=True, text=True)
    assert (result.returncode == 0) == (not missing), f'histogram verification failed for {missing or "healthy metrics"}'
print('PASS: histogram verification requires buckets for both applications')
PY
