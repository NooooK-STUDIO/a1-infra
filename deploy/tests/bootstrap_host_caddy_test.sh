#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT_PATH="${ROOT_DIR}/deploy/bootstrap-host-caddy.sh"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

mkdir -p \
    "${TMP_DIR}/stage/common" \
    "${TMP_DIR}/stage/sites" \
    "${TMP_DIR}/stage/systemd/caddy.service.d" \
    "${TMP_DIR}/bin" \
    "${TMP_DIR}/config" \
    "${TMP_DIR}/state-data" \
    "${TMP_DIR}/state-config" \
    "${TMP_DIR}/docker-data" \
    "${TMP_DIR}/docker-config"

cat > "${TMP_DIR}/stage/Caddyfile" <<'EOF'
{
    admin unix//var/lib/caddy/caddy-admin.sock
}

import /etc/caddy/common/*.caddy
import /etc/caddy/sites/*.caddy
EOF
printf 'handle {\n}\n' > "${TMP_DIR}/stage/common/proxy_common.caddy"
printf 'example.com {\n}\n' > "${TMP_DIR}/stage/sites/example.caddy"
cat > "${TMP_DIR}/stage/systemd/caddy.service.d/override.conf" <<'EOF'
[Service]
ExecReload=
ExecReload=/usr/bin/caddy reload --address unix//var/lib/caddy/caddy-admin.sock --config /etc/caddy/Caddyfile --adapter caddyfile --force
EOF
printf 'certdata\n' > "${TMP_DIR}/docker-data/test.txt"
printf 'configdata\n' > "${TMP_DIR}/docker-config/test.txt"

cat > "${TMP_DIR}/bin/caddy" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
cat > "${TMP_DIR}/bin/systemctl" <<'EOF'
#!/usr/bin/env bash
if [[ "${1:-}" == "daemon-reload" ]]; then
    exit 0
fi
echo "unexpected systemctl invocation: $*" >&2
exit 1
EOF
chmod +x "${TMP_DIR}/bin/caddy" "${TMP_DIR}/bin/systemctl"

PATH="${TMP_DIR}/bin:$PATH" \
HOST_CADDY_REQUIRE_ROOT=false \
HOST_CADDY_STAGE_DIR="${TMP_DIR}/stage" \
HOST_CADDY_CONFIG_DIR="${TMP_DIR}/config" \
HOST_CADDY_SYSTEMD_OVERRIDE_DIR="${TMP_DIR}/systemd/caddy.service.d" \
HOST_CADDY_IMPORT_DOCKER_STATE=true \
HOST_CADDY_STATE_OWNER="" \
HOST_CADDY_DOCKER_DATA_DIR="${TMP_DIR}/docker-data" \
HOST_CADDY_DOCKER_CONFIG_DIR="${TMP_DIR}/docker-config" \
HOST_CADDY_STATE_DATA_DIR="${TMP_DIR}/state-data" \
HOST_CADDY_STATE_CONFIG_DIR="${TMP_DIR}/state-config" \
"${SCRIPT_PATH}"

grep -Fq 'admin unix//var/lib/caddy/caddy-admin.sock' "${TMP_DIR}/config/Caddyfile"
test -f "${TMP_DIR}/config/common/proxy_common.caddy"
test -f "${TMP_DIR}/config/sites/example.caddy"
test -f "${TMP_DIR}/systemd/caddy.service.d/override.conf"
grep -Fq 'certdata' "${TMP_DIR}/state-data/test.txt"
grep -Fq 'configdata' "${TMP_DIR}/state-config/test.txt"

echo "PASS"
