# 3.8 Security Review

> Self-review of the Stage 3.8 Security Design deliverables:
> `security-design.md`, `security-risk-register.md`,
> `data-classification-security.md`, `security-control-matrix.md`,
> `security-api-traceability.md`, `security-database-traceability.md`,
> `security-implementation-checklist.md`. Reference gates: 3.5 API design,
> 3.4 DB design, 3.3 roles/permissions, 3.6 mobile, 3.7 admin, requirements
> (NFR-SEC-001..005, BR-001..012, 2.9).

---

## 1. Executive Summary

Security architecture for Sickler's Warriors is defined end-to-end (auth,
MFA, authorization, consent, emergency, medical/PHI, donor privacy, payments
+ webhooks, chat, notifications, admin, database, encryption, key management,
audit, monitoring, rate limiting, backup/DR, retention, incident response,
OWASP review, third parties). Designed **only** — no implementation. Backend
apps remain scaffolds; `CORS_ALLOW_ALL_ORIGINS`, `DEBUG=True` and the
insecure default `SECRET_KEY` in `settings.py` are recorded as Stage-4 fixes,
not introduced.

**No CRITICAL unmitigated risk.** One high-surfacing risk family is
credential/session compromise — fully mitigated by design (hashing + MFA +
short TTL + rotation + denylist + lockout). Payment risks mitigated via
backend-verified webhooks with HMAC + replay defense + idempotency (BR-008).

## 2. Critical Assets

- Patient medical records & PHI (Highly Sensitive).
- Authentication credentials + MFA seeds.
- Blood donor PII (BR-006).
- Emergency case data.
- Payment transactions & provider refs.
- Audit/legal records (integrity).
- Admin accounts & privileges.

## 3. Major Threats

External (credential/account takeover, API abuse, injection, malicious
uploads, webhook forgery), malicious users (fake blood/campaigns, abuse,
privacy violations), compromised accounts, insiders (excessive privilege,
medical data access, emergency/financial manipulation), third parties
(payment, Firebase, SMS/email, cloud). Full: `security-risk-register.md`
(48 risks).

## 4. Authentication Assessment

- Hashing Argon2id/PBKDF2; rotation; policy; reset; verification; lockout;
  sessions — complete. Device step-up (SD-5) is a marked add-on (ASG-10).
- **Assessment: PASS (with ASG-10 marked RECOMMENDED/FUTURE).**

## 5. Authorization Assessment

- RBAC + object-level (IDOR) + consent + C4/C17 + masking — complete and
  aligned 1:1 to 3.3. **Assessment: PASS.**

## 6. Medical Data Assessment

- Classification gates, consent lifecycle, emergency bounded access,
  reason-locked admin C4 — complete and auditable. **Assessment: PASS.**

## 7. Payment Assessment

- Provider tokenization (no cards), backend-verified webhooks, HMAC, replay
  defense, idempotency, reconciliation, co-sign refunds — complete (BR-008).
  Webhook nonce registry (ASG-9) marked RECOMMENDED. **Assessment: PASS.**

## 8. Blood/Emergency Assessment

- Donor PII masked (BR-006), region-only matching, verified request flow;
  emergency: 24 h window, justification, audit, anomaly — complete.
  **Assessment: PASS.**

## 9. Mobile Security Assessment

- Secure storage, no PHI cache (v1), FLAG_SECURE, deep-link validation, no
  secrets in binary; E2E chat explicitly **not** claimed (SD-19).
  **Assessment: PASS (E2E flagged FUTURE, honest).**

## 10. Admin Security Assessment

- Mandatory MFA, re-auth, idle timeout, screen-role mapping, C4 reasons —
  complete (3.7-aligned). **Assessment: PASS.**

## 11. API Security Assessment

- AuthN/authZ/validation/rate limits/Pagination/errors/abuse — complete;
  10 API SECURITY GAPs captured (ASG-1..10) and NOT implemented.
  **Assessment: PASS (gaps registered for owner approval).**

## 12. Database Security Assessment

- Least-privilege DML role, no superuser, ssl, restricted net, encrypted
  backups, append-only audit, sealing of MFA — complete. Candidate DB
  changes listed but not applied (CBD-1..7). **Assessment: PASS.**

## 13. File Security Assessment

