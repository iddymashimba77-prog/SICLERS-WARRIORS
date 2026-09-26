# 3.5 API Endpoint Matrix

> Stage 3.5 — System Design. Companion to `api-design.md`. This is the
> authoritative endpoint inventory (design-level, nothing implemented).
>
> Legend:
> - **Auth**: `P` public, `T` authenticated token, `S` signed webhook/service.
> - **Permission**: code from the 3.3 catalog; condition suffixes from the 3.3
>   matrix (C2 consent · C3 authorized object · C4 audit/oversight · C5 verified
>   professional · C6 verification workflow · C7 facility context · C8 eligible
>   donors · C9 own match · C10 emergency override · C11 verified campaign ·
>   C12 review/publication · C13 participant-bound · C13b verified partner ·
>   C14 self/authorized patient · C15 clinical relationship+consent ·
>   C16 self-entered · C17 SUP-only privileged assign).
> - **Consent**: `O` owner-only, `C` consent-gated (C2/C3), `N` none/not PHI.
> - **Object rule**: core object-level authorization rule.
> - **Audit**: `Y` sensitive operation → `audit_logs` / `security_events`.
>
> Base URL: `/api/v1/`. {id} = internal id where tables use bigint; {uid} =
> public UUID for API-exposed resources (3.4 §21). Filtering/sorting/pagination
> params per api-design §23/§24.

---

## 1. Auth (`/auth`)

| Module | Method | Endpoint | Auth | Permission | Consent | Object Rule | Audit | Notes |
|---|---|---|---|---|---|---|---|---|
| auth | POST | `/auth/register` | P | — | — | — | login event | role_code limited to self-registerable roles |
| auth | POST | `/auth/login` | P | — | — | — | Y | rate-limited; never discloses account existence |
| auth | POST | `/auth/refresh` | T | — | — | — | Y | rotation + reuse detection |
| auth | POST | `/auth/logout` | T | `auth.logout` | — | self | Y | blacklists refresh |
| auth | POST | `/auth/password-reset/request` | P | — | — | — | — | always 202 |
| auth | POST | `/auth/password-reset/confirm` | P(reset token) | — | — | — | Y | single-use, expiry |
| auth | POST | `/auth/password/change` | T | `auth.password_reset` | — | self | Y | requires current pwd |
| auth | POST | `/auth/verify/email` | P(token) | — | — | — | Y | FR-AUTH-004 |
| auth | POST | `/auth/verify/phone` | P(code) | — | — | — | Y | needed for emergency/donor flows |
| auth | POST | `/auth/mfa/setup` | T | `auth.mfa_manage` | — | self | Y | secret challenged |
| auth | POST | `/auth/mfa/enable` | T | `auth.mfa_manage` | — | self | Y | TOTP |
| auth | POST | `/auth/mfa/disable` | T | `auth.mfa_manage` | — | self | Y | re-auth required |
| auth | GET | `/auth/sessions` | T | `auth.profile_view` | — | self | — | active refresh sessions |
| auth | DELETE | `/auth/sessions/{id}` | T | `auth.profile_view` | — | self | Y | revoke session |

## 2. Users & profile (`/users`)

| Module | Method | Endpoint | Auth | Permission | Consent | Object Rule | Audit | Notes |
|---|---|---|---|---|---|---|---|---|
| users | GET | `/users/me` | T | `auth.profile_view` | — | self | — | public profile subset |
| users | PATCH | `/users/me` | T | `auth.profile_view` | — | self | — | no role/permission fields |
| users | GET/PATCH | `/users/me/privacy` | T | `notifications.manage_prefs` | — | self | — | notification+privacy settings |
| users | GET/PATCH | `/users/me/notifications/preferences` | T | `notifications.manage_prefs` | — | self | — | `notification_preferences` |
| users | GET | `/users/{uid}` | T | `users.view` (C6 VO) | — | — | C4 | admin scope |
| users | PATCH | `/users/{uid}` | T | `users.update` | — | — | Y | admin operational edit |

## 3. Roles & permissions (`/admin/roles`, `/admin/users`)

