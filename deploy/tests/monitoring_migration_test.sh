#!/usr/bin/env bash
set -euo pipefail

python3 <<'PY'
import os
import pathlib
import subprocess
import tempfile

source = pathlib.Path('deploy/monitoring/scripts/bootstrap-monitoring.sh').resolve()
with tempfile.TemporaryDirectory() as tmp:
    root = pathlib.Path(tmp)
    (root / 'docker-compose.yml').touch()
    (root / '.env').write_text('\n'.join(k + '=fixture' for k in [
        'GRAFANA_ADMIN_PASSWORD', 'NOOOOK_DISCORD_WEBHOOK_URL',
        'GRAFANA_DISCORD_PROD_WEBHOOK_URL', 'POSTGRES_EXPORTER_PASSWORD']))
    docker = root / 'docker'
    docker.write_text('''#!/usr/bin/env bash
set -eu
printf '%s\\n' "$*" >> "$CALLS"
case "$*" in
  *State.Running*) echo true ;;
  *Config.Cmd*) if [ "${MIGRATED:-0}" = 1 ]; then echo '["run","--storage.path=/var/lib/alloy/data"]'; else echo '["run"]'; fi ;;
  *Config.Image*) echo grafana/alloy:v1.9.1 ;;
  cp*) if [ "${FAIL_COPY:-0}" = 1 ]; then exit 2; fi ;;
  *up\ -d\ --force-recreate*) if [ "${FAIL_RECREATE:-0}" = 1 ]; then exit 3; fi ;;
  start*) if [ "${FAIL_RECREATE:-0}" = 1 ]; then exit 4; fi ;;
esac
''')
    docker.chmod(0o755)
    calls = root / 'calls'
    env = dict(os.environ, PATH=str(root) + ':' + os.environ['PATH'], MONITORING_DIR=tmp, CALLS=str(calls))
    for copied, fail, recreate in [(False, False, False), (True, False, False), (False, True, False), (False, False, True)]:
        calls.write_text('')
        result = subprocess.run(['bash', str(source)], env=dict(env, MIGRATED=str(int(copied)), FAIL_COPY=str(int(fail)), FAIL_RECREATE=str(int(recreate))), capture_output=True, text=True)
        log = calls.read_text()
        if recreate:
            assert result.returncode != 0 and 'up -d --no-deps alloy' in log
            assert 'Alloy recreated using the preserved positions volume' in result.stderr
        elif fail:
            assert result.returncode != 0 and 'start a1-monitoring-alloy' in log
            assert 'up -d' not in log, 'Do not destroy the old collector after a failed migration'
        elif copied:
            assert result.returncode == 0 and 'cp a1-monitoring-alloy:' not in log
        else:
            assert result.returncode == 0, result.stderr
            assert log.index('pull --policy missing') < log.index('stop a1-monitoring-alloy')
            assert log.index('stop a1-monitoring-alloy') < log.index('cp a1-monitoring-alloy:/data-alloy/.') < log.index('up -d')
            assert '--volumes-from a1-monitoring-alloy' in log and '/var/lib/alloy/data' in log
print('PASS: positions migrate before recreation, skip repeated migration, and preserve the old collector on failure')
PY
