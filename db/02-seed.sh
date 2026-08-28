#!/bin/sh
# Loads the demo dataset. Runs once, on an empty data directory, after 01-schema.sql.
#
# OFF by default. Every seeded account shares one password published in this
# repository (see seed.sql), so loading this anywhere reachable hands out a
# hospital-admin session to anyone who reads the file. Opt in with
# SEED_DEMO_DATA=true for a local demo; a real deployment provisions its first
# administrator from ADMIN_EMAIL / ADMIN_PASSWORD instead.
#
# No `exit` and no `set -e` here: postgres' entrypoint *sources* a non-executable
# .sh, so either would tear down the whole init run.

if [ "${SEED_DEMO_DATA:-false}" = "true" ]; then
  psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" -f /seed/seed.sql
else
  echo "SEED_DEMO_DATA=${SEED_DEMO_DATA} - skipping demo data (no hospitals, no accounts)"
fi
