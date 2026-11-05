#!/usr/bin/env bash
set -euo pipefail

MONITORING_DIR="${MONITORING_DIR:-/opt/infra/monitoring}"
COMPOSE_FILE="${MONITORING_DIR}/docker-compose.yml"
ENV_FILE="${MONITORING_DIR}/.env"

cd "$MONITORING_DIR"

test -f "$COMPOSE_FILE"
test -f "$ENV_FILE"

required_keys=(
  GRAFANA_ADMIN_PASSWORD
  NOOOOK_DISCORD_WEBHOOK_URL
  GRAFANA_DISCORD_PROD_WEBHOOK_URL
  GRAFANA_DISCORD_PAW_WEBHOOK_URL
  POSTGRES_EXPORTER_PASSWORD
)

for key in "${required_keys[@]}"; do
  if ! grep -Eq "^${key}=.+" "$ENV_FILE"; then
    echo "Missing required key in ${ENV_FILE}: ${key}" >&2
    exit 1
  fi
done

docker compose -f "$COMPOSE_FILE" --env-file "$ENV_FILE" config >/dev/null
docker compose -f "$COMPOSE_FILE" --env-file "$ENV_FILE" pull --policy missing
# Older deployments wrote positions into the container layer. Move them into
# the existing volume before replacing the collector, preserving read offsets.
if docker inspect a1-monitoring-alloy >/dev/null 2>&1 &&
  ! docker inspect a1-monitoring-alloy --format '{{json .Config.Cmd}}' | grep -q -- '--storage.path'; then
  migration_dir="$(mktemp -d)"
  was_running="$(docker inspect a1-monitoring-alloy --format '{{.State.Running}}')"
  migration_complete=false
  cleanup_migration() {
    status=$?
    if [ "$status" -ne 0 ] && [ "$was_running" = true ]; then
      echo "Monitoring apply failed; restoring the Alloy collector" >&2
      if ! docker start a1-monitoring-alloy >/dev/null; then
        if [ "$migration_complete" = true ] &&
          docker compose -f "$COMPOSE_FILE" --env-file "$ENV_FILE" up -d --no-deps alloy; then
          echo "Alloy recreated using the preserved positions volume" >&2
        else
          echo "Alloy recovery failed. Retry: docker compose -f '$COMPOSE_FILE' --env-file '$ENV_FILE' up -d --no-deps alloy" >&2
        fi
      fi
    fi
    rm -rf "$migration_dir"
    exit "$status"
  }
  trap cleanup_migration EXIT
  docker stop a1-monitoring-alloy >/dev/null
  docker cp a1-monitoring-alloy:/data-alloy/. "$migration_dir/"
  alloy_image="$(docker inspect a1-monitoring-alloy --format '{{.Config.Image}}')"
  docker run --rm --user 0:0 --entrypoint sh \
    --volumes-from a1-monitoring-alloy \
    -v "$migration_dir:/migration:ro" "$alloy_image" \
    -c 'mkdir -p /var/lib/alloy/data; cp -a /migration/. /var/lib/alloy/data/'
  migration_complete=true
fi
docker compose -f "$COMPOSE_FILE" --env-file "$ENV_FILE" up -d --force-recreate
docker compose -f "$COMPOSE_FILE" --env-file "$ENV_FILE" ps