| Module | Method | Endpoint | Auth | Permission | Consent | Object Rule | Audit | Notes |
|---|---|---|---|---|---|---|---|---|
| rbac | GET | `/admin/roles` | T | SUP/ADM | — | — | — | catalog |
| rbac | GET | `/admin/permissions` | T | SUP/ADM | — | — | — | catalog |
| rbac | GET | `/admin/users/{uid}/roles` | T | `users.view` | — | — | — | current roles |
| rbac | POST | `/admin/users/{uid}/roles` | T | `users.role_assign` (C17) | — | SUP-only privileged | Y | self-assignment denied |
| rbac | DELETE | `/admin/users/{uid}/roles/{role_id}` | T | `users.role_assign` (C17) | — | SUP-only privileged | Y | reason required |
| rbac | GET/POST/DELETE | `/admin/users/{uid}/permissions` | T | `users.role_assign` | — | SUP/ADM | Y | audited overrides (`user_permissions`) |
| users | POST | `/admin/users/{uid}/activate` | T | `users.update` | — | — | Y | activation |
| users | POST | `/admin/users/{uid}/deactivate` | T | `users.deactivate` | — | — | Y | suspension + reason |

## 4. Patients (`/patients`)

| Module | Method | Endpoint | Auth | Permission | Consent | Object Rule | Audit | Notes |
|---|---|---|---|---|---|---|---|---|
| patient | GET/PATCH | `/patients/me` | T | `patients.view`/`update_own` | O | owner | — | FR-PAT-001/002 |
| patient | PUT | `/patients/me/profile-photo` | T | own | O | owner | — | private upload |
| patient | GET | `/patients/me/dashboard` | T | own | O | owner | — | meds/appts/symptoms summary |
| patient | GET/PATCH | `/patients/me/emergency-contact` | T | own | O | owner | — | FR-PAT-003 |
| patient | GET/PATCH | `/patients/{uid}` | T | `patients.view`/`patients.update` | C4 | admin/oversight | C4 | operational edit |
| patient | GET | `/patients/{uid}/health-summary` | T | `patients.view` C2/3 | C | consent+relationship | Y | clinician summary |
| patient | GET | `/patients/{uid}/timeline` | T | C2/3 (own=A) | C | owner/consent | Y | `health_timeline` |

## 5. Doctors (`/doctors`, `/admin/doctors`)

| Module | Method | Endpoint | Auth | Permission | Consent | Object Rule | Audit | Notes |
|---|---|---|---|---|---|---|---|---|
| doctor | GET/PATCH | `/doctors/me` | T | `doctors.self_manage` (C5) | — | self | — | professional profile |
| doctor | POST | `/doctors/me/verification` | T | `doctors.self_manage` | — | self | Y | submit/docs |
| doctor | GET | `/doctors` | T | `doctors.view` | N | public subset | — | directory (name/specialty/verified) |
| doctor | GET | `/doctors/{uid}` | T | `doctors.view` | N | public subset | — | no personal contact leakage |
| doctor | GET/POST/PATCH | `/doctors/me/availability` | T | `doctors.self_manage` | — | self | — | slots |
| doctor | GET | `/doctors/me/patients` | T | `patients.view` C2/3 | C | relationship+consent | C4 | FR-DOC-005 |
| doctor | GET | `/doctors/me/patients/{uid}/medical-records` | T | `medical_records.view` C2/3 | C | relationship+consent | Y | never blanket |
| doctor | GET | `/doctors/me/appointments` | T | `appointments.view` C2/3 | C | relationship+consent | — | schedule |
| doctor | POST | `/admin/doctors/{uid}/verify` | T | `doctors.verify` (VO/ADM, C6) | — | — | Y | approve/reject |
| doctor | POST | `/admin/doctors/{uid}/suspend` | T | `doctors.verify` | — | — | Y | suspension |

## 6. Facilities (`/facilities`, `/admin/facilities`)

| Module | Method | Endpoint | Auth | Permission | Consent | Object Rule | Audit | Notes |
|---|---|---|---|---|---|---|---|---|
| facility | GET | `/facilities` | P | — | N | verified only | — | public list |
| facility | GET | `/facilities/{uid}` | T | — | N | verified | — | no clinical data |
| facility | GET/PATCH | `/facilities/me` | T | HOSPITAL operator (C7) | N | own facility | — | profile |
| facility | GET/POST | `/facilities/me/staff` | T | HOSPITAL (C7) | N | own facility | Y | `healthcare_staff` |
| facility | GET | `/facilities/me/doctors` | T | HOSPITAL | N | own facility | — | linked doctors |
| facility | GET/POST | `/facilities/me/appointments` | T | HOSPITAL/STAFF (C7) | C | own facility+consent | — | appointments |
| facility | POST | `/admin/facilities/{uid}/verify` | T | VO/ADM (C6) | — | — | Y | verification |

## 7. Caregivers (`/caregivers`)

