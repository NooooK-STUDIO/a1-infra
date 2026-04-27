#!/usr/bin/env bash
set -euo pipefail

GRAFANA_CONTAINER="${GRAFANA_CONTAINER:-a1-monitoring-grafana}"
BACKUP_DIR="${BACKUP_DIR:-/opt/infra/monitoring/backups}"
GRAFANA_IMAGE="${GRAFANA_IMAGE:-grafana/grafana:12.0.0}"

timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
backup_file="grafana-data-${timestamp}.tar.gz"

if ! docker inspect "$GRAFANA_CONTAINER" >/dev/null 2>&1; then
  echo "Grafana container not found: ${GRAFANA_CONTAINER}" >&2
  exit 1
fi

mkdir -p "$BACKUP_DIR"
chmod 700 "$BACKUP_DIR"

docker run --rm \
  --user 0:0 \
  --volumes-from "${GRAFANA_CONTAINER}:ro" \
  -v "${BACKUP_DIR}:/backup" \
  "$GRAFANA_IMAGE" \
  sh -c "tar -czf '/backup/${backup_file}' -C /var/lib/grafana . && chmod 600 '/backup/${backup_file}'"

echo "${BACKUP_DIR}/${backup_file}"
