#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
BOOTSTRAP_SCRIPT="${ROOT_DIR}/deploy/bootstrap-instance.sh"
TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT

TARGET_DIR="${TMP_ROOT}/target"

mkdir -p "${TMP_ROOT}/missing" "${TARGET_DIR}"

if REMOTE_APP_DIR="${TARGET_DIR}" "${BOOTSTRAP_SCRIPT}" 2>/dev/null; then
    echo "bootstrap should fail when target env files are absent" >&2
    exit 1
fi

mkdir -p "${TARGET_DIR}/secrets"
printf 'DB_NAME=reading_garden_prod\n' > "${TARGET_DIR}/.env"
printf '{}\n' > "${TARGET_DIR}/secrets/firebase-service-account.json"

REMOTE_APP_DIR="${TARGET_DIR}" "${BOOTSTRAP_SCRIPT}"

grep -Fq 'DB_HOST=shared-postgres' "${TARGET_DIR}/.runtime.env"
grep -Fq 'DB_PORT=5432' "${TARGET_DIR}/.runtime.env"
grep -Fq 'SPRING_DATASOURCE_URL=jdbc:postgresql://shared-postgres:5432/reading_garden_prod' "${TARGET_DIR}/.runtime.env"
grep -Fq 'SPRING_FLYWAY_URL=jdbc:postgresql://shared-postgres:5432/reading_garden_prod' "${TARGET_DIR}/.runtime.env"

echo "PASS"
