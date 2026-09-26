#!/usr/bin/env bash
# Sickler's Warriors — PostgreSQL RETIRED/LEGACY dev cluster management (port 5433).
# App sasa inatumia system PostgreSQL port 5432 (DB: sickle_cell) — see
# scripts/setup_system_pg.sh. Hii script ina-manage tu cluster ya zamani ya
# infrastructure/postgres/data (sw_db*) iliyohifadhiwa. Bado ina bug: DATA_DIR
# hapo chini inaelekeza scripts/data badala ya infrastructure/postgres/data.
#
# Unaweza ku-run hii bila sudo (user-owned instance).
#
# Usage:
#   ./postgres.sh start
#   ./postgres.sh stop
#   ./postgres.sh status
#   ./postgres.sh psql

set -euo pipefail

PG_BIN="/usr/lib/postgresql/18/bin"
DATA_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/data"
LOG_FILE="$(dirname "$DATA_DIR")/postgres.log"

# PORT ya dev ni 5433 ili kutogusana na default postgres (5432).
PORT="5433"

case "${1:-start}" in
  start)
    if ! "$PG_BIN/pg_isready" -p "$PORT" -h /tmp >/dev/null 2>&1; then
      mkdir -p "$DATA_DIR"
      "$PG_BIN/pg_ctl" -D "$DATA_DIR" -l "$LOG_FILE" -o "-p $PORT -k /tmp" start
    else
      echo "PostgreSQL tayari inafanya kazi kwenye port $PORT."
    fi
    ;;
  stop)
    "$PG_BIN/pg_ctl" -D "$DATA_DIR" -o "-p $PORT -k /tmp" stop 2>/dev/null || echo "Hakuna server ya ku-stop."
    ;;
  status)
    if "$PG_BIN/pg_isready" -p "$PORT" -h /tmp >/dev/null 2>&1; then
      echo "status: running (port $PORT)"
    else
      echo "status: stopped"
    fi
    ;;
  psql)
    /usr/bin/psql -h /tmp -p "$PORT" -U sw_db_user -d sw_db "${@:2}"
    ;;
  *)
    echo "Usage: $0 {start|stop|status|psql}"
    exit 1
    ;;
esac