#!/usr/bin/env bash
set -euo pipefail
repo_dir=$(cd "$(dirname "$0")/../.." && pwd)
script="$repo_dir/deploy/monitoring/scripts/configure-tracing-firewall.sh"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
mkdir "$tmp/bin"
cat > "$tmp/bin/id" <<'MOCK'
#!/usr/bin/env bash
[ "$1" = -u ] && printf '%s\n' "${TEST_UID:-0}"
MOCK
cat > "$tmp/bin/docker" <<'MOCK'
#!/usr/bin/env bash
[ "$1" = network ] && [ "$2" = inspect ] && [ "$3" = "${SHARED_BACKEND_NETWORK_NAME:-reading-garden-shared-backend}" ]
options=${TEST_OPTIONS:-'{}'}
printf '[{"Id":"abcdef1234567890","Options":%s,"IPAM":{"Config":[{"Subnet":"%s","Gateway":"%s"}]}}]\n' "$options" "${TEST_SUBNET:-172.24.0.0/16}" "${TEST_GATEWAY:-172.24.0.1}"
MOCK
cat > "$tmp/bin/ip" <<'MOCK'
#!/usr/bin/env bash
[ "$1 $2 $3 $4" = '-d -o link show' ] && [ "$5" = dev ]
printf '3: %s: <BROADCAST> mtu 1500 bridge forward_delay 1500\n' "$6"
MOCK
cat > "$tmp/bin/iptables" <<'MOCK'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$TEST_LOG"
case "$1" in
  -C) [ -e "$TEST_LIVE" ] ;;
  -I) [ "$2 $3" = 'INPUT 1' ] && [ "${TEST_INSERT_FAIL:-0}" != 1 ] && touch "$TEST_LIVE" ;;
  *) exit 1 ;;
esac
MOCK
cat > "$tmp/bin/iptables-restore" <<'MOCK'
#!/usr/bin/env bash
[ "$1" = --test ]
cat > "$TEST_CANDIDATE"
[ "${TEST_RESTORE_FAIL:-0}" != 1 ]
MOCK
chmod +x "$tmp/bin/"*
export PATH="$tmp/bin:$PATH" IPTABLES_RULES_FILE="$tmp/rules.v4" TEST_LOG="$tmp/log" TEST_LIVE="$tmp/live" TEST_CANDIDATE="$tmp/candidate"
cat > "$IPTABLES_RULES_FILE" <<'RULES'
# preserve header
*filter
:INPUT DROP [12:345]
:FORWARD DROP [0:0]
:OUTPUT ACCEPT [0:0]
-A INPUT -s 10.1.0.0/16 -j ACCEPT
-A INPUT -j REJECT --reject-with icmp-host-prohibited
-A FORWARD -j DROP
COMMIT
*nat
:PREROUTING ACCEPT [0:0]
COMMIT
RULES
chmod 640 "$IPTABLES_RULES_FILE"
cp "$IPTABLES_RULES_FILE" "$tmp/original"
"$script"
python3 - "$tmp/original" "$IPTABLES_RULES_FILE" <<'PY'
import sys
original, actual = (open(p, 'rb').read() for p in sys.argv[1:])
rule = b'-A INPUT -i br-abcdef123456 -s 172.24.0.0/16 -d 172.24.0.1/32 -p tcp --dport 4318 -j ACCEPT\n'
assert actual == original.replace(b'-A INPUT ', rule + b'-A INPUT ', 1)
PY
[ "$(stat -c %a "$IPTABLES_RULES_FILE" 2>/dev/null || stat -f %Lp "$IPTABLES_RULES_FILE")" = 640 ]
grep -Fx -- '-I INPUT 1 -i br-abcdef123456 -s 172.24.0.0/16 -d 172.24.0.1/32 -p tcp --dport 4318 -j ACCEPT' "$TEST_LOG" >/dev/null
cp "$IPTABLES_RULES_FILE" "$tmp/expected"
"$script"
cmp "$tmp/expected" "$IPTABLES_RULES_FILE"
[ "$(grep -c '^-I ' "$TEST_LOG")" = 1 ]
for scenario in public bad_gateway restore nonroot malformed missing; do
  cp "$tmp/original" "$IPTABLES_RULES_FILE"
  case "$scenario" in
    public) export TEST_SUBNET=8.8.8.0/24 TEST_GATEWAY=8.8.8.1 ;;
    bad_gateway) export TEST_GATEWAY=172.25.0.1 ;;
    restore) export TEST_RESTORE_FAIL=1 ;;
    nonroot) export TEST_UID=1000 ;;
    malformed) printf '*filter\n:OUTPUT ACCEPT [0:0]\nCOMMIT\n' > "$IPTABLES_RULES_FILE" ;;
    missing) rm "$IPTABLES_RULES_FILE" ;;
  esac
  if [ -e "$IPTABLES_RULES_FILE" ]; then cp "$IPTABLES_RULES_FILE" "$tmp/before"; fi
  cp "$TEST_LOG" "$tmp/log-before"
  if "$script" > "$tmp/output" 2>&1; then echo "Unexpected success: $scenario" >&2; exit 1; fi
  if [ "$scenario" = missing ]; then [ ! -e "$IPTABLES_RULES_FILE" ]; else cmp "$tmp/before" "$IPTABLES_RULES_FILE"; fi
  cmp "$tmp/log-before" "$TEST_LOG"
  unset TEST_SUBNET TEST_GATEWAY TEST_RESTORE_FAIL TEST_UID
done
# Insertion failure must leave the persisted file unchanged.
cp "$tmp/original" "$IPTABLES_RULES_FILE"
rm "$TEST_LIVE"
if TEST_INSERT_FAIL=1 "$script" > "$tmp/output" 2>&1; then echo 'Insertion failure accepted' >&2; exit 1; fi
cmp "$tmp/original" "$IPTABLES_RULES_FILE"
# Docker's explicit bridge option takes precedence over the derived bridge name.
TEST_OPTIONS='{"com.docker.network.bridge.name":"shared-br"}' "$script"
grep -Fx -- '-A INPUT -i shared-br -s 172.24.0.0/16 -d 172.24.0.1/32 -p tcp --dport 4318 -j ACCEPT' "$IPTABLES_RULES_FILE" >/dev/null
# A valid file with no INPUT rules gets the rule immediately after the chain declaration.
printf '*filter\n:INPUT DROP [0:0]\n:OUTPUT ACCEPT [0:0]\nCOMMIT\n' > "$IPTABLES_RULES_FILE"
"$script"
[ "$(sed -n '3p' "$IPTABLES_RULES_FILE")" = '-A INPUT -i br-abcdef123456 -s 172.24.0.0/16 -d 172.24.0.1/32 -p tcp --dport 4318 -j ACCEPT' ]
echo PASS
