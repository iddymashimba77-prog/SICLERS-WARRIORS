# 3.8 Security API Traceability

> Maps every security-relevant API capability to its authentication,
> permission, sensitive data, rate limit, audit and validation contract.
> Endpoints taken from the approved 3.5 API design (`api-endpoint-matrix.md`,
> `api-design.md`). Where a security control requires an API capability 3.5
> does not yet expose, it is marked **`API SECURITY GAP`** — never silently
> invented.

Columns: `AuthN` (P public, T token, R reset/MFA token) · `Permission` (3.3
code) · `Sensitive` (Highest data class in response) · `Rate limit` (3.5 §29 /
§29 of design) · `Audit` (BR-012 event, §42) · `Validation`.

---

## 1. Authentication & MFA Endpoints

| Endpoint | AuthN | Permission | Sensitive | Rate limit | Audit | Validation |
| -------- | ----- | ---------- | --------- | ----- | ----- | ---------- |
| `POST /auth/register` | P | — | none | 3/h/IP | reg event | role_code whitelist; serializer; CAPTCHA (RFC) |
| `POST /auth/login` | P | — | none | 5/min | `auth.login`/`auth.login_failed` | generic error (no enumeration) |
| `POST /auth/refresh` | R | — | token | 10/min | rotation reuse → alert | rotation check; reuse attack detection |
| `POST /auth/logout` | T | `auth.logout` | none | 10/min | `auth.logout` | denylist refresh |
| `POST /auth/password-reset/request` | P | — | none | 3/h/IP+email | reset req | 202 always |
| `POST /auth/password-reset/confirm` | R(reset) | — | none | 3/h | `auth.password_reset` | token single-use, expiry |
| `POST /auth/password/change` | T | `auth.password_reset` | none | 10/min | `auth.password_change` | current pwd required |
| `POST /auth/verify/email` | R | — | none | 5/min | verify | single-use token |
| `POST /auth/verify/phone` | R | — | none | 5/min | verify | OTP single-use, TTL |
| `POST /auth/mfa/setup` | T | `auth.mfa_manage` | sealed seed | 5/min | `auth.mfa.enable` | secret shown once |
| `POST /auth/mfa/enable` / `disable` | T | `auth.mfa_manage` | none | 5/min | mfa events | re-auth on disable |
| `GET /auth/sessions` | T | `auth.profile_view` | session list | 10/min | — | self only |
| `DELETE /auth/sessions/{id}` | T | `auth.profile_view` | none | 10/min | `auth.session_revoke` | self only |
| `POST /auth/mfa/recover` | R | — | recovery codes | 3/h | recovery | single-use hashed codes (SD-6) |
| `POST /auth/mfa/reauth` | T | — | TOTP proof | 5/min | reauth | short TTL; step-up gate |

---

## 2. Users / Roles / Admin

| Endpoint | AuthN | Permission | Sensitive | Rate limit | Audit | Validation |
|---|---|---|---|---|---|---|
| `GET /admin/users` | T | `users.view` (C6) | masked contact | 30/min | — | pagination ≤100 |
| `GET /admin/users/{uid}` | T | `users.view` | masked | 30/min | view | UUID |
| `POST /admin/users/{uid}/activate\|deactivate\|suspend` | T | `users.update`/`deactivate` | none | 60/h | action | state machine |
| `POST /admin/users/{uid}/verify` | T | `users.verify` (C6) | verifying docs | 60/h | decision | reason required (reject) |
| `POST /admin/users/{uid}/roles` | T | `users.role_assign` (**C17**) | role graph | 20/h | `roles.role_assign` | never self-assign; SUP only |

---

## 3. Medical / Consents

| Endpoint | AuthN | Permission | Sensitive | Rate limit | Audit | Validation |
|---|---|---|---|---|---|---|
| `GET /patients/me/records` | T | `medical_records.view` (owner C15) | HS PHI | 60/min | `medical_records.view` | owner-scope filter |
| `POST /patients/me/records` (own) | T | `medical_records.create` (C15) | HS PHI | 30/min | modify | field whitelist; no mass-assign |
| `POST /consents` | T | `consents.grant` (owner) | consent graph | 30/min | `consents.grant` | grantee/scope/duration validated |
| `DELETE /consents/{id}` | T | `consents.revoke` | consent graph | 30/min | `consents.revoke` | immediate effect |
| `GET /consents` (own) | T | `consents.view` (owner) | consent graph | 60/min | view | owner scope |
| Admin `GET /patients/{pid}` (C4) | T | `patients.view` C4 | HS PHI | 20/h | `access_open` + reason | reason-locked gate; no bulk |
| `GET /medical_records/{mid}` (grantee) | T | consent-resolved `view` | HS PHI | 30/min | `medical_records.view` | grant-check in query |
| `GET /medical_records/{mid}/download` | T | `medical_records.download` C4/owner | HS file | 10/h | download | signed URL issuance |
| `PATCH /medications/{id}` `instructions` | T | own (`medications.update`) | HS PHI | 30/min | modify | ≤2000 chars, plain text only (FR-MED-007) |

