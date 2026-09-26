# Sickler's Warriors — PostgreSQL

Mfumo huu unatumia **PostgreSQL 18**.

## Application database (in-use) — System PostgreSQL, port 5432

App (Django) inaunganisha na **`sickle_cell`** kwenye system PostgreSQL ya
`127.0.0.1:5432`. Kuunda role/database inahitaji sudo (una-run mwenyewe):

```bash
sudo bash scripts/setup_system_pg.sh   # idempotent: role + database
```

Credential (dev): user `sw_db_user` / password kwenye `backend/.env`.

## Retained dev cluster (legacy) — port 5433

Cluster ya zamani iko kwenye `infrastructure/postgres/data`, ina-run kwenye
**port 5433** na `scripts/postgres.sh` — hakuna sudo required. Database zake
(`sw_db`, `sw_db_test`, `sw_db_staging`) **zimehifadhiwa** (owner decision
"usiitoe") lakini **hazitumiwi** na app, ambayo sasa iko kwenye `sickle_cell`@5432.

```bash
./scripts/postgres.sh start|stop|status   # legacy cluster (5433)
```

Kumbuka: `scripts/postgres.sh` bado ina bug ya `DATA_DIR` (`scripts/data` badala ya
`infrastructure/postgres/data`) — cluster ya 5433 haiwezi kuanzishwa nayo mpaka
iborekebishwe (C4 kwenye `database-design-review.md`).

## Databases

| Database | Server | Matumizi |
|---|---|---|
| `sickle_cell` | System PG 5432 | Application (development) — inayotumika |
| `test_sickle_cell` | same as dev | Django test database (prefix `test_`) |
| `sw_db` | legacy 5433 | Retained (not used by app) |
| `sw_db_test` / `sw_db_staging` | legacy 5433 | Retained (not used by app) |

## Django integration

`backend/config/settings.py` inasoma environment (defaults inaonyesha `sickle_cell` @ 5432):

```
DB_NAME      (default sickle_cell)
DB_USER      (default sw_db_user)
DB_PASSWORD  (default sw_db_dev_password)
DB_HOST      (default 127.0.0.1)
DB_PORT      (default 5432)
```

Inacharge pia via `backend/.env` isiyo-commit.

## Data / files

- Legacy cluster data directory: `infrastructure/postgres/data/`
- Legacy log: `infrastructure/postgres/postgres.log`
- System cluster data: `/var/lib/postgresql/18/main` (admin-managed)

## Kumbuka

- App DB `sickle_cell` iko kwenye port 5432 (system PG). Uundaji wa DB/role
  unahitaji sudo — angalia C5 `database-design-review.md`.
- SQL migration hutumiwa kwa Django (`manage.py migrate`) — sio raw SQL kwa dev.