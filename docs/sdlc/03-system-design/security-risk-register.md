# 3.8 Security Risk Register

> Stage 3.8 — Security Design. Threat model + risk register for Sickler's
> Warriors, fed by 3.5 API design, 3.4 DB design, 3.3 roles/permissions, and
> the security requirements (NFR-SEC-001..005, BR-001..012, 2.9 Security
> Requirements). This register is the design-time contract; residual risks are
> re-validated in Stage 4 implementation and Stage 5 testing.

Scoring (design): **Likelihood** 1(low)–5(high) × **Impact** 1–5 → **Risk** =
likely × impact, mapped: ≤4 LOW · 5–9 MEDIUM · 10–14 HIGH · ≥15 CRITICAL.
(Mitigations assume designed controls exist; where a control is `API SECURITY
GAP`, it is flagged.)

---

## 1. Rating Scheme

| Risk | Score | Meaning |
|---|---|---|
| LOW | ≤4 | accepted / mitigated |
| MEDIUM | 5–9 | controlled; monitored |
| HIGH | 10–14 | actively managed, must-have control |
| CRITICAL | ≥15 | must be closed before production |

---

## 2. Risk Register

| ID | Threat | Asset | Likelihood | Impact | Risk | Mitigation | Owner |
| --- | ------ | ----- | ---------- | ------ | ---- | ---------- | ----- |
| SR-001 | Credential breach (users) | user accounts, PHI | 3 | 5 | HIGH (15) | Argon2id/PBKDF2+SALT (NFR-SEC-002); rate-limited login; lockout; MFA admin + optional user; breach notification | Platform |
| SR-002 | Account takeover (JWT theft) | user sessions, PHI | 3 | 5 | HIGH (15) | short access TTL (15 min), rotating refresh, reuse detection, denylist, device fingerprints, session revocation | Platform |
| SR-003 | MFA bypass / reset bypass | admin/medical access | 2 | 5 | HIGH (10) | TOTP sealed secret (`bytea`), MFA re-auth on sensitive ops, recovery codes single-use, reset re-auth, rate limiting | Platform |
| SR-004 | IDOR on medical records (patient B reads patient A) | medical_records | 3 | 5 | HIGH (15) | object-set filters (3.5 §28), UUID external IDs, DRF object permissions, IDOR test suite | Backend |
| SR-005 | Doctor over-reach (BR-003) | medical histories | 4 | 4 | HIGH (16) | consent-gated access (BR-004), scope resolution, per-record links, no bulk history | Backend |
| SR-006 | Unauthorized admin PHI access | records, consents | 3 | 4 | HIGH (12) | least privilege (3.3), C4 reason-locked gates (3.7 AD-A-9), audit, no "see all" | Admin |
| SR-007 | Consent abuse/forged grant | records access | 2 | 5 | HIGH (10) | consent signed server-side (BR-004), grant/revoke API only, consent history, expiry, audit | Backend |
| SR-008 | Emergency access abuse (BR-009) | emergency data | 3 | 4 | HIGH (12) | bounded C10 override, `emergency_access_grants`, justification, 24h expiry, audit, anomaly flags | Backend |
| SR-009 | Payment forgery / client-declared success (BR-008) | donations, payouts | 3 | 5 | HIGH (15) | backend-verified webhooks + signature (HMAC), idempotency keys, no client success claim, reconciliation | Payments |
| SR-010 | Webhook replay/forgery | payment records | 2 | 5 | HIGH (10) | signature verify, timestamp window ±5 min, nonce, IP allowlist, idempotent handle, sandbox in dev | Payments |
| SR-011 | Duplicate payments / double-spend | transactions | 2 | 4 | MEDIUM (8) | idempotency keys, `transaction_ref` UNIQUE, status machine, reconciliation | Payments |
| SR-012 | Donor PII exposure (BR-006) | blood_donors | 3 | 4 | HIGH (12) | masked contacts, approximate geo, no public donor PII, verified-request flow only | Blood |
| SR-013 | Fake blood request spam | blood_requests | 3 | 3 | MEDIUM (9) | rate limits, verification steps (BR-005), facility context (C7), audit | Blood |
| SR-014 | Fake/duplicate campaign | campaigns | 3 | 3 | MEDIUM (9) | verification workflow (BR-007), beneficiary docs, approval audit | Campaigns |
| SR-015 | SQL injection | DB, patient data | 2 | 5 | HIGH (10) | DRF ORM everywhere, param queries, no raw SQL; SSRF guard for external | Backend |
| SR-016 | XSS (community/chat/education) | user sessions | 3 | 3 | MEDIUM (9) | output encoding, sanitized HTML (allowed tag whitelist), CSP, no `innerHTML` of user content | Admin/Web |
| SR-017 | Command injection | server | 1 | 5 | MEDIUM (5) | no shell exec, allowlisted commands, env-based config | Backend |
| SR-018 | Path traversal / unsafe filename | file storage | 2 | 4 | MEDIUM (8) | randomized file names, MIME + extension allowlist, size caps, signed URLs, no direct path exposure | Files |
| SR-019 | Malicious file upload (executable) | server, storage | 2 | 4 | MEDIUM (8) | type allowlist (image/pdf), magic-bytes check, anti-executable, virus scan stage, storage without exec perms | Files |
| SR-020 | PHI leak via notification preview (G4) | patients | 3 | 4 | HIGH (12) | no diagnoses in push preview; privacy-safe previews, redact templates | Notifications |
| SR-021 | Private chat leak (doctor↔patient) | conversations | 2 | 5 | HIGH (10) | C13 participant scoping, TLS, server-side row ACL, no admin access, moderation no-read | Chat |
| SR-022 | Chat spam/misuse | community | 3 | 2 | MEDIUM (6) | rate limits (60/min), moderation workload, report/block | Community |
| SR-023 | Log/session token in logs (password/tokens/cards) | credentials | 3 | 4 | HIGH (12) | log scrubbing, no secrets in logs, error handler strips sensitive fields | Platform |
| SR-024 | Audit log tampering | accountability | 2 | 5 | HIGH (10) | append-only (DB constraint + READ ONLY perms), no update/delete path | DB |
| SR-025 | Audit/instrumentation gaps (logging failures) | all | 3 | 3 | MEDIUM (9) | BR-012 mandatory events, security_events telemetry, alerting thresholds | Platform |
| SR-026 | Rate-limit bypass / API abuse | all APIs | 2 | 4 | MEDIUM (8) | throttle plugin + Redis, per-user/IP keys, 429 with Retry-After, WAF at edge | Platform |
| SR-027 | Account enumeration | accounts | 2 | 3 | LOW (6) | generic login/reset responses ("always 202"), timing-safe messages | Platform |
| SR-028 | Session fixation / highjack | sessions | 2 | 4 | MEDIUM (8) | rotate tokens on logout/MFA, refresh rotation, denylist, user-agent check (optional) | Platform |
| SR-029 | Insecure CORS/headers (prod) | web/API | 2 | 3 | MEDIUM (6) | restricted CORS origins (no wildcard in prod), HTTPS-only, security headers (CSP, HSTS, frame, nosniff, referrer) | Admin/Web |
| SR-030 | Data at rest exposure (DB/backup) | all PHI | 2 | 5 | HIGH (10) | disk encryption (LUKS/EBS), encrypted backups, restricted DB network, least-privilege DB role | DB/Infra |
| SR-031 | Backup loss / RPO miss | availability | 2 | 4 | MEDIUM (8) | automated pg_dump/restore tests, off-site copy, encryption; RPO ≤24h (snapshot), ≤1h PITR (target) | Infra |
| SR-032 | Insider export of PHI | records | 2 | 4 | MEDIUM (8) | export permission gating, scope preview, per-export audit, anomaly detection, no bulk PHI export UI | Admin |
| SR-033 | Third-party payment/provider compromise | payments, SMS, Firebase | 2 | 4 | MEDIUM (8) | minimal data to providers, provider docs/AUP, secrets isolated, egress controls, fallback flows | Platform |
| SR-034 | Firebase/SMS secret abuse | notifications | 2 | 3 | LOW (6) | tokenized credentials, project allowlists, key rotation | Platform |
| SR-035 | SSRF via payment URLs | infra | 2 | 4 | MEDIUM (8) | URL allowlist/validation, no user-supplied URLs into server fetch, egress firewalling | Payments |
| SR-036 | DoS on emergency endpoints | availability | 3 | 4 | HIGH (12) | rate limits + burst caps (2/10min), priority gateway, monitoring | Platform |
| SR-037 | Compromised admin account | everything | 2 | 5 | HIGH (10) | mandatory MFA, short idle timeout, re-auth on privileged ops, IP/device monitoring, alert on anomalies, incident playbook | Admin |
| SR-038 | Privileged action abuse (refund, verify, role change) | admin ops | 2 | 4 | MEDIUM (8) | required permission + confirmation + audit + co-sign thresholds (3.7 AD-A-4/11), re-auth on high risk | Admin |
| SR-039 | Caregiver access misuse | caregiver scopes | 2 | 4 | MEDIUM (8) | relationship + consent scope + duration, removal, expiry, audit; role grants nothing alone | Backend |
| SR-040 | Medical export abuse | PHI export | 2 | 4 | MEDIUM (8) | C4 reason-locked download, scope preview, per-export audit, no bulk | Admin |
| SR-041 | Weak password policy | accounts | 3 | 4 | HIGH (12) | Django validators + policy (min 10, common-list check), MFA, breach scan (future) | Platform |
| SR-042 | Session replay after logout | sessions | 2 | 3 | LOW (6) | refresh denylist on logout, access short-lived, kill sessions on password change | Platform |
| SR-043 | Mobile device loss/theft | mobile tokens | 3 | 4 | HIGH (12) | secure storage (flutter_secure_storage), app lock/biometric (optional), remote logout, no PHI cache | Mobile |
| SR-044 | Mobile data exfiltration (clipboard, screenshots, logs) | PHI on device | 2 | 3 | LOW (6) | no sensitive clipboard, FLAG_SECURE on medical screens, log scrub, screenshots disabled | Mobile |
| SR-045 | Deep-link hijack (admin/mobile) | sessions | 2 | 3 | MEDIUM (6) | app-link validation (Android App Links/iOS Universal Links), no token in query by default | Mobile |
| SR-046 | TOTP secret exfiltration | MFA | 2 | 4 | MEDIUM (8) | secret sealed at rest, shown once, never in logs, QR re-set flows audited | Platform |
| SR-047 | Enumeration via error differences | data | 2 | 2 | LOW (4) | consistent error codes/messages server-side, generic auth errors | Backend |
| SR-048 | Legal/regulatory non-compliance (retention) | records | 2 | 4 | MEDIUM (8) | documented retention/archival/anonymization policy (SD-13) | Platform |

