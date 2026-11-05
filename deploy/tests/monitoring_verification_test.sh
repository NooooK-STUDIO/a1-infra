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
