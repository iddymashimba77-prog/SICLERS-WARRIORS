# 3.7 Admin Screen ↔ API Traceability

> For every admin screen: **Screen → Role → Permission → API Endpoint (3.5) →
> DB Resource (3.4) → Security Rule → Audit Rule**. Missing endpoints are
> explicitly marked **`API GAP`** — the panel never invents an API. This
> document is the contract for Stage 4 API work and the checklist to verify
> that the admin panel is exactly the approved surface.

Method: rows reference `admin-screen-inventory.md` IDs; permission codes and
envelope/pagination rules come from 3.3 and 3.5. `(gap)` = endpoint does not
exist yet and MUST be raised as an API addition before the panel implements it.

---

## 1. Full Trace Table

| Screen ID | Screen | Role | Permission | API Endpoint | DB | Security rule | Audit |
|---|---|---|---|---|---|---|---|
| AUTH-A-01 | Login | all | `auth.login` | `POST /api/v1/auth/login` | users | MFA TOTP mandatory for admin | failed attempts |
| AUTH-A-02 | Reset | all | `auth.password_reset` | `POST /api/v1/auth/password/forgot` · `POST /api/v1/auth/password/reset` | users | rate-limit + timed token | event |
| AUTH-A-03 | MFA setup | all | `auth.mfa_setup` | `POST /api/v1/auth/mfa/setup` · `POST /api/v1/auth/mfa/verify` | mfa | backup codes one-time | event |
| AUTH-A-04 | Sessions (own) | all | `auth.sessions` | `GET /api/v1/auth/sessions` · `POST /api/v1/auth/sessions/{id}/revoke` | sessions | user-scoped only | revoke |
| AUTH-A-05 | Re-auth | SUP/ADM | `auth.reauth` | `POST /api/v1/auth/mfa/reauth` (MFA service) | mfa | TOTP + short TTL | reauth |
| ADM-DASH-001..4 | Dashboards | SUP/ADM/VO/MOD | `analytics.view` (kernel) | `GET /api/v1/admin/dashboard` **`(gap)`** — needs role-filtered kernels | analytics_snapshots, queue tables | aggregates only; no raw data | open |
| ADM-USR-001 | Users list | SUP/ADM | `users.view` | `GET /api/v1/admin/users?page=&status=&role=` | users | masked contacts | — |
| ADM-USR-002 | User detail | SUP/ADM | `users.view` | `GET /api/v1/admin/users/{uid}` | users | masked | view |
| ADM-USR-003 | Account actions | SUP/ADM | `users.update`/`users.deactivate` | `POST /api/v1/admin/users/{uid}/activate` · `deactivate` · `suspend` (3.5 §20) | users | state-machine guarded | each |
| ADM-USR-004 | Verify user | SUP/ADM/VO | `users.verify` (C6) | `POST /api/v1/admin/users/{uid}/verify` | users | scoped to verification | decision |
| ADM-USR-005 | Role assign | **SUP only** | `users.role_assign` (C17) | `POST /api/v1/admin/users/{uid}/roles` | user_roles | C17 — never self-assign | change |
| ADM-PAT-001 | Patients list | SUP/ADM | `patients.view` (C4) | `GET /api/v1/admin/patients` **`(gap)`** partial in 3.5 §20 | patients | C4 gate + reason | access open |
| ADM-PAT-002 | Patient profile | SUP/ADM | `patients.update` | `GET /api/v1/admin/patients/{pid}` **`(gap)`** | patients | C4; operational edit only | open |
| ADM-PAT-003 | Health timeline | SUP/ADM | `medical_records.view` (C4) | `GET /api/v1/patients/me/records/` (mirrored) | medical_records | C4 + consent-resolve | view/download |
| ADM-PAT-004 | Consents | SUP/ADM | `consents.view` (C4) | `GET /api/v1/patients/me/consents` (mirrored) | consents | C4 + scope | view |
| ADM-DOC-001 | Doctor queue | SUP/ADM/VO | `doctors.verify` (C6) | `GET /api/v1/admin/doctors/verification-queue` | doctor_profiles | scoped | view |
| ADM-DOC-002 | Doctor decision | SUP/ADM/VO | `doctors.verify` | `POST /api/v1/admin/doctors/{uid}/verify` · `{uid}/suspend` | doctor + audit | signed docs; decision job | decision |
| ADM-FCL-001 | Facilities | SUP/ADM/VO | `facilities.verify`,`facilities.view` | `GET /api/v1/admin/facilities` | facilities | internal data | view |
| ADM-FCL-002 | Facility verify | SUP/ADM/VO | `facilities.verify` | `POST /api/v1/admin/facilities/{fid}/verify` | facilities | verify scope | decision |
| ADM-CAR-001 | Caregivers | SUP/ADM | `caregivers.view` (C4) | `GET /api/v1/admin/caregivers` **`(gap)`** | caregiver_relationships | C4 + scope | view |
| ADM-CAR-002 | Caregiver remove | SUP/ADM | `caregivers.remove` (C4) | `POST /api/v1/admin/caregivers/{rel}/remove` **`(gap)`** | caregivers | C4 + reason | removal |
| ADM-BLD-001 | Blood requests | SUP/ADM/VO | `blood_requests.view` (C6) | `GET /api/v1/admin/blood/requests*` | blood_requests | no donor PII (BR-006) | view |
| ADM-BLD-002 | Blood verify | SUP/ADM/VO | `blood_requests.verify` | `POST /api/v1/admin/blood/verification-queue/…` | blood_requests | verify scope | decision |
| ADM-BLD-003 | Donors masked | SUP/ADM/VO | `blood_donors.view` (C6/7) | `GET /api/v1/admin/blood/donors` | blood_donors | masked (region/group) | view |
| ADM-BLD-004 | Matching | SUP/ADM/VO | `blood_matches.run`·`view` | `POST /api/v1/admin/blood/matches/run` | blood_matches | C9-scoped pairs | run |
| ADM-EMG-001 | Emergency monitor | SUP/ADM | `emergency_requests.view` (C4) | `GET /api/v1/admin/emergency` | emergency_requests | operational only | open |
| ADM-EMG-002 | Emergency list | SUP/ADM | same | `GET /api/v1/admin/emergency?status=` | emergency_requests | C4 | view |
| ADM-EMG-003 | Emergency detail | SUP/ADM | `emergency_requests.view`·`manage` | `GET /api/v1/admin/emergency/{caseId}` · `POST /{caseId}/respond\|escalate\|resolve` | emergency_requests | C4; C10 override bounded | action |
| ADM-DON-001 | Campaign queue | SUP/ADM/VO | `campaigns.verify` | `GET /api/v1/admin/campaigns/verification-queue` | campaigns | scoped queue | view |
| ADM-DON-002 | Campaign decision | SUP/ADM/VO | `campaigns.verify` | `POST /api/v1/admin/campaigns/{cid}/verify` | campaigns | beneficiary docs | decision |
| ADM-DON-003 | Donations | SUP/ADM | `donations.view`·`payments.view` | `GET /api/v1/admin/donations*`·payments | donations/payments | redacted payer refs | view |
| ADM-DON-004 | Reconciliation | SUP/ADM | `donations.view` | `GET /api/v1/payments/verify` (partial) **`(gap)`** · `POST /api/v1/payments/refund` | payments | webhook-only confirm (BR-008); human refund | refund |
| ADM-APP-001 | Appointments | HIDDEN | none (AD-A-6) | — | appointments | no approved permission | — |
| ADM-COM-001 | Reports queue | SUP/ADM/MOD | `community.moderate` | `GET /api/v1/admin/community/reports` | reports | spoiler content | view |
| ADM-COM-002 | Moderation decision | SUP/ADM/MOD | `community.moderate` | `POST /api/v1/admin/community/reports/{rid}/resolve` **`(gap)`** | reports/moderations | hide-first | decision |
| ADM-EDU-001 | Content list | SUP/ADM | `education.review` | `GET /api/v1/admin/education/content` **`(gap)`** | content | drafts locked | view |
| ADM-EDU-002 | Editor | SUP/ADM | `education.review` | `POST /api/v1/admin/education/content/{id}/draft` **`(gap)`** | content | draft only | save |
| ADM-EDU-003 | Review/publish | SUP/ADM | `education.review` | `POST /api/v1/admin/education/content/{id}/review` · `/publish` **`(gap)`** | content | publish after review | publish |
| ADM-COM-MSG-1 | Broadcast | SUP/ADM | `notifications.broadcast` | `POST /api/v1/admin/notifications/broadcast` **`(gap)`** | notifications | privacy-safe preview | send |
| ADM-NOT-001 | Templates | SUP/ADM | `notifications.broadcast` | `GET/POST /api/v1/admin/notifications/templates` **`(gap)`** | templates | placeholders | save |
| ADM-NOT-002 | Delivery log | SUP/ADM | `notifications.broadcast` | `GET /api/v1/admin/notifications/log*` **`(gap)`** | notification log | — | view |
| ADM-RPT-001 | Analytics | SUP/ADM, VO | `analytics.view` | `GET /api/v1/admin/analytics?range=` | analytics_snapshots | aggregates only | view |
| ADM-RPT-002 | Exports | SUP (ADM C4) | `analytics.export` | `POST /api/v1/admin/exports` **`(gap)`** | exports+audit | scope preview; no PHI in aggregates | export |
| ADM-AUD-001 | Audit explorer | SUP/ADM(VO) | `audit_logs.view` (C6) | `GET /api/v1/admin/audit-logs?actor=&module=&range=` | audit_logs | append-only, no PHI bodies | view |
| ADM-SEC-001 | Security center | SUP(+ADM) | `security_events` **`(gap)`** | `GET /api/v1/admin/security/alerts*` **`(gap)`** | security_events | masked creds never rendered | open |
| ADM-SET-001 | System settings | SUP(+ADM) | settings **`(gap)`** | `GET/POST /api/v1/admin/settings*` **`(gap)`** | settings | secret configs masked + reauth | save |
| ADM-SRCH-001 | Search | all authorized | per-index view | `GET /api/v1/admin/search?q=` **`(gap)`** | authorized indexes | no PHI previews | — |
| COM-P-001 | ProtectedGate | SUP/ADM | (on C4) | — (UI) → writes `audit_logs.access_open` | audit_logs | reason required | access_open |
| COM-H-001 | Default states | all | — | — | — | 403 policy | — |

