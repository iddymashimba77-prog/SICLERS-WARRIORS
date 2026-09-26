# 3.9 Stage — Deployment Environment Variables

> Part of Stage 3.9 Deployment Design. This file defines the **catalogue of
> environment categories and variable names** used across Development, Test,
> Staging and Production.
>
> **No real values are written in this document.** Secrets are never stored in
> Git (`.env` is gitignored; `backend/.env.example` carries placeholder names
> only). Values are injected per environment via `.env` / secret manager / CI/CD
> secrets (see `deployment-design.md` §33–34).
>
> Classification levels:
> * **PUBLIC** — non-sensitive configuration; safe to commit as defaults.
> * **SECRET** — must never appear in source, commits, logs, or client apps.
> * **MIXED** — name is safe, but value may be sensitive depending on environment.

---

## 1. Django Core

| Variable | Level | Purpose | Example / Notes |
|---|---|---|---|
| `DJANGO_SETTINGS_MODULE` | PUBLIC | Settings class to load | `config.settings.dev` / `.test` / `.staging` / `.prod` (Stage 4 split) |
| `DEBUG` | PUBLIC | Debug mode flag | `false` in staging/prod at all times |
| `SECRET_KEY` | SECRET | Django signing key | Random ≥50 chars; unique per environment; never the dev value |
| `ALLOWED_HOSTS` | PUBLIC | Host whitelist | Comma-separated; no wildcard in prod |
| `ROOT_URLCONF` | PUBLIC | URL module | `config.urls` |
| `TIME_ZONE` | PUBLIC | App timezone | `Africa/Dar_es_Salaam` (business rules; reminders follow this TZ) |
| `LANGUAGE_CODE` | PUBLIC | Default language | `en` (UI strings in Swahili are data/messages, not locale switch) |

## 2. Database (PostgreSQL)

| Variable | Level | Purpose | Notes |
|---|---|---|---|
| `DB_NAME` | PUBLIC | Database name | Prod `sickle_cell_prod` (NOT reusing dev DB names) |
| `DB_USER` | PUBLIC | App DB user | Least-privilege; **never `root`, never superuser** (3.8, §12/§14) |
| `DB_PASSWORD` | SECRET | App DB password | Per-env; staged rotation |
| `DB_HOST` | PUBLIC | DB host | Same-host `127.0.0.1` Phase 1; `DB_PRIVATE_IP` for managed PG |
| `DB_PORT` | PUBLIC | DB port | Default `5432`; legacy local `5433` cluster is NOT production-app DB |
| `DB_SSLMODE` | PUBLIC | TLS for DB link | `require`/`verify-full` for any non-local link |
| `DB_OPTIONS` | MIXED | PgBouncer/constraints | `-c statement_timeout=...` where required |
| `DATABASE_URL` | MIXED | Combined URL (optional) | Prefer explicit `DB_*` vars; if used, holds secret → SECRET |

## 3. Application Security

| Variable | Level | Purpose | Notes |
|---|---|---|---|
| `ACCESS_TOKEN_LIFETIME_MINUTES` | PUBLIC | JWT access TTL | 15 (3.8) |
| `REFRESH_TOKEN_LIFETIME_DAYS` | PUBLIC | Rotating refresh TTL | Mobile 30 / Admin 8h (3.8) |
| `AUTH_PASSWORD_ITERATIONS` | PUBLIC | Argon2id params override | Leave default; tune only with documented reason |
| `CORS_ALLOWED_ORIGINS` | PUBLIC | Allowed origins for Admin Web | `https://admin.<domain>` |
| `CSRF_TRUSTED_ORIGINS` | PUBLIC | CSRF trusted hosts | Admin Web origin only |
| `SESSION_COOKIE_SECURE` | PUBLIC | Cookies TLS-only | `true` in staging/prod |
| `SECURE_SSL_REDIRECT` | PUBLIC | HTTP→HTTPS | `true` at Nginx (not app) |
| `HSTS_*` | PUBLIC | HSTS headers | `SECURE_HSTS_SECONDS` etc. |
| `SECURE_PROXY_SSL_HEADER` | PUBLIC | X-Forwarded-Proto trust | Only behind Nginx |

## 4. API / Rate Limiting / Cache

| Variable | Level | Purpose | Notes |
|---|---|---|---|
| `API_BASE_URL` | PUBLIC | Public API URL | `https://api.<domain>` |
| `API_VERSION` | PUBLIC | Version prefix | `v1` |
| `RATE_LIMIT_LOGIN_MIN` | MIXED | Login throttle (3.5 §29) | Per IP/user, config-driven |
| `RATE_LIMIT_GLOBAL_MIN` | MIXED | Global throttle | Tiered anonymous/authed |
| `REDIS_URL` | SECRET | Redis broker/cache | Only when Celery/Redis approved (§13) |
| `CACHE_BACKEND_ARGS` | MIXED | LocMem in dev / Redis in prod | Never cache PHI (3.8, §41) |

