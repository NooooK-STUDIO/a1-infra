#!/usr/bin/env bash
set -euo pipefail

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT
mkdir -p "$TMP_DIR/bin"
cat > "$TMP_DIR/bin/psql" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$TEST_LOG_FILE"
cat >> "$TEST_LOG_FILE"
STUB
chmod +x "$TMP_DIR/bin/psql"

TEST_LOG_FILE="$TMP_DIR/psql.log" \
PATH="$TMP_DIR/bin:$PATH" POSTGRES_USER=postgres \
READING_GARDEN_PROD_APP_PASSWORD=test READING_GARDEN_PROD_MIGRATOR_PASSWORD=test \
PAWTOGETHER_PROD_APP_PASSWORD=test PAWTOGETHER_PROD_MIGRATOR_PASSWORD=test \
PAWTOGETHER_DEV_APP_PASSWORD=test PAWTOGETHER_DEV_MIGRATOR_PASSWORD=test \
bash deploy/postgres/init/10-create-app-databases.sh

grep -Fq 'CREATE DATABASE reading_garden_prod ' "$TMP_DIR/psql.log"
grep -Fq 'CREATE DATABASE pawtogether_prod ' "$TMP_DIR/psql.log"
if grep -Fq 'pawtogether_dev' "$TMP_DIR/psql.log"; then
    echo 'retired PawTogether database or role was initialized' >&2
    exit 1
fi
echo PASS