---

## 4. Doctor / Facility / Blood

| Endpoint | AuthN | Permission | Sensitive | Rate limit | Audit | Validation |
|---|---|---|---|---|---|---|
| `GET /admin/doctors/verification-queue` | T | `doctors.verify` C6 | verify docs meta | 30/min | — | queue scope |
| `POST /admin/doctors/{uid}/verify` | T | `doctors.verify` | license docs | 60/h | decision | reason on reject |
| `POST /admin/doctors/{uid}/suspend` | T | `doctors.verify`/`update` | SS | 60/h | suspend | state machine |
| `GET /admin/facilities` | T | `facilities.view`/`verify` | internal ops | 60/min | — | — |
| `POST /admin/facilities/{fid}/verify` | T | `facilities.verify` | docs | 60/h | decision | verify-scope (C6) |
| `GET /admin/blood/requests` | T | `blood_requests.view` (C6/VO scope) | SS (no donor PII) | 60/min | — | BR-006 mask |
| `POST /admin/blood/verification-queue/:verify` | T | `blood_requests.verify` | SS | 60/h | `blood.verify` | reason |
| `POST /admin/blood/matches/run` | T | `blood_matches.run` (C6/7) | matched pairs (C9) | 10/h | run | C9 scope; no contact leak |
| `GET /doctors` (directory) | T | `doctors.view` | public subset | 60/min | — | server filters to APPROVED + active; public projection omits contact data and licence numbers |
| `GET /doctors/{uid}/verification-history` | T | self **or** `doctors.verify` | licence meta | 30/min | view | 404 (not 403) for anyone else, so the route never confirms an application exists |
| `GET /admin/doctors/verification-history` | T | `doctors.verify` C6 | licence meta | 30/min | view | registry-wide trail |
| `POST /admin/doctors/{uid}/reinstate` | T | `doctors.verify` | SS | 60/h | reinstate | reason required; appends a decision |
| `GET /blood/requests/{uid}/decisions` | T | owner/admin/eligible donor | SS + decider's reason | 60/min | view | reached through the request's own object gate; reason shown verbatim so it can be contested |

---

## 5. Emergency

| Endpoint | AuthN | Permission | Sensitive | Rate limit | Audit | Validation |
|---|---|---|---|---|---|---|
| `POST /emergency/requests` | T | create (owner) | case min | 5/day; 2/10min | create | rate-limited (BR-009) |
| `GET /emergency/requests` (own) | T | owner view | case min | 60/min | — | owner scope |
| `GET /admin/emergency/{caseId}` | T | `emergency_requests.view` C4 | HS case | 30/min | `access_open` | grant-window check (24h) |
| `POST /admin/emergency/{caseId}/respond\|escalate\|resolve` | T | `manage`, C10 bound | operations | 30/h | action | reason + confirm; expiry |
| `POST /admin/emergency/{caseId}/grant-access` | T | C10/SUP | grant | 10/h | `emergency.access_grant` | justification required; auto-expire 24h |

---

## 6. Payments / Webhooks

| Endpoint | AuthN | Permission | Sensitive | Rate limit | Audit | Validation |
|---|---|---|---|---|---|---|
| `POST /donations/initiate` | T | `donations.create` | provider ref | 10/h; 1/campaign | initiate | idempotency key; amount caps |
| `POST /payments/{provider}/verify` (admin) | T | `payments.verify` | provider payload | 20/h | reconcile | provider adapter |
| `POST /payments/refund` | T | `payments.refund` | redacted | 10/h | `payments.refund` | co-sign threshold; reason |
| `POST /api/v1/webhooks/payments/{provider}` | HMAC (no session) | provider adapter | provider payload | IP allowlist + sig | `payments.webhook_received` | sig + nonce + ttl ±5min; idempotency |

---

## 7. Community / Education / Notifications / Files