| Module | Method | Endpoint | Auth | Permission | Consent | Object Rule | Audit | Notes |
|---|---|---|---|---|---|---|---|---|
| caregiver | GET | `/caregivers` | T | `caregivers.view` | C | patient own / C3 grantee | — | list |
| caregiver | POST | `/caregivers` | T | `caregivers.invite` (PAT) | O | patient | Y | invite → PENDING |
| caregiver | POST | `/caregivers/{id}/accept` | T | invitee | C | invitee only | Y | → ACTIVE |
| caregiver | POST | `/caregivers/{id}/decline` | T | invitee | C | invitee only | — | → declined |
| caregiver | GET/PATCH | `/caregivers/{id}/permissions` | T | `caregivers.modify` (PAT) | O | patient | Y | consent scope for link |
| caregiver | DELETE | `/caregivers/{id}` | T | `caregivers.remove` (PAT) | O | patient | Y | revoke + consent REVOKED |

## 8. Consents (`/consents`)

| Module | Method | Endpoint | Auth | Permission | Consent | Object Rule | Audit | Notes |
|---|---|---|---|---|---|---|---|---|
| consent | POST | `/consents` | T | `consents.grant` (PAT) | O | patient | Y | DRAFT→ACTIVE, scope+expiry |
| consent | GET | `/consents` | T | `consents.view` | C | owner or named grantee | — | list |
| consent | GET | `/consents/{id}` | T | `consents.view` | C | owner or named grantee | — | detail |
| consent | PATCH | `/consents/{id}` | T | `consents.grant` (PAT) | O | patient | Y | amend scope/expiry |
| consent | POST | `/consents/{id}/revoke` | T | `consents.revoke` (PAT) | O | patient | Y | immediate (FR-MEDREC-005) |
| consent | POST | `/consents/{id}/renew` | T | `consents.grant` (PAT) | O | patient | Y | extend expiry |
| consent | GET | `/consents/active` | T | `consents.view` | C | grantee C2 | — | C2 evaluation |

## 9. Medical records (`/medical-records`, `/patients/{uid}/...`)

| Module | Method | Endpoint | Auth | Permission | Consent | Object Rule | Audit | Notes |
|---|---|---|---|---|---|---|---|---|
| medrec | GET | `/patients/me/medical-records` | T | `medical_records.view` (own=A) | O | owner | — | own list |
| medrec | POST | `/patients/me/medical-records` | T | `medical_records.create` (C16/C15) | O | owner | Y | patient entry |
| medrec | GET | `/patients/me/medical-records/{id}` | T | own | O | owner | Y(high) | sensitive read audited |
| medrec | PATCH | `/patients/me/medical-records/{id}` | T | own C16 | O | owner | Y | update own entry |
| medrec | DELETE | `/patients/me/medical-records/{id}` | T | own C16 | O | owner | Y | soft delete |
| medrec | GET | `/patients/{uid}/medical-records` | T | `medical_records.view` C2/3 | C | consent+grantee context | Y | clinician/caregiver |
| medrec | POST | `/patients/{uid}/medical-records` | T | C15 | C | clinical relationship+consent | Y | clinical entry (DOC/STA/HOS) |
| medrec | POST | `/patients/{uid}/medical-records/{id}/files` | T | C15 or own | C/O | context | Y | private upload |
| medrec | GET | `/patients/{uid}/medical-records/{id}/files/{fid}` | T | `medical_records.download` C2/3 | C | consent scope incl. file | Y | download |
| encounter | GET/POST | `/clinical-encounters` | T | C15 | C | facility+consent | Y | `clinical_encounters` |

## 10. Medications (`/medications`)

| Module | Method | Endpoint | Auth | Permission | Consent | Object Rule | Audit | Notes |
|---|---|---|---|---|---|---|---|---|
| medication | GET/POST | `/medications` | T | `medications.create/view` | O | owner | — | FR-MED-001 |
| medication | GET/PATCH/DELETE | `/medications/{id}` | T | own (doc C2/3) | O/C | owner/consent | — | manage |
| medication | GET/POST | `/medications/{id}/schedule` | T | own | O | owner | — | FR-MED-002 |
| medication | PATCH/DELETE | `/medications/{id}/schedule/{sid}` | T | own | O | owner | — | edit schedule |
| medication | POST | `/medications/{id}/log-dose` | T | `medications.update` (own) | O | owner | Y | FR-MED-004 + idempotency |
| medication | GET | `/medications/{id}/events` | T | own | O | owner | — | FR-MED-005 |
| medication | GET | `/medications/stats` | T | own | O | owner | — | FR-MED-006 async |

