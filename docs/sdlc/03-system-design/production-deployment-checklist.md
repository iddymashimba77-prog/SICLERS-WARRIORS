# 3.9 Stage — Production Deployment Checklist

> Part of Stage 3.9 Deployment Design (§44). **This is the future production
> readiness checklist** — nothing here is executed now. Each item is a gate
> condition that must be TRUE before the production launch that happens after
> Stage 4 (Implementation) and Stage 5 (Testing).
>
> Marking convention below is a **template** — completion is tracked later in
> Stage 4/5, not in this document.

---

## 1. Infrastructure

- [ ] Server provisioned (per `deployment-design.md` §7 minimum specs)
- [ ] OS: pinned LTS (e.g. Debian 12 / Ubuntu 24.04) with security updates enrolled
- [ ] Firewall configured: only 22 (SSH, restricted), 80, 443 open inbound; all else closed
- [ ] SSH: keys only, no password auth, no root login, MFA option for jump host
- [ ] `fail2ban`/equivalent configured for SSH + login throttling
- [ ] DNS records created for domain/subdomains (see §9 checklist below)
- [ ] TLS certificates issued + auto-renewal working
- [ ] NTP time sync verified (critical for JWT/payment nonce ±5 min window)
- [ ] Monitoring + alerting endpoints wired (uptime, disk, CPU, memory)
- [ ] System package/cron for automated security patches configured

## 2. Backend

- [ ] Production settings module used (`DEBUG=false`); `django-insecure-*` key NEVER used
- [ ] Environment variables injected from secret manager (not in Git)
- [ ] WSGI/ASGI server (Gunicorn/Uvicorn) — dev server NOT used
- [ ] Workers configured (`backend`, `worker`, scheduler)
- [ ] `collectstatic` ran; static served via nginx/CDN
- [ ] Migrations applied per runbook (approved, backed-up, reversible-friendly)
- [ ] Health endpoints live (`/livez`, `/healthz`) — liveness vs readiness
- [ ] Logging structured JSON, no PHI/tokens; shipping enabled
- [ ] Graceful restart verified (no dropped in-flight requests)
- [ ] Sentry/error tracking enabled with PHI scrubbers
- [ ] Rate limits verified (3.5 §29 values active in prod settings)
- [ ] CORS/CSRF/HSTS/secure-cookie settings verified

## 3. Database

- [ ] Production DB created (`sickle_cell_prod`) with least-privilege app user
- [ ] App DB user is NOT superuser/root; no public exposure (port closed)
- [ ] `DB_SSLMODE` enforced if DB not same-host
- [ ] Connection pooling decision applied (PgBouncer if needed)
- [ ] Initial backup taken
- [ ] **Restore test executed** (backup is not valid until restored — 3.9 §30)
- [ ] PITR/WAL archiving configured if RPO ≤1h required (3.8 NFR-SEC)
- [ ] Monitoring: disk, connections, slow queries
- [ ] Credentials stored ONLY in secret manager

## 4. Security

- [ ] Secrets: all rotated, unique per environment (SECRET_KEY, JWT, DB, SMS, FCM, payments)
- [ ] No secrets in source, logs, or client bundles
- [ ] HTTPS-only (HTTP→HTTPS redirect, HSTS) verified by external scan
- [ ] Access controls: app roles/permissions (3.3) active
- [ ] Security events + audit_logs recording to append-only storage
- [ ] Emergency access config restricted (24h window, justification — 3.8 §10)
- [ ] MFA TOTP enforced for all admin roles (3.8 §6/§25); recovery path tested
- [ ] Open ports audited (3.9 §35): only necessary
- [ ] Dependency vulnerability scan clean (3.9 §35/§38)
- [ ] Firewall/FW rules reviewed by second person
- [ ] Anti-scanning/IDS baseline (Phase 2; note if deferred)

## 5. Mobile

