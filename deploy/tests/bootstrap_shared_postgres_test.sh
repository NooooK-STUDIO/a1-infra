#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT_PATH="${ROOT_DIR}/deploy/bootstrap-shared-postgres.sh"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

mkdir -p "${TMP_DIR}/stack" "${TMP_DIR}/bin"
printf 'services:\n  postgres:\n    image: postgres:17\n' > "${TMP_DIR}/stack/docker-compose.yml"
mkdir -p "${TMP_DIR}/stack/secrets"
printf 'superpass\n' > "${TMP_DIR}/stack/secrets/postgres_superuser.password"
printf 'prod-app-pass\n' > "${TMP_DIR}/stack/secrets/reading_garden_prod_app.password"
printf 'prod-migrator-pass\n' > "${TMP_DIR}/stack/secrets/reading_garden_prod_migrator.password"
printf 'dev-app-pass\n' > "${TMP_DIR}/stack/secrets/reading_garden_dev_app.password"
printf 'dev-migrator-pass\n' > "${TMP_DIR}/stack/secrets/reading_garden_dev_migrator.password"

cat > "${TMP_DIR}/bin/docker" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

LOG_FILE="${TEST_LOG_FILE:?TEST_LOG_FILE is required}"

printf '%s\n' "$*" >> "$LOG_FILE"

case "${1:-}" in
    network)
        if [[ "${2:-}" == "inspect" ]]; then
            exit 1
        fi
        if [[ "${2:-}" == "create" ]]; then
            exit 0
        fi
        ;;
    compose)
        if [[ "${4:-}" == "up" ]]; then
            exit 0
        fi
        if [[ "${4:-}" == "logs" ]]; then
            exit 0
        fi
        ;;
    inspect)
        printf 'healthy\n'
        exit 0
        ;;
esac

echo "unexpected docker invocation: $*" >&2
exit 1
EOF
chmod +x "${TMP_DIR}/bin/docker"

TEST_LOG_FILE="${TMP_DIR}/docker.log" \
PATH="${TMP_DIR}/bin:$PATH" \
POSTGRES_STACK_DIR="${TMP_DIR}/stack" \
POSTGRES_BOOTSTRAP_TIMEOUT_SECONDS=5 \
"${SCRIPT_PATH}"

grep -Fq 'network inspect reading-garden-shared-backend' "${TMP_DIR}/docker.log"
grep -Fq 'network create reading-garden-shared-backend' "${TMP_DIR}/docker.log"
grep -Fq "compose -f ${TMP_DIR}/stack/docker-compose.yml up -d" "${TMP_DIR}/docker.log"
grep -Fq 'inspect --format={{.State.Health.Status}} shared-postgres' "${TMP_DIR}/docker.log"

echo "PASS"