- Allowlist + magic bytes, size caps, randomized names, signed URLs,
  reviewer-scope doctor docs, retention — complete. ClamAV RFC noted
  (RECOMMENDED). **Assessment: PASS.**

## 14. Privacy Assessment

- Privacy-by-design per feature, G4 no-PHI previews, retention/erasure,
  data-subject rights — complete. **Assessment: PASS.**

## 15. Third-Party Assessment

- Per-provider data/secrets/failure/privacy/fallback mapped (§37).
  **Assessment: PASS.**

## 16. Audit & Monitoring Assessment

- BR-012 event codes, append-only, security_events, thresholds/alerts —
  complete; anomaly engine RFC (SD-18). **Assessment: PASS.**

## 17. Backup/Recovery Assessment

- Encrypted nightly dumps, off-site, quarterly restore, RPO/RTO defined —
  complete. **Assessment: PASS.**

## 18. Critical Security Gaps

| Gap | Status |
|---|---|
| None critical | — (design sets all CRITICAL risks to controlled) |
| ASG-1..10 (missing API capabilities) | registered; amendment to 3.5 for owner approval |
| SD-1/4/9/14/19 | blocking set requires owner sign-off before Stage 4 |

## 19. High-Risk Issues (controlled but to monitor)

| Issue | Control | Residual |
|---|---|---|
| Credential/account takeover | hashing+MFA+TTL+rotation+denylist+lockout | low (device step-up optional) |
| IDOR / cross-patient read | object filters + UUID + consent | low |
| Admin PHI abuse | C4 reason + audit + no bulk | low (insider monitoring SD-18) |
| Payment/webhook fraud | backend verify + HMAC + idempotent | low (provider variance — adapter) |
| PHI leak via notifications | privacy-safe templates + G4 | low |

## 20. Medium-Risk Issues

| Issue | Control | Note |
|---|---|---|
| Rate-limit bypass variance | Redis + WAF | calibrate under load (NFR-PERF) |
| Virus scan not yet shipped | allowlist + quarantine | ClamAV RFC Stage-4 |
| Export misuse | scope-gate + audit | no bulk PHI UI |
| Chat retention vs legal | archive + erasure | legal hold path |

## 21. Low-Risk Issues

| Issue | Control |
|---|---|
| Enumeration timing | generic messages throughout |
| Cookie-JWT overlap | bearer-only SPA; CSRF restricted |
| Push-channel residual | in-app fallback |

## 22. Required Decisions (owner sign-off before Stage 4)

1. Sign-off SD-1 (Argon2id) / SD-4 (TTL) / SD-9 (CORS) / SD-14 (secrets) / SD-19 (no E2E).
2. Approve ASG-1..10 as 3.5 amendments (or reject per-item).
3. Approve CBD-1..7 as 3.4 amendments (or defer).
4. Confirm MFA mandatory scope for all admins (3.7) plus step-up set (SD-5).
5. Accept documented residual risks (register §3).

## 23. Stage 4 Security Requirements (contract)

- [ ] Implement auth/MFA/password/session per `security-design.md` §5/6/31.
- [ ] Implement permission classes + object ACL + consent resolver (ASG-aware).
- [ ] Implement masked serializers + data-classification gating.
- [ ] Implement file allowlist + signed-URL storage; doctor-doc scoping.
- [ ] Implement payments + webhooks (HMAC/nonce/idempotency/reconciliation).
- [ ] Configure DB roles/grants/append-only; sealed MFA column.
- [ ] Apply `security-implementation-checklist.md` REQUIRED items; sign SDs.

## 24. Stage 5 Security Testing Requirements

- [ ] Auth: full suite (§35 security-design).
- [ ] Authorization: IDOR, role, C17, C4, consent expiry.
- [ ] API: injection, malformed, oversized, rate-limit 429, token abuse.
- [ ] Files: malicious uploads, invalid types, oversized, traversal, URL leaks.
- [ ] Payments: duplicate/forged webhook/replay/invalid status/idempotency.
- [ ] Privacy: cross-patient, donor mask, emergency minimal, export, previews.

---

## 25. Requirements Traceability §48

