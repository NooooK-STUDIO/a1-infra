#!/usr/bin/env bash
set -euo pipefail

psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" <<SQL
CREATE ROLE reading_garden_prod_app LOGIN PASSWORD '${READING_GARDEN_PROD_APP_PASSWORD}';
CREATE ROLE reading_garden_prod_migrator LOGIN PASSWORD '${READING_GARDEN_PROD_MIGRATOR_PASSWORD}';
CREATE ROLE reading_garden_dev_app LOGIN PASSWORD '${READING_GARDEN_DEV_APP_PASSWORD}';
CREATE ROLE reading_garden_dev_migrator LOGIN PASSWORD '${READING_GARDEN_DEV_MIGRATOR_PASSWORD}';

CREATE DATABASE reading_garden_prod OWNER reading_garden_prod_migrator;
CREATE DATABASE reading_garden_dev OWNER reading_garden_dev_migrator;
SQL

psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname reading_garden_prod <<SQL
REVOKE CREATE ON SCHEMA public FROM PUBLIC;
GRANT USAGE ON SCHEMA public TO reading_garden_prod_app;
ALTER DEFAULT PRIVILEGES FOR ROLE reading_garden_prod_migrator IN SCHEMA public
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO reading_garden_prod_app;
ALTER DEFAULT PRIVILEGES FOR ROLE reading_garden_prod_migrator IN SCHEMA public
GRANT USAGE, SELECT ON SEQUENCES TO reading_garden_prod_app;
SQL

psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname reading_garden_dev <<SQL
REVOKE CREATE ON SCHEMA public FROM PUBLIC;
GRANT USAGE ON SCHEMA public TO reading_garden_dev_app;
ALTER DEFAULT PRIVILEGES FOR ROLE reading_garden_dev_migrator IN SCHEMA public
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO reading_garden_dev_app;
ALTER DEFAULT PRIVILEGES FOR ROLE reading_garden_dev_migrator IN SCHEMA public
GRANT USAGE, SELECT ON SEQUENCES TO reading_garden_dev_app;
SQL