## 5. Authentication / MFA / Tokens

| Variable | Level | Purpose | Notes |
|---|---|---|---|
| `JWT_SIGNING_KEY` | SECRET | Token signing (or reuse SECRET_KEY) | Rotated with SECRET_KEY |
| `MFA_TOTP_ISSUER` | PUBLIC | Authenticator issuer label | `Sickler's Warriors` |
| `OTP_*` | MIXED | TOTP/backup-code params | Algorithm/length defaults |
| `PASSWORD_RESET_TOKEN_TTL` | PUBLIC | Recovery TTL (3.8 §30) | |
| `DEVICE_API_KEY` | SECRET | Device registration pre-auth key | Only if required by 3.5 amendments |

## 6. File Storage

| Variable | Level | Purpose | Notes |
|---|---|---|---|
| `STORAGE_BACKEND` | PUBLIC | `local` / `s3` | Phase 1 local private dir; Phase 2 object storage |
| `STORAGE_ROOT` | PUBLIC | Private storage dir | Outside web root; not served by Nginx (3.8) |
| `STORAGE_BUCKET` | PUBLIC | Object-storage bucket | Private bucket, no public policy (3.7 §16, 3.8 §19) |
| `STORAGE_REGION/ENDPOINT` | PUBLIC | Provider endpoint | In-country where legally required |
| `STORAGE_ACCESS_KEY` | SECRET | Object-storage key | |
| `STORAGE_SECRET_KEY` | SECRET | Object-storage secret | |
| `SIGNED_URL_TTL` | PUBLIC | Presigned URL TTL | 60–600s (documents) |
| `MEDIA_URL_PUBLIC` | PUBLIC | Public media prefix | Only for approved-public images (none PHI) |

## 7. Django Static / Admin Web

| Variable | Level | Purpose | Notes |
|---|---|---|---|
| `DJANGO_STATIC_URL` | PUBLIC | Static URL prefix | Served by Nginx/CDN |
| `DJANGO_STATIC_ROOT` | PUBLIC | Static collect dir | |
| `ADMIN_WEB_URL` | PUBLIC | Admin panel origin | `https://admin.<domain>` |
| `VITE_API_BASE_URL` | PUBLIC | Admin build-time API URL (Vite env) | Compile-time; not in bundle as secret |

## 8. Email / SMS / Notifications

| Variable | Level | Purpose | Notes |
|---|---|---|---|
| `EMAIL_BACKEND` | PUBLIC | SMTP / SES | Console in dev, SMTP in prod |
| `EMAIL_HOST_*` | MIXED | SMTP host/port/user | |
| `EMAIL_HOST_PASSWORD` | SECRET | SMTP password | |
| `EMAIL_FROM` | PUBLIC | Sender address | `no-reply@<domain>` |
| `DEFAULT_FROM_EMAIL` | PUBLIC | Fallback sender | |
| `SMS_PROVIDER` | PUBLIC | `africastalking`/other | Chosen at Stage 4 |
| `SMS_API_KEY` | SECRET | SMS provider key | |
| `SMS_SENDER_ID` | PUBLIC | Sender label | |
| `SMS_TEMPLATE_*` | MIXED | Message templates | Never PHI in content (3.8) |

## 9. Firebase / Push

| Variable | Level | Purpose | Notes |
|---|---|---|---|
| `FIREBASE_PROJECT_ID` | PUBLIC | GCP project | |
| `FIREBASE_SERVICE_ACCOUNT_JSON` | SECRET | Service-account JSON | **Never committed** (3.8 §23); injected via secret manager |
| `FIREBASE_VAPID_KEY` | SECRET | Web push VAPID | |
| `FCM_DRY_RUN` | PUBLIC | Send-test mode | true in dev/test |
| `NOTIFICATION_PLATFORM` | PUBLIC | `fcm` / `apns` | Per app store build |

## 10. Payments

