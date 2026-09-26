# 3.8 Security Control Matrix

> Stage 3.8 — Security Design. Maps each security control across the five
> layers: **Mobile, API, Database, Admin, Third-Party**. States per cell:
> `✓` designed · `~` partial (see note) · `—` not applicable / deferred ·
> `RFC` under review. Source: `security-design.md`, `security-risk-register.md`.

Legend notes appear at row level for `~`.

---

## 1. Control Matrix

| Security Control | Mobile | API | Database | Admin | Third Party |
| ---------------- | ------ | --- | -------- | ----- | ----------- |
| **Authentication** | ✓ login+MFA(client) | ✓ JWT access/refresh, rotate | ✓ hashed creds (Argon2id/PBKDF2) | ✓ mandatory MFA + re-auth | ✓ provider creds isolated |
| **Authorization** | ✓ consent-aware client (G-principles) | ✓ RBAC 3.3 + object ACL + C4/C17 | ✓ least-privilege roles (no superuser) | ✓ screen-role matrix + 403 | — (data limited) |
| **Consent gating** | ✓ surfaces consent (BR-004) | ✓ consent resolver in object filters | ✓ `consents`/`medical_record_links` | ✓ C4 reason gates (AD-A-9) | — |
| **Encryption** | ✓ TLS + secure storage; no PHI cache | ✓ TLS; field controls | ✓ TLS/SSL, disk+LUKS/EBS, sealed mfa | ✓ HTTPS-only + headers | ✓ TLS to providers; token-only cards |
| **Pwd hashing** | — (server-side) | ✓ server-side Argon2id/PBKDF2 | ✓ hashed column `password_hash` | ✓ admin min-12 policy | — |
| **MFA** | ✓ TOTP client + recovery | ✓ `/auth/mfa/*`, step-up | ✓ `mfa_secret_encrypted` sealed | ✓ required, re-auth ops | — |
| **Rate limiting** | ✓ backoff UX | ✓ Redis throttles (3.5 §29) | ✓ (within) | ✓ UI retry 429 | ✓ provider caps |
| **Input validation** | ✓ client pre-check (non-trust) | ✓ DRF serializers + OWASP | ✓ parameterized ORM, constraints | ✓ typed confirmations | — |
| **Logging/Audit** | ✓ audit client events (deferred) | ✓ BR-012 event codes (§42) | ✓ append-only `audit_logs` anti-DEL | ✓ admin action audit + reasons | ✓ provider/IP webhook logs |
| **Monitoring** | ~ device/location flags (SD-5, partial) | ✓ security_events + thresholds | ✓ pg log review (ops) | ✓ security center + alerts (3.7) | ✓ webhook/IP anomaly |
| **Backups** | — | — | ✓ encrypted pg_dump + off-site + restore test | ✓ export trail | ✓ provider receipts |
| **File security** | ~ upload via signed URL | ✓ allowlist/MIME/size/signed URL | ✓ encrypted media storage | ✓ reviewer-only access (C6) | ✓ CDN/storage IAM |
| **Privacy** | ✓ G4: no PHI previews/screenshots | ✓ masked outputs (BR-006) | ✓ classification (37) + retention | ✓ least-privilege, no bulk export | ✓ minimal data to providers |
| **Session mgmt** | ✓ secure storage + re-auth | ✓ rotation + denylist + revoke | ✓ token_denylist table | ✓ idle 15 min, forced logout | — |
| **Incident response** | ✓ user-facing (logout/revoke) | ✓ IR playbooks (design) | ✓ restore runbook | ✓ security center alerts | ✓ provider incident channels |
| **Key management** | — (no app secrets) | ✓ env-secrets Stage 4, KMS prod (SD-14) | ✓ sealed columns + rotation | ✓ setting save re-auth | ✓ segmented provider secrets |
| **SSRF protection** | — | ✓ egress allowlist + URL validation | — | — | ✓ allowlisted endpoints |

---

## 2. Notes on `~` / constrained cells

- **Mobile monitoring (partial)**: impossible-travel/new-device heuristics run
  server-side; the mobile device participates only via device metadata — no
  device-agent control shipped in v1 (SD-5).
- **Uploads (mobile partial)**: signed upload URLs granted by the API; the
  mobile client does no independent file-type trust (server recomputes).
- **Third-party providers**: all secrets segmented server-side; provider
  fallback behaviors documented in `security-design.md` §37.

---

## 3. Requirement → Control Mapping

| Requirement | Control(s) | Layer |
|---|---|---|
| NFR-SEC-001 (TLS) | Encryption row | API/Mobile/Admin/DB |
| NFR-SEC-002 (pwd) | Password hashing row | API/DB |
| NFR-SEC-003 (authz) | Authorization + consent | all |
| NFR-SEC-004 (audit) | Logging/Audit row | API/Admin |
| NFR-SEC-005 (OWASP) | Input validation + bolts | API/Web |
| BR-006 (donor PII) | Privacy + authorization | API/DB/Admin |
| BR-008 (payment verify) | AuthN + webhooks + logging | API/payments |
| BR-009 (emergency) | Rate limiting + emergency gates | API |
| 3.8 objectives | all rows | all |

---

## 4. Residual (marked) Controls for Stage 4/5

| Control | Status | Owner stage |
|---|---|---|
| Virus scan at upload (ClamAV) | RFC | Stage 4 add-on (register §4) |
| Fraud/anomaly engine thresholds | RFC | Stage 4 (SD-18) |
| Mobile device-agent monitoring | FUTURE | v2 |
| E2E sealed chat | FUTURE | v2 (SD-19) |
| HSM/KMS selection | 3.9 deployment decision | 3.9 |
| DB immutable-audit trigger hardening | Stage 4 | Stage 4 |

---

END — cross-checked with `security-design.md` §38 and `security-review.md`.