Priority ordering (risk rank): SR-004/005/009/001/002 first, then SR-006/008/
012/015/020/021/023/024/030/036/037/041/043, then the MEDIUM/LOW set.

---

## 3. Accepted Risks (documented)

| ID | Rationale | Compensation |
|---|---|---|
| SR-027 | generic responses add minor UX cost | uniform messages, logging at security_events |
| SR-033/SR-034 | third-party operational risk accepted by policy | provider governance, secrets isolation |
| SR-044 | residual low-impact mobile risk | platform secure-storage + FLAG_SECURE |

---

## 4. Control Gaps (design-time → Stage 4/5)

| Gap | Register ref | Handling |
|---|---|---|
| Webhook signature schemes differ per provider (MPesa/Selcom/ClickPesa/cards) | SR-009/010 | provider adapter profile; HMAC-verify where offered; treasury idempotency fallback (`provider_ref` cross-check) |
| Virus scanning at upload time has no vendor selected | SR-019 | RFC: ClamAV scan path (Stage 4); until then allowlist-only + unsigned quarantine dir |
| Anomaly detection engine (logins/PHI/refunds) not in API | SR-025/032/037 | thresholds implemented in monitoring layer; alerts; `security_events` ingest |
| HSM/KMS provider selection | SR-030 | env-var secrets in Stage 4 dev; platform KMS (AWS/GCP) or HashiCorp Vault at 3.9 deployment decision |
| Audit log DB-level immutability (trigger) hardening | SR-024 | Django ORM append-only + DB role `NOUPDATE/DELETE` on `audit_logs` in production grants |

All are documented, none silently invented; each maps to Stage 4/5 work.

---

END — feeds `security-design.md` §3–4 and `security-review.md` risk sections.