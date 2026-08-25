#!/bin/sh
# Loads the demo dataset. Runs once, on an empty data directory, after 01-schema.sql.
#
# On by default so `docker compose up` gives a working demo out of the box. Set
# SEED_DEMO_DATA=false for any instance that will hold real patients: the seeded
# staff accounts share one well-known password (see seed.sql), so leaving them in
# place on a reachable host hands out a hospital-admin session to anyone who guesses it.
#
# No `exit` and no `set -e` here: postgres' entrypoint *sources* a non-executable
# .sh, so either would tear down the whole init run.

if [ "${SEED_DEMO_DATA:-true}" = "true" ]; then
  psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" -f /seed/seed.sql
else
  echo "SEED_DEMO_DATA=${SEED_DEMO_DATA} - skipping demo data (no hospitals, no accounts)"
fi