---

## 2. Traceability Summary

| Metric | Count |
|---|---|
| Screens mapped | 52 (incl. COM-P-001, COM-H-001) |
| Endpoints existing (3.5 matrix asserts) | ≈ 25 |
| **API GAP (missing endpoint)** | **18** (dashboard kernels, patients list/profile, caregivers, reconciliation verify, report resolve, education CRUD/publish, broadcast, templates/log, exports, security events, settings, search) |
| Deliberately removed (no permission) | ADM-APP-001 (AD-A-6) |
| PHI-free guarantee broken anywhere? | none by design; PHI only via C4 gate |
| Export without permission | none (SUP/ADM-C4 only) |

**Gap policy**: 18 gaps are listed, not invented. Any Stage 4 concrete API
addition must first update this table and pass 3.8 security review; the panel
remains blocked on them (placeholder states `API GAP`, no fake data).

---

## 3. Invariant Checks

1. No screen depends on an endpoint not listed in `api-endpoint-matrix.md` or
   explicitly marked `API GAP`.
2. Every C4-flagged screen carries COM-P-001 gate and `audit_logs.access_open`.
3. No private chat endpoint is referenced by any admin screen (chat.* denied).
4. Every decision (verify/approve/reject/refund/moderation) is audit-logged
   with actor + reason.
5. UI columns always mirror permission-resolved API fields — no client-side
   joins into data the API refuses to give.
6. IOException on a gap route must show `API GAP` placeholder, never a
   fabricated dataset.

---

END — next: `admin-web-ui-ux-review.md`.