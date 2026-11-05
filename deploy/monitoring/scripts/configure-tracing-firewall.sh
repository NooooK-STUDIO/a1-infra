#!/usr/bin/env bash
set -euo pipefail

if [ "$(id -u)" != 0 ]; then
  echo 'Run this script as root' >&2
  exit 1
fi
network=${SHARED_BACKEND_NETWORK_NAME:-reading-garden-shared-backend}
rules_file=${IPTABLES_RULES_FILE:-/etc/iptables/rules.v4}
if [ ! -f "$rules_file" ] || [ -L "$rules_file" ]; then
  echo 'Existing regular iptables rules file required' >&2
  exit 1
fi

network_info=$(docker network inspect "$network" | python3 -c '
import ipaddress, json, re, sys
try:
    data = json.load(sys.stdin)
    if len(data) != 1:
        raise ValueError("expected one network")
    net = data[0]
    network_id = net["Id"]
    if not re.fullmatch(r"[0-9a-f]{12,64}", network_id):
        raise ValueError("invalid network ID")
    bridge = (net.get("Options") or {}).get("com.docker.network.bridge.name") or "br-" + network_id[:12]
    if not re.fullmatch(r"[a-zA-Z0-9_.-]{1,15}", bridge) or bridge in (".", ".."):
        raise ValueError("invalid bridge name")
    configs = [c for c in net["IPAM"]["Config"] if ":" not in c.get("Subnet", "")]
    if len(configs) != 1:
        raise ValueError("expected exactly one IPv4 subnet")
    subnet = ipaddress.IPv4Network(configs[0]["Subnet"], strict=True)
    gateway = ipaddress.IPv4Address(configs[0]["Gateway"])
    private = [ipaddress.IPv4Network(cidr) for cidr in ("10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16")]
    if not any(subnet.subnet_of(p) for p in private) or gateway not in subnet or gateway in (subnet.network_address, subnet.broadcast_address):
        raise ValueError("subnet or gateway is not a usable private IPv4 address")
    print(bridge, subnet, gateway)
except (KeyError, TypeError, ValueError, json.JSONDecodeError) as exc:
    sys.exit("Invalid Docker network: " + str(exc))
')
read -r bridge subnet gateway <<< "$network_info"
if ! ip -d -o link show dev "$bridge" | grep -Eq "(^|[[:space:]])bridge([[:space:]]|$)"; then
  echo "Docker network interface is not a bridge" >&2
  exit 1
fi

candidate=$(mktemp "${rules_file}.tracing.XXXXXXXX")
trap 'rm -f "$candidate"' EXIT
python3 - "$rules_file" "$candidate" "$bridge" "$subnet" "$gateway" <<'PY'
import os, stat, sys

source, candidate, bridge, subnet, gateway = sys.argv[1:]
with open(source, 'rb') as f:
    info = os.fstat(f.fileno())
    data = f.read()
lines = data.splitlines(keepends=True)
filters = [i for i, line in enumerate(lines) if line.rstrip(b'\r\n') == b'*filter']
if len(filters) != 1:
    sys.exit('Rules must contain exactly one filter table')
start = filters[0]
commits = [i for i in range(start + 1, len(lines)) if lines[i].rstrip(b'\r\n') == b'COMMIT']
if not commits:
    sys.exit('Filter table has no COMMIT')
end = commits[0]
if any(line.startswith(b'*') for line in lines[start + 1:end]):
    sys.exit('Malformed filter table')
chains = [i for i in range(start + 1, end) if lines[i].startswith(b':INPUT ')]
if len(chains) != 1:
    sys.exit('Filter table must declare one INPUT chain')
chain = chains[0]
input_rules = [i for i in range(start + 1, end) if lines[i].startswith(b'-A INPUT ')]
if any(i < chain for i in input_rules):
    sys.exit('INPUT rules precede INPUT chain')
rule = f'-A INPUT -i {bridge} -s {subnet} -d {gateway}/32 -p tcp --dport 4318 -j ACCEPT'.encode()
# Move only this exact rule if already present, so it always precedes INPUT rejects.
lines = [line for i, line in enumerate(lines) if not (start < i < end and line.rstrip(b'\r\n') == rule)]
end = next(i for i in range(start + 1, len(lines)) if lines[i].rstrip(b'\r\n') == b'COMMIT')
chain = next(i for i in range(start + 1, end) if lines[i].startswith(b':INPUT '))
input_rules = [i for i in range(chain + 1, end) if lines[i].startswith(b'-A INPUT ')]
pos = input_rules[0] if input_rules else chain + 1
if pos > 0 and not lines[pos - 1].endswith(b'\n'):
    sys.exit('Cannot insert into malformed rules file')
newline = b'\r\n' if lines[chain].endswith(b'\r\n') else b'\n'
lines.insert(pos, rule + newline)
with open(candidate, 'wb') as f:
    f.write(b''.join(lines))
os.chown(candidate, info.st_uid, info.st_gid)
os.chmod(candidate, stat.S_IMODE(info.st_mode))
PY
iptables-restore --test < "$candidate"
args=(-i "$bridge" -s "$subnet" -d "$gateway/32" -p tcp --dport 4318 -j ACCEPT)
positions=$(iptables -S INPUT | python3 -c '
import shlex, sys
expected = sys.argv[1:]
def options(tokens):
    pairs = []
    while tokens:
        if len(tokens) < 2:
            return None
        key, value, *tokens = tokens
        if (key, value) != ("-m", "tcp"):
            pairs.append((key, value))
    return sorted(pairs)
wanted = options(expected)
position = 0
for line in sys.stdin:
    tokens = shlex.split(line)
    if tokens[:2] == ["-A", "INPUT"]:
        position += 1
        if options(tokens[2:]) == wanted:
            print(position)
' "${args[@]}")
if [ "${positions%%$'\n'*}" != 1 ]; then
  # Keep older copies: deleting by a saved index could remove an unrelated rule after a concurrent insert.
  iptables -I INPUT 1 "${args[@]}"
fi
if ! cmp -s "$rules_file" "$candidate"; then
  mv -f "$candidate" "$rules_file"
fi
