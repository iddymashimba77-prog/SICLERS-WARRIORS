# 3.9 Stage — Deployment Docker Architecture

> Part of Stage 3.9 Deployment Design (§23). This document describes the
> **conceptual container plan** for servers, workers and supporting services.
>
> **This is a DESIGN document only.** No Dockerfiles, no `docker compose`,
> no production containers are created now. Implementation happens in
> Stage 4, literally from these definitions.
>
> PostgreSQL is **NOT containerized** — Phase 1 runs PostgreSQL on the same
> host (system package / dedicated service) or moves to managed PostgreSQL
> (Phase 4). See `deployment-design.md` §12/§14/§23.

---

## 1. Container Strategy Decision

| Aspect | Decision | Rationale |
|---|---|---|
| Containerize PostgreSQL? | **No** | 3.8 + managed-PG option: data residency, patch control, easier backup/PITR; a managed or system PG is more appropriate than a container for a single-node start |
| Containerize the app? | **Yes** (backend, worker, admin build, optional proxy) | Reproducible builds, identical dev→test→staging→prod, fast rollback by image tag |
| Orchestration (Kubernetes) | **No** (Phase 1) | Over-engineered for initial scale (3.9 §40). Single-host Docker + systemd/compose is enough |
| Image registry | Yes (private) | Immutable tags = audit + rollback |

## 2. Container Inventory

| Container | Base image | Runs on | Purpose |
|---|---|---|---|
| `backend` | `python:3.12-slim` (pinned) | App host | Django service (Gunicorn/Uvicorn workers) |
| `worker` | same `backend` image + cmd | App host | Celery consumers + scheduler overlay |
| `admin-web` | build stage `node:20-alpine` → static artifact | Build-time only | Builds React/Vite admin; output to static dir/CDN |
| `nginx` | `nginx:1.27-alpine` (pinned) | App host | Reverse proxy, TLS, static, gzip (optional container; system nginx equivalent) |
| `redis` | `redis:7-alpine` (pinned) | App host | Queue broker + cache **only when approved** (§1 of `deployment-design.md` §13/§21) |

**Not containerized:** PostgreSQL (system/managed), backup scripts (host cron +
systemd timers), monitoring agents (host-level) — kept outside container runtime
for operational stability.

## 3. Image Build Design

```
Dockerfile (multi-stage, backend)
  stage base:
    python:3.12-slim
    install build deps only
    pip install --require-hashes -r requirements/prod.txt   (pinned + hashes)
  stage runtime:
    nonroot user (id 10001), no shell, no build tools
    copy venv + app code
    copy entrypoint (runs as non-root)
    HEALTHCHECK /healthz (readiness) + /livez (liveness)
```

Build-time rules:

* Pin **all** pip requires (stage 3.9 §35): `requirements/base.txt`,
  `dev.txt`, `test.txt`, `prod.txt`, `constraints.txt` with `--require-hashes`.
* Build images with `--no-cache` on release branches; never tag `:latest` in
  prod — use immutable `git-sha` + semantic version tag.
* Scans (`trivy`) run in CI before registry push (3.9 §21); failing scans
  block the pipeline.
* No secret baked at build time — all secrets via runtime env / mounted
  secret files / secret manager.
* `debug`/`dev` images are never pushed to the release registry.

## 4. Runtime Design (per app host)

```
┌──────────────────────── App Host (single VPS, Phase 1) ────────────────────────┐
│  systemd units  /  or  compose project (design choice decided at Stage 4)      │
│                                                                                │
│  nginx (TLS/route/static) ──► backend:8000 (HTTP, internal 127.0.0.1)          │
│                                 └─ worker (Celery) ← redis:6379 (internal)     │
│  postgres:5432 (system service, NOT container)                                 │
│  backup timer + rsync/PITR (system)                                            │
└─────────────────────────────────────────────────────────────────────────────────┘
```

Internal ports bound to `127.0.0.1` only; everything else blocked by firewall
(`deployment-design.md` §32/§35).

## 5. Compose Layout (conceptual, Stage 4)

```yaml
# docker-compose.yml — CONCEPTUAL ONLY, not created now
services:
  backend:
    build: .
    image: registry.example/sicklers-warriors/backend:<tag>   # immutable tag
    env_file: .env.prod        # sourced from secret manager, never Git
    depends_on: [postgres-not-containerized]
    restart: unless-stopped
    volumes:
      - media:/srv/media        # private uploaded files (not in image)
  worker:
    image: registry.example/sicklers-warriors/backend:<tag>
    command: celery -A config worker --loglevel=INFO
    env_file: .env.prod
    restart: unless-stopped
  redis:
    image: redis:7-alpine       # only if queue/cache approved
    command: redis-server --save '' --appendonly yes
    volumes: [redis-data:/data]
  nginx:
    build: ./docker/nginx
    ports: ["443:443", "80:80"]
    depends_on: [backend]
    volumes: [static:/srv/static, media:/srv/media]
```

## 6. Data Volumes (never in image)

| Volume | Contains | Access |
|---|---|---|
| `media` | uploaded doctor licenses, medical docs, profile images (Phase 1 local) | Read by backend + nginx via private route **disabled**; documents served via signed URL only (3.8 §19) |
| `static` | `collectstatic` output + admin build | Public via nginx/CDN (non-sensitive only) |
| `redis-data` | transient queue state | Loss-tolerant; never PHI |
| postgres datadir | — | **host filesystem** (backup via pg_basebackup/pg_dump host tools) |

## 7. Health, Lifecycle & Logging

* Health: container `HEALTHCHECK` calls `/livez` (liveness) and readiness probes
  hit `/healthz` through nginx path `/_internal/...` (firewall-only reachable).
* Graceful stop: `SIGTERM` → Gunicorn graceful drain → Celery `--time-limit` +
  task ACK semantics so no task is lost.
* Logs: container JSON logs → host journald/fluent path → retention policy
  (3.8 §28/§42). Never log tokens/PHI.

## 8. Registry & Rollback

* `registry.example/sicklers-warriors/backend:v1.x.x-<git-sha>`
* Previous N image tags retained → instant rollback by re-pointing tag
  (3.9 §29/§32).
* Private registry only; registry token is a CI/CD secret.

## 9. Environments

| Env | Compose profile | DB | Notes |
|---|---|---|---|
| DEV | `backend` + local Postgres 5432 (`sickle_cell`) | dev | no Redis |
| TEST | ephemeral CI containers | ephemeral | per-job `sickle_cell_test` |
| STAGING | compose on staging host | staging PG | mirrors prod topology |
| PRODUCTION | compose on prod host (Phase 1) | prod PG | system/managed PG |

## 10. Constraints & Omitted Items

* No Kubernetes, no service mesh, no sidecar proxies in Phase 1 (3.9 §40).
* No `--privileged`, no host network mode; only named volumes + 127.0.0.1 binds.
* No Docker secrets feature dependency — prefer host-level secret files
  (revisionable by config mgmt) or managed secret store.
* PostgreSQL never in compose in Phase 1 (paragraph "Do not containerize
  PostgreSQL automatically if managed PostgreSQL is more appropriate").

---

_End of deployment-docker-architecture.md (3.9 companion)._