- [ ] Release configuration: `prod` flavor/dart-define only, no dev endpoints in bundle
- [ ] Android release keystore created, stored securely, NEVER in repo; `key.properties` gitignored
- [ ] Version codes/bump policy applied (semantic)
- [ ] API endpoint: `https://api.<domain>` verified reachable from production mobile
- [ ] Push (FCM) configured for prod project; test notification delivered
- [ ] SMS/email notifications verified on prod provider
- [ ] App-store metadata/screenshots/privacy policy live
- [ ] iOS (if/when built): certs+provisioning in secure store, TestFlight verified

## 6. Admin Web

- [ ] `admin.<domain>` resolves; HTTPS valid
- [ ] Build uses prod environment; static assets cache-hashed
- [ ] Authentication + MFA tested against prod API
- [ ] Permissions (3.3 matrix) verified per role on prod
- [ ] No backend secrets reachable from admin bundle/network
- [ ] Rollback tagged (previous build retained)

## 7. Payments

- [ ] Production credentials provisioned (M-Pesa, Tigo, Airtel, ClickPesa, Selcom, card)
- [ ] TEST and PRODUCTION credential sets are separate and never mixed (3.8 §22)
- [ ] Webhook URLs registered; HTTPS verified reachable per provider
- [ ] Signature verification + nonce + ±5 min window tested end-to-end
- [ ] Idempotency for double-callbacks verified
- [ ] Reconciliation job configured + tested against provider statements
- [ ] Alerts on payment failures/reconciliation mismatches configured
- [ ] Sandbox flag OFF in prod config

## 8. Notifications

- [ ] Firebase service-account JSON stored in secret manager (never in Git)
- [ ] FCM Sender/VAPID keys set for prod
- [ ] Dev/test/staging/prod project separation verified
- [ ] SMS provider prod credentials verified; sender ID approved
- [ ] Email SMTP verified; `no-reply@` set up; DKIM/SPF checked
- [ ] Notification failure handling + retry (queue) tested
- [ ] Privacy: no PHI inside notification payloads (3.8 §24)

## 9. DNS / Domain

- [ ] A/AAAA records: main, api, admin, staging, api-staging
- [ ] TTLs reasonable (300s during launches, higher after stable)
- [ ] Cert validation records (acme/challenge) documented
- [ ] Domain + cert expiry monitoring active (3.9 §39)

## 10. Observability

- [ ] Uptime monitor (external) active for api + admin + main
- [ ] Log ingestion + retention per 3.8 (90d app, 365d auth/payment)
- [ ] Metrics dashboards: CPU, memory, disk, DB, latency p95, error rate
- [ ] Alerts configured: down, DB unavailable, high error, disk 80%, suspicious auth, payment failures
- [ ] Incident response contact/rotation defined (3.8 §38)

## 11. Backup / DR

- [ ] Encrypted backups (GPG AES-256) running on schedule
- [ ] Off-site/DR copy active (different location/provider)
- [ ] **Restore drill passed** (RPO/RTO measured against targets: RPO ≤24h, target ≤1h; RTO ≤4h)
- [ ] Backup monitoring alert on failure enabled
- [ ] DR runbook referenced; personnel aware of steps

---

## Verification matrix (template — completed at launch time, not now)

| # | Category | Check | Result | Evidence |
|---|---|---|---|---|
| 1 | Infrastructure | firewall only 22/80/443 | ☐ | `ss -tlnp` |
| 2 | Backend | DEBUG=false | ☐ | prod settings |
| 3 | Database | restore test | ☐ | restore log |
| 4 | Security | no-secret leak scan | ☐ | grep + CI |
| 5 | Mobile | prod endpoint | ☐ | build archive |
| 6 | Admin | MFA login | ☐ | smoke test |
| 7 | Payments | webhook signed+idempotent | ☐ | callback log |
| 8 | Notifications | FCM delivered | ☐ | device log |
| 9 | DNS | all records resolve | ☐ | dig query |
| 10 | DR | drill RTO/RPO | ☐ | drill report |

---

_End of production-deployment-checklist.md (3.9 companion). Not executed now._