#!/usr/bin/env bash
# Sickler's Warriors — create the app database on the SYSTEM PostgreSQL (port 5432)
# System PG ina-own 5432; hii script inahitaji sudo (inageuka kuwa postgres superuser).
#
# Usage (run by project owner in a terminal):
#   sudo bash scripts/setup_system_pg.sh

set -euo pipefail

# Run a SQL statement as the postgres superuser (peer auth, local socket).
pg_as_super() {
  sudo -u postgres /usr/bin/psql -p 5432 -tAc "$1"
}

echo "==> Creating role sw_db_user (if missing) on system PG (5432)"
if [ "$(pg_as_super "SELECT 1 FROM pg_roles WHERE rolname='sw_db_user'")" = "1" ]; then
  echo "    role sw_db_user tayari ipo."
else
  pg_as_super "CREATE ROLE sw_db_user WITH LOGIN PASSWORD 'sw_db_dev_password';"
  echo "    role sw_db_user imeundwa."
fi

echo "==> Creating database sickle_cell (owned by sw_db_user) on system PG (5432)"
if [ "$(pg_as_super "SELECT 1 FROM pg_database WHERE datname='sickle_cell'")" = "1" ]; then
  echo "    database sickle_cell tayari ipo."
else
  sudo -u postgres /usr/bin/createdb -p 5432 -O sw_db_user sickle_cell
  echo "    database sickle_cell imeundwa."
fi

# Verify connect as the app role (scram password auth, host 127.0.0.1)
echo "==> Verifying app connection"
if PGPASSWORD='sw_db_dev_password' /usr/bin/psql -h 127.0.0.1 -p 5432 -U sw_db_user -d sickle_cell -tAc "SELECT 'connected OK';" | grep -q "connected OK"; then
  echo "    Connection OK: 127.0.0.1:5432/sickle_cell (user sw_db_user)."
else
  echo "    FAILED ku-connect. Angalia pg_hba.conf ya system PG."
  exit 1
fi