## 11. Appointments (`/appointments`)

| Module | Method | Endpoint | Auth | Permission | Consent | Object Rule | Audit | Notes |
|---|---|---|---|---|---|---|---|---|
| appointment | GET | `/appointments` | T | `appointments.view` (C7/C2/3) | C | own/doctor/facility | — | list |
| appointment | POST | `/appointments` | T | `appointments.create` | C | own or authorized | — | FR-APP-001, idempotency |
| appointment | GET | `/appointments/{id}` | T | C3/C7 | C | participant/facility | — | detail |
| appointment | POST | `/appointments/{id}/confirm` | T | DOC/STA (C7) | C | clinical context | Y | SCHEDULED→CONFIRMED |
| appointment | POST | `/appointments/{id}/reschedule` | T | PAT own / DOC C2/3 | C | owner/context | Y | transition |
| appointment | POST | `/appointments/{id}/cancel` | T | `appointments.cancel` | C | owner/doctor | Y | →CANCELLED |
| appointment | POST | `/appointments/{id}/complete` | T | DOC/STA (C7) | C | clinical context | Y | →COMPLETED |
| appointment | POST | `/appointments/{id}/no-show` | T | DOC/STA (C7) | C | clinical context | Y | →NO_SHOW |
| notification | — | reminders | async job | — | — | — | — | FR-APP-002 |

## 12. Blood network (`/blood`, `/admin/blood`)

| Module | Method | Endpoint | Auth | Permission | Consent | Object Rule | Audit | Notes |
|---|---|---|---|---|---|---|---|---|
| donor | GET/PATCH | `/blood/donors/me` | T | `blood_donors.self_manage` (BLD) | — | self | — | FR-BLD-001..004 |
| donor | GET | `/blood/donors` | T | `blood_donors.view` (C7) | — | internal | — | no public contact data |
| blood | GET | `/blood/requests` | T | `blood_requests.view` (A/C3/C8) | C8 | tracked/eligible | — | verified-only public subset |
| blood | POST | `/blood/requests` | T | `blood_requests.create` | — | — | Y | FR-BLD-005/006, idempotency |
| blood | GET | `/blood/requests/{id}` | T | C3/C8 | C8 | tracked | — | no donor PII |
| blood | POST | `/blood/requests/{id}/cancel` | T | owner | — | owner | Y | →CANCELLED |
| blood | POST | `/admin/blood/requests/{id}/verify` | T | `blood_requests.verify` (VO/ADM, C6) | — | — | Y | BR-005 |
| blood | POST | `/admin/blood/requests/{id}/reject` | T | `blood_requests.verify` | — | — | Y | reason required |
| match | GET | `/blood/requests/{id}/matches` | T | `blood_matches.view` C9 | C9 | own request | C4 | FR-BLD-007 |
| match | POST | `/blood/matches/{id}/respond` | T | `blood_requests.respond` (BLD, C8/C9) | C9 | own match | Y | FR-BLD-009 |
| blood | POST | `/blood/requests/{id}/donation-events` | T | STA/HOS (C7) | — | facility | Y | immutable history |
| blood | POST | `/admin/blood/run-matching` | T | `blood_matches.run` (SUP/ADM) | — | — | Y | async matcher |

## 13. Emergency (`/emergency`, `/admin/emergency`)

| Module | Method | Endpoint | Auth | Permission | Consent | Object Rule | Audit | Notes |
|---|---|---|---|---|---|---|---|---|
| emergency | POST | `/emergency/requests` | T | `emergency_requests.create` (C14) | — | own/C14 | Y | FR-EMG-001/002, rate-limit+key |
| emergency | GET | `/emergency/requests` | T | `emergency_requests.view` | — | owner/responder | — | list |
| emergency | GET | `/emergency/requests/{id}` | T | `emergency_requests.view` | — | owner/responder | — | detail |
| emergency | POST | `/emergency/requests/{id}/validate` | T | operator/system | — | — | Y | telephone/severity checks |
| emergency | POST | `/emergency/requests/{id}/respond` | T | `emergency_requests.manage` | — | responder | Y | →RESPONDING |
| emergency | POST | `/emergency/requests/{id}/escalate` | T | `emergency_requests.manage` | — | responder | Y | →ESCALATED |
| emergency | POST | `/emergency/requests/{id}/resolve` | T | `emergency_requests.resolve` | — | responder | Y | →RESOLVED |
| emergency | POST | `/emergency/requests/{id}/cancel` | T | owner/operator | — | owner | Y | →CANCELLED |
| emergency | GET | `/emergency/access-grants` | T | C10 | — | patient context | Y | bounded override |
| emergency | GET | `/admin/emergency` | T | SUP/ADM (C4) | — | — | C4 | monitoring (FR-EMG-005/006) |

