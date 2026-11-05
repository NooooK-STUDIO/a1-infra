#!/usr/bin/env python3
"""Exercise the real Alloy -> Tempo pipeline with synthetic OTLP spans."""
import json
import pathlib
import secrets
import subprocess
import tempfile
import time
import urllib.error
import urllib.request

ROOT = pathlib.Path(__file__).resolve().parents[2]
PREFIX = "a1-tracing-test-" + secrets.token_hex(4)


def docker(*args):
    return subprocess.check_output(["docker", *args], text=True).strip()


def request(url, payload=None):
    req = urllib.request.Request(url, headers={"Accept": "application/json"})
    if payload is not None:
        req.data = json.dumps(payload).encode()
        req.add_header("Content-Type", "application/json")
    with urllib.request.urlopen(req, timeout=5) as response:
        return response.read()


def wait_for(check, label):
    deadline = time.monotonic() + 90
    while time.monotonic() < deadline:
        try:
            result = check()
            if result:
                return result
        except (urllib.error.URLError, TimeoutError, ConnectionError):
            pass
        time.sleep(1)
    raise AssertionError(label)


with tempfile.TemporaryDirectory(prefix=PREFIX) as directory:
    config = pathlib.Path(directory)
    # Only the isolated test containers expose these listeners to their network.
    tempo = (ROOT / "deploy/monitoring/tempo/tempo.yml").read_text()
    tempo = tempo.replace("http_listen_address: 127.0.0.1", "http_listen_address: 0.0.0.0")
    tempo = tempo.replace("endpoint: 127.0.0.1:14317", "endpoint: 0.0.0.0:14317")
    (config / "tempo.yml").write_text(tempo)
    alloy = (ROOT / "deploy/monitoring/alloy/config.alloy").read_text()
    alloy = alloy[alloy.index('otelcol.receiver.otlp "apps"'):]
    alloy = alloy.replace('"127.0.0.1:14317"', '"tempo:14317"')
    (config / "config.alloy").write_text(alloy)
    config.chmod(0o755)
    try:
        docker("network", "create", PREFIX)
        docker("run", "-d", "--name", PREFIX + "-tempo", "--network", PREFIX,
               "--network-alias", "tempo", "--tmpfs", "/var/tempo:uid=10001,gid=10001,mode=700",
               "-p", "127.0.0.1::3200", "-v", f"{config}:/etc/tracing:ro",
               "grafana/tempo:3.1.1", "-config.file=/etc/tracing/tempo.yml")
        docker("run", "-d", "--name", PREFIX + "-alloy", "--network", PREFIX,
               "-e", "OTLP_HTTP_LISTEN_ADDRESS=0.0.0.0:4318", "-p", "127.0.0.1::4318",
               "-v", f"{config}:/etc/tracing:ro", "grafana/alloy:v1.9.1",
               "run", "/etc/tracing/config.alloy")
        tempo_url = "http://" + docker("port", PREFIX + "-tempo", "3200/tcp")
        alloy_url = "http://" + docker("port", PREFIX + "-alloy", "4318/tcp")
        wait_for(lambda: request(tempo_url + "/ready"), "Tempo failed to become ready")
        trace_id = secrets.token_hex(16)
        timestamp = time.time_ns()
        sensitive = ["url.query", "url.full", "http.url", "http.target", "db.statement", "db.query.text"]
        attributes = [{"key": key, "value": {"stringValue": "PRIVATE_TEST_VALUE"}} for key in sensitive]
        attributes += [{"key": "http.route", "value": {"stringValue": "/tracing-smoke"}}]
        payload = {"resourceSpans": [{
            "resource": {"attributes": [{"key": "service.name", "value": {"stringValue": "tracing-smoke"}}]},
            "scopeSpans": [{"spans": [{
                "traceId": trace_id, "spanId": secrets.token_hex(8), "name": "GET /tracing-smoke",
                "kind": 2, "startTimeUnixNano": str(timestamp), "endTimeUnixNano": str(timestamp + 1000000),
                "attributes": attributes,
            }]}],
        }]}
        wait_for(lambda: request(alloy_url + "/v1/traces", payload), "Alloy rejected OTLP")
        def read_trace():
            trace = request(tempo_url + "/api/v2/traces/" + trace_id)
            # Tempo 3 can return HTTP 200 with an empty trace while ingestion catches up.
            return trace if "GET /tracing-smoke" in trace.decode() else None

        trace = wait_for(read_trace, "Trace was not delivered")
        assert "PRIVATE_TEST_VALUE" not in trace.decode(), "Sensitive attributes reached storage"
        assert "http.route" in trace.decode() and "/tracing-smoke" in trace.decode(), "Route was lost"
        assert "tracing-smoke" in trace.decode(), "Service identity was lost"
        print("PASS: real Alloy -> Tempo delivery, readable trace, sensitive attributes removed")
    except Exception:
        for name in (PREFIX + "-tempo", PREFIX + "-alloy"):
            subprocess.run(["docker", "logs", "--tail", "30", name], check=False)
        raise
    finally:
        for name in (PREFIX + "-alloy", PREFIX + "-tempo"):
            subprocess.run(["docker", "rm", "-f", name], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        subprocess.run(["docker", "network", "rm", PREFIX], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
