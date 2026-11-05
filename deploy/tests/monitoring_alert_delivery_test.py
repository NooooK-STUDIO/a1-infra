#!/usr/bin/env python3
"""Opt-in Docker integration test: python3 deploy/tests/monitoring_alert_delivery_test.py"""
import base64
import json
import os
from pathlib import Path
import subprocess
import tempfile
import threading
import time
import urllib.error
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

ROOT = Path(__file__).resolve().parents[1] / 'monitoring/grafana/provisioning'
PREFIX = 'alert-delivery-' + os.urandom(5).hex()
messages = []
active = {'ReadingGardenProbe', 'PawProbe', 'InfraProbe', 'ReadingGardenSecond'}

class Handler(BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass

    def do_GET(self):
        lines = ['# TYPE test_alert gauge']
        for name in sorted(active):
            lines.append('test_alert{name="%s"} 1' % name)
        body = ('\n'.join(lines) + '\n').encode()
        self.send_response(200)
        self.send_header('Content-Type', 'text/plain; version=0.0.4')
        self.end_headers()
        self.wfile.write(body)

    def do_POST(self):
        data = json.loads(self.rfile.read(int(self.headers['Content-Length'])))
        messages.append((self.path.split('?')[0], data))
        print('RECEIVED:', self.path, json.dumps(data), flush=True)
        self.send_response(204)
        self.end_headers()


def docker(*args, check=True):
    return subprocess.run(['docker', *args], check=check, text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE).stdout.strip()


def wait_for(label, predicate, seconds=120):
    deadline = time.monotonic() + seconds
    while time.monotonic() < deadline:
        if predicate():
            print('PASS:', label, flush=True)
            return
        time.sleep(2)
    raise AssertionError('%s timed out; received messages: %s' % (label, json.dumps(messages, ensure_ascii=False)))


def request(url):
    req = urllib.request.Request(url, headers={'Authorization': 'Basic ' + base64.b64encode(b'admin:integration-test').decode()})
    try:
        with urllib.request.urlopen(req, timeout=3) as response:
            return json.load(response)
    except (OSError, ValueError, urllib.error.HTTPError):
        return {}


def text_of(payload):
    return json.dumps(payload, ensure_ascii=False)


def delivered(path, status, name):
    return any(p == path and any(status.upper() in embed.get('title', '') and name in embed.get('title', '') and ('infra' if name == 'InfraProbe' else 'prod') in embed.get('title', '') for embed in body.get('embeds', [])) for p, body in messages)


def main():
    server = ThreadingHTTPServer(('0.0.0.0', 0), Handler)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    port = server.server_address[1]
    with tempfile.TemporaryDirectory(prefix=PREFIX) as tmp:
        tmp = Path(tmp)
        alert_dir = tmp / 'alerting'
        data_dir = tmp / 'datasources'
        alert_dir.mkdir(mode=0o755)
        data_dir.mkdir(mode=0o755)
        os.chmod(tmp, 0o755)
        # Keep the forwarder verbatim, excluding unrelated Loki rules.
        rules = (ROOT / 'alerting/monitoring-alerts.yml').read_text()
        header, groups = rules.split('groups:\n', 1)
        rules = (header + 'groups:\n' + groups.split('\n- orgId:', 1)[0]).replace('interval: 60s', 'interval: 10s')
        (alert_dir / 'rules.yml').write_text(rules)
        for file in ('notification-policies.yml', 'notification-templates.yml', 'contact-points.yml'):
            content = (ROOT / 'alerting' / file).read_text()
            if file == 'notification-policies.yml':
                content = content.replace('group_wait: 30s', 'group_wait: 1s').replace('group_interval: 5m', 'group_interval: 10s')
            (alert_dir / file).write_text(content)
        (data_dir / 'datasources.yml').write_text('''apiVersion: 1
datasources:
  - name: Prometheus
    uid: prometheus
    type: prometheus
    access: proxy
    url: http://prometheus:9090
    jsonData:
      httpMethod: POST
      timeInterval: 2s
''')
        (tmp / 'prometheus.yml').write_text('''global:
  scrape_interval: 2s
  evaluation_interval: 2s
rule_files:
  - /etc/prometheus/rules.yml
scrape_configs:
  - job_name: synthetic
    static_configs:
      - targets: ["host.docker.internal:%d"]
''' % port)
        alerts = [('ReadingGardenProbe', 'reading-garden-kotlin', 'prod'), ('ReadingGardenSecond', 'reading-garden-kotlin', 'prod'), ('PawProbe', 'pawtogether', 'prod'), ('InfraProbe', 'monitoring', 'infra')]
        content = 'groups:\n- name: synthetic\n  interval: 2s\n  rules:\n'
        for name, service, env in alerts:
            content += '  - alert: %s\n    expr: test_alert{name="%s"} == 1\n    labels:\n      service: %s\n      env: %s\n      severity: warning\n' % (name, name, service, env)
        (tmp / 'prom-rules.yml').write_text(content)
        try:
            docker('network', 'create', PREFIX)
            docker('run', '-d', '--name', PREFIX + '-prom', '--network', PREFIX, '--network-alias', 'prometheus', '--add-host', 'host.docker.internal:host-gateway', '-v', str(tmp / 'prometheus.yml') + ':/etc/prometheus/prometheus.yml:ro', '-v', str(tmp / 'prom-rules.yml') + ':/etc/prometheus/rules.yml:ro', 'prom/prometheus:v3.4.0')
            docker('run', '-d', '--name', PREFIX + '-grafana', '--network', PREFIX, '--add-host', 'host.docker.internal:host-gateway', '-p', '127.0.0.1::3000', '-e', 'GF_SECURITY_ADMIN_PASSWORD=integration-test', '-e', 'GF_PLUGINS_PREINSTALL_DISABLED=true', '-e', 'GF_ANALYTICS_CHECK_FOR_UPDATES=false', '-e', 'GF_UNIFIED_ALERTING_MIN_INTERVAL=10s', '-e', 'NOOOOK_DISCORD_WEBHOOK_URL=http://host.docker.internal:%d/shared' % port, '-e', 'GRAFANA_DISCORD_PROD_WEBHOOK_URL=http://host.docker.internal:%d/reading' % port, '-v', str(alert_dir) + ':/etc/grafana/provisioning/alerting:ro', '-v', str(data_dir) + ':/etc/grafana/provisioning/datasources:ro', 'grafana/grafana:12.4.14')
            grafana_port = docker('port', PREFIX + '-grafana', '3000/tcp').rsplit(':', 1)[1]
            api = 'http://127.0.0.1:' + grafana_port
            wait_for('Grafana ready', lambda: request(api + '/api/health').get('database') == 'ok', 60)
            wait_for('all firing notifications routed with source alert names', lambda: all(delivered('/reading' if service == 'reading-garden-kotlin' else '/shared', 'firing', name) for name, service, _ in alerts), 150)
            assert not any(delivered('/shared', 'firing', name) for name in ('ReadingGardenProbe', 'ReadingGardenSecond'))
            assert not any(delivered('/reading', 'firing', name) for name in ('PawProbe', 'InfraProbe'))
            # Inspect Grafana's alert instances: Discord's template intentionally omits service.
            def labels_preserved():
                data = request(api + '/api/prometheus/grafana/api/v1/alerts')
                instances = data.get('data', {}).get('alerts', [])
                return all(any(a.get('labels', {}).get('source_alert') == name and a['labels'].get('service') == service and a['labels'].get('env') == env and a.get('state', '').lower() in ('firing', 'alerting') for a in instances) for name, service, env in alerts)
            wait_for('source_alert, service and env preserved', labels_preserved, 30)
            active.remove('ReadingGardenProbe')
            wait_for('one resolved while second remains firing', lambda: delivered('/reading', 'resolved', 'ReadingGardenProbe') and labels_preserved_except_one(api), 150)
            active.clear()
            wait_for('remaining alerts resolved on their receivers', lambda: all(delivered('/reading' if service == 'reading-garden-kotlin' else '/shared', 'resolved', name) for name, service, _ in alerts), 150)
            print('PASS: real Grafana to local Discord-compatible receiver; %d notifications' % len(messages))
        except Exception:
            print('Grafana logs:\n' + docker('logs', '--tail', '100', PREFIX + '-grafana', check=False), flush=True)
            raise
        finally:
            docker('rm', '-f', PREFIX + '-grafana', PREFIX + '-prom', check=False)
            docker('network', 'rm', PREFIX, check=False)
            server.shutdown()
            server.server_close()


def labels_preserved_except_one(api):
    data = request(api + '/api/prometheus/grafana/api/v1/alerts')
    alerts = data.get('data', {}).get('alerts', [])
    return any(a.get('labels', {}).get('source_alert') == 'ReadingGardenSecond' and a.get('state', '').lower() in ('firing', 'alerting') for a in alerts)


if __name__ == '__main__':
    main()
