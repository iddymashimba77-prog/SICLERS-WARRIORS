# 3.8 Security Implementation Checklist

> Stage 4 developer checklist derived from `security-design.md`,
> `security-api-traceability.md`, `security-database-traceability.md`,
> `security-risk-register.md`. Mark each item:
> **REQUIRED** (must ship before production) · **RECOMMENDED** (should ship) ·
> **FUTURE** (v2, no blocker).
> This is a design artifact for the Stage 4 contract, not the implementation
> itself.

---

## 1. Secrets & Configuration

- [ ] **REQUIRED** — No secrets in source code; all via env vars / `.env` (gitignored).
- [ ] **REQUIRED** — `.env.example` with names only, no values.
- [ ] **REQUIRED** — `SECRET_KEY` from env, not the Django default (SD-14).
- [ ] **REQUIRED** — `DEBUG=False`, `ALLOWED_HOSTS` set in production (SR-025/026).
- [ ] **REQUIRED** — `CORS_ALLOW_ALL_ORIGINS=False`; `CORS_ALLOWED_ORIGINS` explicit (SD-9).
- [ ] **REQUIRED** — Per-provider secrets segmented (payments, Firebase, SMS, email).
- [ ] **RECOMMENDED** — Secrets manager / KMS wiring (3.9 production).
- [ ] **FUTURE** — Vault-based dynamic secrets.

---

## 2. Authentication

- [ ] **REQUIRED** — Password hashing `Argon2id` (fallback PBKDF2) with salts (SD-1).
- [ ] **REQUIRED** — Unified login (no account-existence disclosure; SR-027).
- [ ] **REQUIRED** — JWT access (15 min) + rotating refresh; denylist (SD-4).
- [ ] **REQUIRED** — Login ratelimit (5/min) + lockout (10) + security_event.
- [ ] **REQUIRED** — Registration role allow-list; email+phone verification before sensitive use.
- [ ] **REQUIRED** — Reset: 202-always request; single-use timed token; MFA-challenge on admin (SD-3).
- [ ] **REQUIRED** — Password policy: min 10 (12 admin), common-list block, rotation window (SD-2).
- [ ] **REQUIRED** — `auth.sessions` list/revoke device management.
- [ ] **RECOMMENDED** — Impossible-travel / new-device step-up (SD-5; ASG-10).

---

## 3. MFA

- [ ] **REQUIRED** — TOTP enable/disable/setup via `/auth/mfa/*`; sealed secret (SD-16).
- [ ] **REQUIRED** — MFA mandatory for admin roles (3.7).
- [ ] **REQUIRED** — Step-up re-auth for: role assign, refunds, emergency override, settings, C4 medical open (SD-5).
- [ ] **REQUIRED** — Recovery codes: 8 single-use, hashed-stored, re-enroll flow (SD-6; CBD-1).
- [ ] **REQUIRED** — MFA verify rate limit (5/min).
- [ ] **RECOMMENDED** — Device-trust (revocable, non-default) (SD-5).

---

## 4. Authorization

- [ ] **REQUIRED** — DRF permission classes mirror 3.3 matrix per endpoint.
- [ ] **REQUIRED** — Object-level authorization filters for every sensitive resource (IDOR) (3.5 §28).
- [ ] **REQUIRED** — Consent resolver in record queries (owner/grantee/scope/expiry).
- [ ] **REQUIRED** — C4 reason-locked gates for admin medical access (AD-A-9).
- [ ] **REQUIRED** — C17 exclusivity: role assignment SUP-only, never self-assign.
- [ ] **REQUIRED** — Masked outputs (donor PII, contacts, payment payloads) (BR-006).
- [ ] **REQUIRED** — Deny-by-default (absent permission = denied).

---

## 5. Validation & Input

- [ ] **REQUIRED** — DRF serializers whitelist fields (anti mass-assignment).
- [ ] **REQUIRED** — Parameterized ORM queries only (no string SQL).
- [ ] **REQUIRED** — HTML sanitizer (community/chat/education) allow-list tags.
- [ ] **REQUIRED** — Payload size/field-count caps; pagination ≤100.
- [ ] **REQUIRED** — UUID/positive-int validators on all resource IDs.
- [ ] **RECOMMENDED** — SSRF guard on any external fetch (allowlist URLs).

---

## 6. Encryption & Keys

- [ ] **REQUIRED** — TLS 1.2+/1.3 in production; HTTPS-only.
- [ ] **REQUIRED** — `mfa_secret_encrypted` AES-GCM sealed (SD-16).
- [ ] **REQUIRED** — Encrypted media storage + signed short-TTL download URLs.
- [ ] **REQUIRED** — Backup encryption (GPG AES-256) before off-site (SD-15).
- [ ] **REQUIRED** — JWT signing key from env/secrets (SD-14).
- [ ] **RECOMMENDED** — Key rotation cadence enforced (SD-17).

---

## 7. Files & Documents

