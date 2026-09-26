# 3.8 Security Database Traceability

> Maps security requirements to the 3.4-approved tables/entities, their
> sensitive fields, access rules, encryption, and audit obligations. Any DB
> change implied by security is listed in §5 as a **candidate** (for owner
> approval) — **nothing is implemented now** (design stage, no migrations).

Legend: Access = 3.3 roles/conditions · Enc = encryption applied · Audit =
event on change/read.

---

## 1. Identity & Access (accounts)

| Table | Sensitive fields | Access rules | Encryption at rest | Audit |
|---|---|---|---|---|
| `users` | `password_hash`, `mfa_enabled`, `phone`, `email` | owner; SUP/ADM masked (C6); backend hasher | `password_hash` + MFA sealed; contact at-rest encrypted media | login/change |
| `roles` / `permissions` / `role_permissions` | — | SUP (C17) manage | — | role assign/perm change |
| `user_roles` / `user_permissions` | grants graph | SUP (C17) | — | `roles.role_assign` |
| `verification_documents` | license images (blobs refs) | owner; VO/ADM/SUP verify scope (C6) | encrypted file media + signed URL | upload/verify/decision |
| `token_denylist` | refresh token hashes | backend only | hashed tokens | revoke/logout |
| `security_events` | auth telemetry (IP, device, actor) | SUP/ADM auth center; append-only | at-rest (media) | n/a (source) |
| `mfa_secret_encrypted` (in users or mfa table) | TOTP seed | backend only; never API | **AES-GCM sealed** (SD-16) | setup/enable/disable |

---

## 2. Patients / Medical / Consent

| Table | Sensitive fields | Access rules | Encryption at rest | Audit |
|---|---|---|---|---|
| `patients` (profile) | demographics, emergency contact | owner; clinical (C14); SUP/ADM C4 | at-rest | record view |
| `medical_records` | notes, symptoms, history, files refs | owner; consent grantee; clinical C7/C14; C4 | at-rest + sealed media | `medical_records.view`/`modify` |
| `clinical_encounters` | treatment data | clinical author (C15/16) | at-rest | modify |
| `medical_record_links` | grant mapping | consent-resolved | — | grant/revoke |
| `consents` | grantee, scope, duration | owner + grantee + C4 | at-rest | `consents.grant`/`revoke` |
| `medications` / `appointments` | meds schedule, appt info | owner/clinical/C7 | at-rest | create/update |

---

## 3. Caregiver / Blood

| Table | Sensitive fields | Access rules | Encryption at rest | Audit |
|---|---|---|---|---|
| `caregiver_relationships` | relationship scope | owner + caregiver (consent) + C4 | at-rest | grant/remove |
| `blood_donors` | **phone/address**, group, region | masked (BR-006); match scope C9 | at-rest; exact loc sealed until consent | verify/match |
| `blood_requests` | need/units, no donor PII | owner; C6/C7 verify | at-rest | verify/approve |
| `blood_matches` | pair links (C9) | match scope only | at-rest | run |

---

## 4. Emergency

| Table | Sensitive fields | Access rules | Encryption at rest | Audit |
|---|---|---|---|---|
| `emergency_requests` | identity, blood group, hospital, caregiver contact, status | owner; C7 hospital; SUP/ADM C4; grant | at-rest | grant/read/resolve |
| `emergency_access_grants` | grantee, window, justification | SUP/ADM (C10); grant creator | at-rest | **grant/revoke/expiry** |
| emergency timeline | statuses/responses | same scope | at-rest | actions |

---

## 5. Donations / Payments

| Table | Sensitive fields | Access rules | Encryption at rest | Audit |
|---|---|---|---|---|
| `donations` | amount, refs | owner receipts; SUP/ADM masked | at-rest | initiate/confirm |
| `payments` | `provider_ref`, payload (no cards) | finance/SUP/ADM (masked) | at-rest; payloads **sealed** | webhook/refund/reconcile |
| `transactions` / reconciliation snapshots | amounts | finance | at-rest | reconcile |
| card data | **never** | — | N/A (provider tokenized) | N/A |

---

## 6. Community / Chat / Education

| Table | Sensitive fields | Access rules | Encryption at rest | Audit |
|---|---|---|---|---|
| `community_posts` / comments | content | public surface (auth) | at-rest | moderate |
| `reports` (moderation) | reported content | SUP/ADM/MOD (spoiler) | at-rest | moderate |
| `conversations` / `messages` | private chat content | participants C13 only; admin none | at-rest; **no E2E v1** (SD-19) | message create/report |
| `blocks` | block graph | participants | at-rest | block (v2) |
| `education_content` | drafts (locked) | SUP/ADM review; public published | at-rest | publish/review |

---

## 7. Audit / Notifications / Settings

| Table | Sensitive fields | Access rules | Encryption at rest | Audit |
|---|---|---|---|---|
| `audit_logs` | actor, action, `details` (**no PHI**) | SUP/ADM (C6 own); append-only | at-rest | n/a (target) |
| `notification_templates` | placeholders only | SUP/ADM | at-rest | save |
| `notification_log` | delivery meta | SUP/ADM | at-rest | send |
| `push_tokens` | device tokens | backend; never exposed | at-rest | register/unregister |
| `settings` | values (incl. secret-config) | SUP (ADM conditional); values masked | sealed for secret-config | `admin.setting_change` |

---

## 8. Access / Encryption / Audit summary

| Cross-table rule | Implementation |
|---|---|
| Derived column for FK-scoped queries | `patient_id`, `requester_id`, `granted_to_user_id`, `*_uid uuid` UNIQUE (3.4 §21) |
| Masked output | serializer layer (never raw) — `contacts`, `phone`, payment numbers |
| Encrypted media | document/file blobs stored with per-file keys; signed URL download |
| Append-only | `audit_logs` — NOUPDATE/DELETE at application and DB grant |
| Identity mapping | internal `id` + external `uid` (never `id` in URLs) |

---

## 9. Candidate DB changes (future, owner-approved only — NOT implemented now)

| Candidate | Requirement | Table(s) | Stage |
|---|---|---|---|
| CBD-1 | add `recovery_codes_hash` column | users (or mfa table) | SD-6 MFA recovery |
| CBD-2 | add `device_metadata` / `last_login_device` columns | security_events | new-device step-up (SD-5) |
| CBD-3 | add `nonce`/`event_id` registry for webhook replay | payments (webhook_events) | ASG-9 |
| CBD-4 | signed media key table / `file_enc_key_ref` | files | encrypted media |
| CBD-5 | `emergency_access_grants` window columns already approved (3.4) | emergency_access_grants | §9/§10 (already in 3.4) |
| CBD-6 | audit archive tables (cheap tier) | audit_logs archive | §33 retention |
| CBD-7 | anonymization/tombstone columns for erasure | users/patients | §33/§43 |

All CBD rows are **candidate only**; each will be amended into 3.4 with owner
approval and may alter the approved ERD — documented reason, not staged now.

---

END — gap/deletion linked to `security-design.md` §33/§43 and review decisions.