| Variable | Level | Purpose | Notes |
|---|---|---|---|
| `PAYMENT_PROVIDERS` | PUBLIC | Enabled set | `mpesa,tigo,airtel,clickpesa,selcom,card` |
| `MPESA_*`, `TIGO_*`, `AIRTEL_*`, `CLICKPESA_*`, `SELCOM_*`, `CARD_*` | MIXED | Provider config | Consumer key/secret, shortcode, passkeys |
| `PAYMENT_ENV` | PUBLIC | `sandbox` / `production` | **Explicit per environment; TEST creds never on prod** (3.8 §22) |
| `WEBHOOK_BASE_URL` | PUBLIC | Callback base URL | `https://api.<domain>`; registered per provider |
| `WEBHOOK_NONCE_STORE` | PUBLIC | Nonce registry (ASG-10) | Redis/DB-backed |
| `PAYMENT_SECRET_KEY` | SECRET | Signing/verification keys | Per provider; rotated |
| `IDEMPOTENCY_TTL` | PUBLIC | Replay window | ±5 min (3.8 §22) |

## 11. Observability

| Variable | Level | Purpose | Notes |
|---|---|---|---|
| `LOG_LEVEL` | PUBLIC | App log level | `INFO` prod, `DEBUG` dev |
| `LOG_FORMAT` | PUBLIC | `json` / `text` | Structured JSON in prod |
| `LOG_RETENTION_DAYS` | PUBLIC | Log retention | 90 (auth/payment 365) |
| `SENTRY_DSN` | SECRET | Error tracking | PHI scrubbing enabled (3.8 §42) |
| `SENTRY_TRACES_SAMPLE_RATE` | PUBLIC | Sampling | Low; never sample PHI payloads |
| `METRICS_ENDPOINT_PORT` | PUBLIC | /metrics scrape port | Internal only |

## 12. Backup / Ops

| Variable | Level | Purpose | Notes |
|---|---|---|---|
| `BACKUP_DIR` | PUBLIC | Encrypted backup path | GPG AES-256 (3.8 §17, §32) |
| `BACKUP_GPG_PUBLIC_KEY_ID` | PUBLIC | Recipient key | |
| `BACKUP_ENCRYPTION_KEY_ID` | PUBLIC | Key identifier | |
| `BACKUP_RETENTION_*` | PUBLIC | Daily/weekly/monthly counts | |
| `PITR_WAL_DIR` | PUBLIC | WAL archive dir | |
| `DR_OFFSITE_ENDPOINT` | MIXED | Offsite copy target | |
| `DR_OFFSITE_CREDENTIALS` | SECRET | Offsite copy auth | |

## 13. CI/CD

| Variable | Level | Purpose | Notes |
|---|---|---|---|
| `CI` | PUBLIC | Set by pipeline | |
| `TEST_DB_NAME/DB_USER/DB_PASSWORD` | MIXED | Test-runner DB | Ephemeral per job |
| `GPG_PRIVATE_KEY` | SECRET | Signing (repo sigs) | |
| `DOCKER_REGISTRY` | MIXED | Image registry | |
| `DOCKER_REGISTRY_TOKEN` | SECRET | Push token | |
| `DEPLOY_SSH_KEY` | SECRET | CD deploy key | Individual, revocable (3.9 §43) |
| `GH/CI_TOKEN` | SECRET | Provider token | |

---

## 14. Public vs Secret — Summary Rule

| Class | Handling |
|---|---|
| **PUBLIC** | Commit to `.env.example`; inject per environment with per-env value |
| **MIXED** | Name may appear in `settings.py` defaults; content injected per env |
| **SECRET** | Never in Git (`.env` gitignored), never in logs, never in mobile/admin bundles; inject via secret manager or CI/CD secrets; rotate per policy |

**Proof rule (3.8 applied):** a value is SECRET if disclosure would let an
attacker impersonate a user, sign data, access PHI, spend money, or break
audit integrity. When in doubt, classify as SECRET.

---

## 15. Environment Matrices

### 15.1 Per-Environment Presence

| Variable group | DEV | TEST | STAGING | PRODUCTION |
|---|---|---|---|---|
| DEBUG | true | true | **false** | **false** |
| SECRET_KEY | dev-only | test-only | staging-only | **prod-only (rotated)** |
| DB | local `sickle_cell` (dev) | ephemeral test DB | staging DB | prod DB (`sickle_cell_prod`) |
| Payments | sandbox | sandbox | sandbox | **production creds** |
| Firebase | dev project | dev project | staging project | production project |
| SMS/Email | console/log | dummy provider | sandbox provider | real provider |
| Storage | local | local/ephemeral | private bucket | private bucket |
| Monitoring | none | minimal | full alerts | full alerts + on-call |

### 15.2 No-Go Rules

* Never point a non-production environment at the **production database**.
* Never copy production PHI into dev/test/staging without approved
  anonymization (3.9 §38).
* Never reuse **payment production credentials** outside production.
* Never allow `DEBUG=true` in Staging or Production.
* Never store secrets in the Flutter `--dart-define` that ships in a bundle.

---

_End of deployment-environment-variables.md (3.9 companion)._