- [ ] **REQUIRED** — Extension + MIME + magic-bytes allowlist; size caps (SD-20).
- [ ] **REQUIRED** — Randomized storage filenames (never client names) (SD-8).
- [ ] **REQUIRED** — Signed-URL download with permission check; no static public dir.
- [ ] **REQUIRED** — Doctor-license storage reviewer-scope only (C6), audit every access.
- [ ] **RECOMMENDED** — ClamAV scan path (Stage 4 add-on; register §4).
- [ ] **RECOMMENDED** — Quarantine dir for unsigned content.

---

## 8. API & Web

- [ ] **REQUIRED** — CSRF for cookie flows; bearer-token JWT for SPA (no cookie CSRF).
- [ ] **REQUIRED** — Security headers: CSP(nonce), HSTS, `nosniff`, frame-deny, referrer-none (SD-10).
- [ ] **REQUIRED** — 429 handling with `Retry-After`; Redis-backed throttles.
- [ ] **REQUIRED** — Envelope errors; no stack/SQL/secrets in responses; generic auth errors.
- [ ] **REQUIRED** — Service `correlation_id` + request-id header.

---

## 9. Database

- [ ] **REQUIRED** — App role `sw_db_user` non-superuser, DML-only, no CREATEDB.
- [ ] **REQUIRED** — Migration role separate from runtime.
- [ ] **REQUIRED** — Audit tables append-only (app + DB grant `NOUPDATE/DELETE`).
- [ ] **REQUIRED** — Restrict PG network; `sslmode=require` remote.
- [ ] **REQUIRED** — No public exposure; FW allowlist.
- [ ] **RECOMMENDED** — Disk encryption plus encrypted backups.

---

## 10. Payment & Webhooks

- [ ] **REQUIRED** — No stored raw card data; provider tokens only.
- [ ] **REQUIRED** — Webhook HMAC signature + timestamp window (±5 min) + nonce + IP allowlist.
- [ ] **REQUIRED** — Idempotency keys; `transaction_ref`/`provider_ref` UNIQUE; replay detection.
- [ ] **REQUIRED** — Backend-only success (`CONFIRMED`) — never client-claimed (BR-008).
- [ ] **REQUIRED** — Reconciliation job (snapshot vs provider).
- [ ] **REQUIRED** — Refund co-sign threshold + audit + re-auth (AD-A-11).
- [ ] **RECOMMENDED** — Webhook event nonce registry (ASG-9).

---

## 11. Mobile Security

- [ ] **REQUIRED** — Tokens in `flutter_secure_storage`; no plaintext files.
- [ ] **REQUIRED** — No PHI cached; client clears on logout (SD-11).
- [ ] **REQUIRED** — No PHI/tokens in logs/debug.
- [ ] **REQUIRED** — `FLAG_SECURE` on medical/consent screens; iOS snapshot blank (SD-12).
- [ ] **REQUIRED** — App/Universal Links validation for deep links.
- [ ] **REQUIRED** — No secrets baked in binary; env-fed build config.
- [ ] **RECOMMENDED** — Biometric app-lock for sensitive area.

---

## 12. Admin Security

- [ ] **REQUIRED** — MFA mandatory; min-12 password (SD-2).
- [ ] **REQUIRED** — Idle timeout 15 min + force logout (AD-A-2).
- [ ] **REQUIRED** — Re-auth for privileged actions (SD-5).
- [ ] **REQUIRED** — Screen-role mapping + backend 403 (3.7).
- [ ] **REQUIRED** — Admin action audit with reasons (AD-A-9).

---

## 13. Privacy & Data

- [ ] **REQUIRED** — Data-classification gating (§37 deliverable).
- [ ] **REQUIRED** — No PHI in notifications/previews (G4).
- [ ] **REQUIRED** — Retention schedule + legal-hold override (SD-13).
- [ ] **REQUIRED** — Erasure flow with anonymization (SD-14).
- [ ] **RECOMMENDED** — Portability export (FUTURE flag).

---

## 14. Monitoring & Attack Response

- [ ] **REQUIRED** — Security events for: failed login, lockouts, escalation, abnormal reads, exports, payment anomalies, emergency patterns.
- [ ] **REQUIRED** — Alert thresholds → security center (3.7) + ops channel.
- [ ] **REQUIRED** — Incident playbooks (compromised admin, leaked creds, unauthorized access, payment fraud, DB compromise, upload, DoS).
- [ ] **RECOMMENDED** — Dashboard for rate-limit abuse (429 spikes).

---

## 15. Backup & Recovery

- [ ] **REQUIRED** — Automated nightly pg_dump; encrypted; off-site copy.
- [ ] **REQUIRED** — Restore test quarterly; RPO ≤24 h / RTO ≤4 h documented.
- [ ] **REQUIRED** — Runbook ownership.

---

### Acceptance

This checklist is **done** only when the SD-1..SD-21 decisions (blocking set
SD-1/4/9/14/19) are owner-signed and each `REQUIRED` box is met in Stage 4.

---

END — cross-checked with `security-design.md` and review gate.