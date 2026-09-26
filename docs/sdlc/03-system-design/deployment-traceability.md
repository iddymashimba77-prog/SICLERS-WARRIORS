# 3.9 Stage — Deployment Traceability

> Part of Stage 3.9 Deployment Design (§48). Maps deployment requirements back
> to the approved Requirements, Architecture, API, Database, Security, Mobile
> and Admin designs. Columns per mandate: Requirement | Component | Environment
> | Deployment Requirement | Security Requirement | Monitoring.

Legend — Source references:
* R = `docs/sdlc/02-requirements/*` (NFR = non-functional, SEC = security, BR = business rules)
* A3.1 = `application-architecture.md`, S3.1 = `system-architecture.md`
* API = `api-design.md` / `api-endpoint-matrix.md`
* DB = `database-design.md` / `erd`
* SEC = `security-design.md` (SD-N) / `security-review.md` (ASG-N)
* MOB = `mobile-ui-ux-design.md`, ADM = `admin-web-ui-ux-design.md`

---

## 1. Core Deployment

| Requirement | Component | Environment | Deployment Requirement | Security Requirement | Monitoring |
|---|---|---|---|---|---|
| NFR availability, BR-005 | Backend API | PROD | Production WSGI/ASGI server (Gunicorn/Uvicorn, workers), no dev server | non-root, HTTPS-only, secrets via manager | /livez, /healthz, error rate, p95 latency |
| NFR scalability | Backend | STAGING=PROD parity, PROD | Same image/tag promoted (parity), immutable tags | Image signing, no `:latest` in prod | deploy log, image digest audit |
| API 3.5 (§1–§2) | API routing | PROD | `api.<domain>` reverse-proxied, version `v1` | TLS 1.2+, HSTS, trust proxy | uptime, HTTP status codes |
| NFR reliability | Nginx | PROD | Reverse proxy TLS/static/WebSocket-forward, request limits, gzip | restrict ports, security headers, no PHI in logs | connection count, 5xx |
| NFR latency/connectivity | PostgreSQL | PROD | Same host Phase 1, managed/priv-net Phase 2+; least-privilege app user; pooling (Phase 2) | TLS-to-DB if remote, no public exposure, no superuser | pool, replication lag, slow queries |
| NFR backup (3.8 NFR-SEC-005) | Backup system | ALL | pg_dump nightly + WAL/PITR, encrypted (GPG AES-256), off-site, restore drill | encryption at rest, key access limited | backup job status, restore drill pass |
| BR-012 audit | audit_logs/security_events | PROD | Append-only target (design: `audit_logs`, `security_events`), log retention 90d/365d | no PHI in details (SEC §27/§42) | audit writes, retention age |

## 2. Security-related (walk-on from 3.8)

| Requirement | Component | Environment | Deployment Requirement | Security Requirement | Monitoring |
|---|---|---|---|---|---|
| SEC §6 MFA | Auth service | PROD | TOTP enforced admin + step-up; recovery OTP; no MFA deactivation in prod | MFA secret encrypted (`mfa_secret_encrypted` bytea — DB) | login events, failed-token rate |
| SEC §31 sessions/JWT | Auth | prod API | Refresh rotation, token denylist active, device flag (ASG-10) | signing key rotated, no token logging | refresh failure rate |
| SEC §19 licenses/docs | File storage | PROD | Private bucket/storage; signed URLs 60–600s; **no public object policy** | server-side encryption + GPG backups, download audit | access-log alerts |
| SEC §22 payments | Payment service | PROD | Prod creds separate from test; webhook HTTPS; signature+nonce±5min+idempotency | secret store for payment secrets | webhook failures, reconciliation mismatches |
| SEC §23 notifications | FCM/SMS/Email | PROD | Prod projects/credentials separated; service-account JSON via secret manager | FCM JSON never in Git; PHI-scrubbed payloads | delivery receipts, retry queue depth |
| SEC §30 recovery | account recovery | PROD | Rate-limited recovery endpoints live | OTP/TTL, anomalies → security_events | anomaly alerts |
| SEC §28 monitoring | Metric/alerting | PROD | Scrape endpoint internal only | no PHI in metrics labels | alert fires validate |

## 3. Environments

| Environment | Backend | DB | Admin | Mobile | Real services |
|---|---|---|---|---|---|
| DEV (local) | `DEBUG=true` | local 5432 `sickle_cell` (dev) | vite dev server | `--dart-define` dev | none / sandbox |
| TEST (CI) | ephemeral | ephemeral test DB | test build | integration | sandbox providers |
| STAGING | parity image | staging DB | staging domain | staging | sandbox FCM/sum, dummy SMS |
| PROD | prod image | `sickle_cell_prod` | `admin.<domain>` | `prod` flavor | prod FCM, real SMS/Email, prod payments |

Deployment lock: prod DB reachable **only** from PROD backend host;
no dev/staging container can ever see the prod DB.

## 4. Mobile & Admin mapping

| Requirement | Component | Environment | Deployment Requirement | Security Requirement | Monitoring |
|---|---|---|---|---|---|
| MOB (3.6) offline-first | Mobile app | DEV/TEST/STAGING/PROD | build flavors + `--dart-define` per env; **no runtime hardcoded prod secrets** | signing keystore private; app stores cryptographically signed | crash/ANR rates |
| MOB notifications | FCM client | PROD | FCM routing per build; requested runtime permission | perms least-privilege; no PHI in messages | FCM send failures |
| ADM (3.7) admin web | Admin SPA | PROD | `admin.<domain>` static build + HTTPS, API via `api.<domain>`, MFA mandatory | never any backend secret in SPA bundle; CORS limited to admin origin | admin login/audit events |
| API gate (3.5 §27–§29) | API layer | ALL | rate limits per class in prod settings | object-level permissions + audits | throttled-request counters |

## 5. CI/CD & Git

| Requirement | Component | Environment | Deployment Requirement | Security Requirement | Monitoring |
|---|---|---|---|---|---|
| NFR controlled release | CI/CD | CI | Pipeline: lint→unit→security→build→test→staging→approval→prod (3.9 §18/§21); **no auto-prod deploy** | CI secrets scoped; prod deploy via approval + SSH key | pipeline status, deploy history |
| Protected branches | Git | ALL | `main` protected; PR review + required checks; release branches; hotfix path | no force-push, signed tags, deploy only from tags | commit/tag audit |

## 6. Non-functional targets (measure)

| NFR target | Baseline | Current status of platform | Notes |
|---|---|---|---|
| RPO ≤24h (target ≤1h) | designed (SEC) | **not implemented** — Stage 4/5 | restore drill to prove |
| RTO ≤4h | designed (SEC) | **not implemented** | run by runbook, drill result |
| 99.9% uptime goal | designed | n/a (no prod yet) | monitoring once live |

## 7. Open/tracking references

* ASG-1..10 (3.8 API gaps) → become Stage-4 implementation tasks + deployment implications (e.g. device-flag needs endpoint config).
* CBD-1..7 (3.8 DB changes) → Stage-4 schema tasks (security_events index, token_denylist, mfa_secret_encrypted, emergency_access_grants).
* Zero-commit Git repo / no CI today → Stage 4 baseline task.
* Admin-web build target: `VITE_API_BASE_URL` per env (no baked secrets).

---

_End of deployment-traceability.md (3.9 companion)._