## 14. Campaigns (`/campaigns`, `/admin/campaigns`)

| Module | Method | Endpoint | Auth | Permission | Consent | Object Rule | Audit | Notes |
|---|---|---|---|---|---|---|---|---|
| campaign | GET | `/campaigns` | P | — | — | verified only | — | BR-007 |
| campaign | POST | `/campaigns` | T | `campaigns.create` (C11) | — | owner-role | — | DRAFT (FR-CAM-001) |
| campaign | GET | `/campaigns/{id}` | P | — | — | verified | — | FR-CAM-003 |
| campaign | PATCH | `/campaigns/{id}` | T | owner C11 | — | owner | — | update |
| campaign | POST | `/campaigns/{id}/submit` | T | owner | — | owner | Y | →PENDING_VERIFICATION |
| campaign | POST | `/admin/campaigns/{id}/verify` | T | `campaigns.verify` (VO/ADM, C6) | — | — | Y | BR-007 |

## 15. Donations & payments (`/donations`, `/payments`, `/webhooks`)

| Module | Method | Endpoint | Auth | Permission | Consent | Object Rule | Audit | Notes |
|---|---|---|---|---|---|---|---|---|
| donation | POST | `/donations` | T | `donations.create` | — | verified campaign (C11) | Y | FR-CAM-004, idempotency key |
| donation | GET | `/donations/{id}` | T | `donations.view` | — | donor/FIN/ORG | — | FR-CAM-005 |
| donation | GET | `/donations/{id}/receipt` | T | donor | — | donor | — | FR-CAM-006 |
| donation | GET | `/donations` | T | donor/ORG | — | own | — | history |
| donation | POST | `/admin/donations/{id}/refund` | T | `donations.refund` (SUP/ADM) | — | — | Y | refund workflow |
| payment | GET | `/payments/{transaction_id}` | T | `payments.view` | — | donor/FIN/ORG | — | FR-PAY-003 |
| payment | GET | `/payments` | T | donor/ORG | — | own | — | transactions |
| payment | POST | `/payments/{id}/retry` | T | donor | — | own PENDING/FAILED | Y | same idempotency |
| webhook | POST | `/webhooks/payments/{provider}` | S | `payments.verify` (service-internal) | — | — | Y | signed, idempotent, FR-PAY-004/005 |

## 16. Community (`/community`, `/admin/community`)

| Module | Method | Endpoint | Auth | Permission | Consent | Object Rule | Audit | Notes |
|---|---|---|---|---|---|---|---|---|
| community | GET | `/community/posts` | T | `community.create_post`(view) | N | public feed | — | FR-COM-001 |
| community | POST | `/community/posts` | T | `community.create_post` | N | — | — | →PUBLISHED |
| community | GET | `/community/posts/{id}` | T | — | N | visibility status | — | detail |
| community | PATCH/DELETE | `/community/posts/{id}` | T | author / `community.moderate` | N | author/mod | Y | hide soft-delete |
| community | GET/POST | `/community/posts/{id}/comments` | T | `community.comment` | N | — | — | FR-COM-002 |
| community | PATCH/DELETE | `/community/posts/{id}/comments/{cid}` | T | author / mod | N | author/mod | Y | moderation |
| community | POST/DELETE | `/community/posts/{id}/reactions` | T | — | N | — | — | toggle |
| community | POST | `/community/reports` | T | `community.report` | N | — | — | FR-COM-003 |
| community | GET | `/admin/community/reports` | T | `community.moderate` (SUP/ADM/MOD) | N | — | — | FR-COM-004 |
| community | POST | `/admin/community/reports/{id}/resolve` | T | `community.moderate` | N | — | Y | FR-COM-005 |

## 17. Chat (`/chat`)