| Requirement | Security Requirement | Component | Role | API | Database | Test | Coverage |
|---|---|---|---|---|---|---|---|
| NFR-SEC-001 | TLS everywhere | infra/mobile/admin | all | all HTTPS | transport | TLS checks | Fully covered |
| NFR-SEC-002 | Password hashing | backend | all | `/auth/*` | users | auth suite | Fully covered |
| NFR-SEC-003 | Authorization + consent | DRF/ACL/consent | per 3.3 | permissions | records/consents | IDOR suite | Fully covered |
| NFR-SEC-004 | Audit | audit + telemetry | all | audit endpoints | audit_logs/sec_events | coverage | Fully covered |
| NFR-SEC-005 | OWASP protection | all layers | all | all | all | OWASP suite | Fully covered |
| 2.9 access-control model | Role+permission+consent+context | backend | all | per matrix | consents | consent suite | Fully covered |
| BR-002/003/004 | Private + consent medical | records | owner/grantee/C4 | records/consents | records/links | IDOR/consent | Fully covered |
| BR-006 | Donor PII protected | donors | masked roles | donors | donors | masking | Fully covered |
| BR-007 | Campaign verified | campaigns | VO/ADM/SUP | campaigns/verify | campaigns | workflow | Fully covered |
| BR-008 | Backend payment verify | payments/webhooks | backend service | initiate/webhook | payments | webhook suite | Fully covered |
| BR-009 | Emergency spam protection | emergency | owner/C7/C4 | emergency | emergency | rate-limit | Fully covered |
| BR-012 | Audit critical ops | audit | all | audit endpoints | audit_logs | coverage | Fully covered |
| 3.7 admin MFA/timeout | Admin security | admin web | admin roles | auth/mfa | users/mfa | admin suite | Partially covered (ASG-10 step-up FUTURE) |
| 3.6 G4 privacy | Notification preview safety | notifications | any | broadcasts | notification | preview leaks | Fully covered |
| 3.5 rate-limits | DoS control | API | all | throttles | Redis | 429 tests | Fully covered (calibration pending) |
| E2E chat (not claimed) | acceptable security level | chat | participants | C13 | messages | participant ACL | Documented (FUTURE E2E) — acceptable |

**Coverage**: 14/14 Fully covered · 1 Partial (admin step-up ASG-10, FUTURE) ·
0 Missing · 0 Unresolved (all gaps registered ASG-1..10 / CBD-1..7).

---

## 26. Stage 3.8 Quality Gate ($50)

| Check | Status |
|---|---|
| Authentication designed | ✓ §5/§6/§31 |
| Authorization aligned 3.3 | ✓ §7 + matrices |
| Medical data protected | ✓ §8 + classification |
| Consent model defined | ✓ §9 |
| Emergency access controlled | ✓ §10 |
| Doctor verification protected | ✓ §19 + §28 |
| Blood donor privacy protected | ✓ §20 |
| Payment security defined | ✓ §21/§22 |
| Webhook security defined | ✓ §22 |
| API security defined | ✓ §11 |
| Database security defined | ✓ §16 + traceability |
| File upload security defined | ✓ §19 |
| Mobile security defined | ✓ §14 |
| Admin security defined | ✓ §25 |
| Encryption defined | ✓ §17 |
| Key management defined | ✓ §18 |
| Audit logging defined | ✓ §27 |
| Monitoring defined | ✓ §28 |
| Rate limiting defined | ✓ §29 |
| Backup security defined | ✓ §32 |
| Data retention defined | ✓ §33 |
| Incident response defined | ✓ §38 |
| Security testing requirements defined | ✓ §35 |
| OWASP-aligned review completed | ✓ §36 |
| Requirements traceability completed | ✓ §25 above |

All 25 **complete**.

---

## 27. Stage 3.8 Decision (§51)

> **`PASS WITH MINOR REVISIONS`**

**Explanation**: No blocking security gaps. All CRITICAL/HIGH risks are
mitigated by design; the 10 API Security Gaps (ASG-1..10) and candidate DB
changes (CBD-1..7) are explicitly registered and require owner approval as 3.5
/ 3.4 amendments — they do not block the design gate. Minor revisions are the
owner sign-off of the blocking SD set and the calibration/scan add-ons
(SD-18 fraud engine, ClamAV, load-calibrated rate limits) tracked for Stage 4.
Backend scaffolds are unchanged; nothing was implemented or migrated.

**Stage 3.8 CLOSES — `PASS WITH MINOR REVISIONS`.**

---

STOP — awaiting owner approval. Do NOT proceed to 3.9 Deployment Design or any
implementation until the project owner explicitly approves this stage and the
SD blocking decisions.