| Endpoint | AuthN | Permission | Sensitive | Rate limit | Audit | Validation |
|---|---|---|---|---|---|---|
| `POST /community/posts` | T | community post | Public (auth) | 30/min | — | sanitized HTML |
| `POST /community/reports` | T | report create | reported content | 30/min | report | spoiler metadata only |
| `POST /admin/community/reports/{rid}/resolve` | T | `community.moderate` | reports | 60/h | `community.moderate` | reason; hide-first |
| `GET/POST /education/content` | T | `education.review`/create | drafts | 30/min | publish | category/state |
| `POST /admin/education/content/{id}/review\|publish` | T | `education.review` | draft | 60/h | decision | publish after review |
| `POST/DELETE /education/content/{id}/document` | T | `education.publish` (C12) | own, non-PUBLISHED article | 30/min | document_upload/remove | MIME+magic+size+extension match; no PUBLISHED edit |
| `POST/DELETE /admin/education/content/{id}/document` | T | `education.review` | non-PUBLISHED article | 30/min | document_upload/remove | same validation; metadata-only audit |
| `GET/POST /medical-records/` | T | `medical_records.view` / `.create` | O/C | own, or C15 clinical writer | 30/min | view/create | list is metadata-only; read set is the gate |
| `GET/PATCH/DELETE /medical-records/{id}/` | T | `view` / `update` / `delete` | O/C | own, C15, or C4 with reason | 30/min | view/update/delete | soft delete; foreign uid → 404 |
| `GET/POST /medical-records/{id}/files/` | T | `view` / `upload` | O/C | owner or C15 | 20/min | upload | PDF/JPEG/PNG ≤15MB; magic + extension; SHA-256 |
| `GET /medical-records/files/{fid}/download` | T | `medical_records.download` | O/C | chart read gate + download | global | download | no public URL exists for clinical bytes |
| `POST /medical-records/{id}/share/` | T | `view` | O | patient only | 20/min | share | narrowest grant: 1 record, 1 user, optional expiry |
| `GET /medical-records/{id}/history/` | T | `medical_records.view` | O/C | read set | global | — | append-only; non-PHI details only |
| `GET /admin/*/medical-records/*` (C4) | T | `medical_records.view` | — | requires `X-Oversight-Reason` ≥10 chars | global | view | reason stored; a plain GET is 403 |
| `GET /patients/me/medical-records/` | T | `medical_records.view` | O | own chart only | 30/min | view | `me` alias resolves to the caller; never another patient |
| `GET /blood/requests/{id}/decisions` | T | owner / admin / eligible donor (C8) | decision trail | global | — | append-only; ineligible donor gets 404, not 403 |
| `POST /admin/doctors/{uid}/reinstate` | T | `doctors.verify` (C6) | professional standing | 60/h | `doctors.verify` | reason required; suspended status required |
| `GET /doctors/{uid}/verification-history` | T | self, else `doctors.verify` | licence history | global | — | append-only; 404 for anyone else (no existence leak) |
| `GET /admin/doctors/verification-history` | T | `doctors.verify` (C6) | licence history | 60/min | — | `?decision=` must be a known code; newest 200 |
| `POST /chat/conversations` (PSY/SOC) | T | `chat.start` | care conversation | 20/min | conversations.create | partner must be APPROVED in the registry; role alone is not enough |
| `POST /medical-records/` (PSY) | T | `medical_records.create` | O/C | C15: verified + live consent scope | 30/min | create | attributed to the psychologist; no prescribing rights |
| `POST /medical-records/` (SOC) | T | — | O/C | denied | — | — | consent grants access, never authorship |
| `POST /doctors/me/verification` (PSY/SOC) | T | `doctors.self_manage` | professional identity | 10/day | `doctors.verify` trail | claimed `professional_type` must match the account role |
| `POST /notifications/broadcast` | T | `notifications.broadcast` | template (PHI-stripped) | 5/h | send | privacy-safe preview; no PHI |
| `POST /files/upload` | T | per-doc permission | file | daily cap | `files.upload` | MIME+magic+size+allowlist |
| `GET /files/{uid}/download` | T | per-doc permission | file (signed URL) | 30/min | `files.download` | signed URL, short TTL |
| `GET /admin/audit-logs` | T | `audit_logs.view` (C6 own) | audit meta (no PHI) | 60/min | — | append-only read |
| `GET /admin/analytics` | T | `analytics.view` | aggregates | 60/min | view | aggregate-only; no raw PHI |
| `POST /admin/exports` | T | `analytics.export`/`audit_logs.export` | scope preview | 10/h | `exports.create` | scope-gate; no bulk PHI |
| `GET /admin/search?q=` | T | per-index view | — | 30/min | — | authorized indexes only; no PHI previews |

---

## 8. API SECURITY GAP Register

Missing capabilities surfaced by security analysis (not invented; each is a
proposed 3.5 amendment for owner approval before Stage 4):

| GAP id | Missing capability | Needed for | Security import |
|---|---|---|---|
| ASG-1 | `POST /auth/mfa/recover` | MFA recovery (§30/SD-6) | high — recovery secure flow |
| ASG-2 | `POST /auth/mfa/reauth` (step-up) | privileged ops re-auth (§28) | high |
| ASG-3 | `DELETE /auth/mfa` codes / recovery mgmt | recovery code refresh | medium |
| ASG-4 | `GET /admin/security/events` (auth telemetry) | monitoring (§28) | medium |
| ASG-5 | `POST /admin/emergency/{caseId}/grant-access` (window mgmt) | bounded emergency grant (§9/§10) | high |
| ASG-6 | `POST /files/upload` signed-initiate + `POST /files/upload/complete` | secure multi-part/malware-gated upload | high |
| ASG-7 | `POST /admin/exports` (request+tokenized download) | safe exports (SD-14) | medium |
| ASG-8 | Notification template secret-places sanitized endpoint | safe push previews (G4) | medium |
| ASG-9 | Webhook replay-nonce registry (per provider) | replay defense (§22) | high |
| ASG-10 | `POST /auth/device-flag` (opt-in device metadata) | new-device step-up (SD-5) | medium |

Each ASG is a candidate 3.5 amendment; **no endpoint is treated as existing**.
This register is carried into `security-review.md` as a required decision.

---

END — validation of gaps + decisions in `security-review.md`.