| Module | Method | Endpoint | Auth | Permission | Consent | Object Rule | Audit | Notes |
|---|---|---|---|---|---|---|---|---|
| chat | GET | `/chat/conversations` | T | member | — | participant C13 | — | own |
| chat | POST | `/chat/conversations` | T | `chat.start` (DOC A / PAT C13b) | — | verified partner (C13b) | Y | DOCTOR_PATIENT |
| chat | GET | `/chat/conversations/{id}` | T | member | — | C13 | — | detail |
| chat | GET | `/chat/conversations/{id}/messages` | T | member | C | C13 | — | history |
| chat | POST | `/chat/conversations/{id}/messages` | T | `chat.send` (C13) | C | C13 | Y(hi-sens) | send |
| chat | DELETE | `/chat/conversations/{id}/messages/{mid}` | T | sender | — | sender | — | own tombstone |
| chat | POST | `/chat/conversations/{id}/read` | T | member | — | C13 | — | read/delivery |
| chat | POST | `/chat/conversations/{id}/leave` | T | member | — | participant | — | →LEFT |
| chat | POST | `/chat/conversations/{id}/add-participant` | T | creator/role | — | C13 | Y | authorized adds |

## 18. Education (`/education`, `/admin/education`)

| Module | Method | Endpoint | Auth | Permission | Consent | Object Rule | Audit | Notes |
|---|---|---|---|---|---|---|---|---|
| education | GET | `/education/categories` | P | — | N | — | — | FR-EDU-002 |
| education | GET | `/education/content` | P | — | N | published only | — | FR-EDU-001/004 |
| education | GET | `/education/content/{id}` | P | — | N | published | — | detail |
| education | POST | `/education/content` | T | `education.publish` (C12) | N | author | — | DRAFT |
| education | PATCH/DELETE | `/education/content/{id}` | T | author C12 | N | author | — | draft edit |
| education | POST | `/education/content/{id}/submit` | T | author | N | author | — | →IN_REVIEW |
| education | POST | `/admin/education/content/{id}/review` | T | `education.review` (SUP/ADM) | N | — | Y | FR-EDU-003 |

## 19. Notifications (`/notifications`, `/admin/notifications`)

| Module | Method | Endpoint | Auth | Permission | Consent | Object Rule | Audit | Notes |
|---|---|---|---|---|---|---|---|---|
| notification | GET | `/notifications` | T | `notifications.view` | — | recipient | — | FR-NOT-001..005 |
| notification | GET | `/notifications/{id}` | T | recipient | — | recipient | — | mark read |
| notification | POST | `/notifications/{id}/read` | T | recipient | — | recipient | — | mark read |
| notification | POST | `/notifications/read-all` | T | recipient | — | recipient | — | bulk |
| notification | GET/PATCH | `/notifications/preferences` | T | `notifications.manage_prefs` | — | self | — | FR-NOT-006 |
| notification | POST/DELETE | `/notifications/devices` | T | recipient | — | self | — | push tokens |
| notification | POST | `/admin/notifications/broadcast` | T | `notifications.broadcast` (SUP/ADM) | — | — | Y | system broadcast |

## 20. Administration (`/admin`)

| Module | Method | Endpoint | Auth | Permission | Consent | Object Rule | Audit | Notes |
|---|---|---|---|---|---|---|---|---|
| admin | GET | `/admin/dashboard` | T | SUP/ADM | — | — | C4 | aggregate KPIs |
| admin | GET | `/admin/users` | T | `users.view` | — | — | — | +search/filter |
| admin | GET | `/admin/doctors/verification-queue` | T | `doctors.verify` (VO/ADM) | — | — | — | pending |
| admin | GET | `/admin/blood/verification-queue` | T | `blood_requests.verify` | — | — | — | pending |
| admin | GET | `/admin/campaigns/verification-queue` | T | `campaigns.verify` | — | — | — | pending |
| admin | GET | `/admin/emergency` | T | SUP/ADM (C4) | — | — | C4 | monitoring |
| admin | GET | `/admin/community/reports` | T | `community.moderate` | — | — | — | queue |
| admin | GET | `/admin/audit-logs` | T | `audit_logs.view` (SUP/ADM, C6 VO) | — | — | — | export C4 |
| admin | GET | `/admin/analytics` | T | `analytics.view` (SUP/ADM, C6 VO) | — | — | C4 | aggregates/export |

## 21. AI assistant (`/ai`) — design placeholder (AD-2)

| Module | Method | Endpoint | Auth | Permission | Consent | Object Rule | Audit | Notes |
|---|---|---|---|---|---|---|---|---|
| ai | POST | `/ai/chat/` | T | `ai.use` | — | — | Y | non-diagnostic (BR-010/011) |
| ai | GET | `/ai/trends/{patient_uid}` | T | `ai.use` + analytics.health_trends C2/3 | C | owner/consent | Y | FR-AI-004 |