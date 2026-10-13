# 3.6 Mobile UI/API Traceability

> `Screen → User Role → Permission → API Endpoint → Database Resource →
> Security Rule`. Full tracing of mobile screens (inventory IDs) to the approved
> 3.5 endpoint matrix, 3.3 permission codes, and 3.4 database entities.
> **No screen depends on an endpoint that does not exist** (verified §QA).
>
> Conditions: C2 consent · C3 authorized object · C5 verified professional ·
> C6 verification workflow · C7 facility context · C8 eligible donors · C9 own
> match · C10 emergency override · C13 chat participants · C13b verified partner ·
> C14 self/authorized patient · C15 clinical relationship+consent ·
> C16 self-entry · C17 SUP-only.

| AUI | Screen | Roles | Permission | API (3.5 matrix module) | DB resource (3.4) | Security rule |
|---|---|---|---|---|---|---|
| AUTH-001 | Splash | all | — | `GET /users/me` | `users`, `token_denylist` | session probe, silent refresh |
| AUTH-003 | Login | all | `auth.login` | `POST /auth/login`, `/auth/refresh` | `users`, `security_events`, `token_denylist` | rate-limited 5/min; no existence leak |
| AUTH-004 | Register | public | — | `POST /auth/register` | `users`, `user_roles` | role_code limited; hashed pwd |
| AUTH-005/006 | Verify | pending | — | `POST /auth/verify/email`, `/verify/phone` | `users` | token/code single-use |
| AUTH-007/008 | Reset | public | — | `/auth/password-reset/request`, `/confirm` | `users` | always 202; single-use token |
| AUTH-009 | MFA | auth | `auth.mfa_manage` | `POST /auth/mfa/setup|enable|disable` | `users` (mfa_secret 🔒) | self only; re-auth |
| AUTH-010 | Sessions | auth | `auth.profile_view` | `GET /auth/sessions`, `DELETE /auth/sessions/{id}` | `security_events`, `users` | self-scoped; revoke audits |
| HOME-001 | Home | all | own scope | `GET /patients/me/dashboard`; doctor: `/doctors/me(appointments)`; donor: `GET /blood/requests` | `dashboard` join; `appointments`; `blood_requests` | role-scoped aggregates; no diagnosis in headline |
| PAT-001 | Health dash | patient/caregiver | own / consent | `GET /patients/me/health-summary`, `/patients/me/timeline` | `patients`, `health_timeline`, `symptoms` | own/consent only; PHI surface |
| PAT-002 | Profile | patient | `patients.view/update_own` | `GET/PATCH /patients/me`, `PUT /patients/me/profile-photo` | `patients` | owner-only edit |
| PAT-003 | Emg contacts | patient | own | `GET/PATCH /patients/me/emergency-contact` | `patients` | owner-only |
| MED-001 | Record list | patient / grantee | own / `medical_records.view` C2/3 | `GET /patients/me/medical-records`; doc: `/doctors/me/patients/{uid}/medical-records` | `medical_records*` | consent gate; no blanket |
| MED-002 | Record detail | patient / grantee | `medical_records.view` +C2/3 | `GET /patients/me/medical-records/{id}` | `medical_records`, links | object scoping; sensitive read audit |
| MED-003 | File viewer | authorized | `medical_records.download` C2/3 | `GET /medical-records/files/{fid}/download` | `medical_record_files` | chart read gate re-checked; no public URL; encryption at rest |
| MED-004 | Entry (own) | patient | `medical_records.create` C16 | `POST /medical-records/` | `medical_records` | self-entry authorship; PHI warning |
| MED-005 | Record history | patient / grantee | `medical_records.view` C2/3 | `GET /medical-records/{id}/history/`, `/medical-records/history/` | `medical_record_events` | append-only; non-PHI details |
| MED-006 | Share one record | patient | `medical_records.view` (owner) | `POST /medical-records/{id}/share/`, `/share/revoke/` | `medical_record_links` | 1 record → 1 user; optional expiry; revoke immediate |
| MED-007 | Visibility | patient | `medical_records.update` (owner) | `POST /medical-records/{id}/visibility/` | `medical_records` | per-record opt-out of consent reads |
| MED-008 | Attach file | patient / clinician | `medical_records.upload` C16/C15 | `POST /medical-records/{id}/files/` | `medical_record_files` | PDF/JPEG/PNG ≤15MB; magic + extension + SHA-256 |
| MED-009 | Archive/suppress | patient / clinician | `medical_records.update` | `POST /medical-records/{id}/status/` | `medical_records`, `medical_record_events` | soft status; suppressed leaves read set |
| CONS-001 | Consent list | patient | `consents.view` | `GET /consents`, `/consents/active` | `consents` | owner/grantee; active-filter C2 |
| CONS-002 | Consent detail | patient | `consents.view` | `GET /consents/{id}`, `/revoke`, `/renew` | `consents`, links | owner operate; revoke immediate |
| CONS-003 | Grant | patient | `consents.grant` | `POST /consents` | `consents` | owner explicit gesture; expiry |
| MEDT-001 | Meds list | patient/caregiver | own / `medications.view` | `GET /medications`, `GET /medications/stats` | `medications*` | own/consent scope |
| MEDT-002 | Meds add/edit | own / C16 | `medications.create/update` | `POST/PATCH /medications` | `medications` | `instructions` = prescriber directions, ≤2000 chars, separate from schedule `notes` (FR-MED-007) |
| MEDT-004 | Dose log | own / C16 | `medications.update` | `POST /medications/{id}/log-dose` | `medication_events` | idempotency key; server ack |
| APP-001..005 | Appointments | patient/doc/staff | `appointments.*` C7/C2/3 | `GET/POST /appointments`, `…/confirm/reschedule/cancel/complete` | `appointments` | state-transition checks server-side |
| APP-003 | Booking registries | patient | `facilities.view` / `doctors.view` | `GET /facilities`, `GET /doctors` | `facilities`, `doctors` | verified rows only; pre-selection only when exactly one facility; no free-text venue |
| BLOOD-002 | Create request | patient | `blood_requests.create` | `POST /blood/requests` | `blood_requests` | idempotent; BR-005/006 |
| BLOOD-003 | Request detail | owner / C3/C8 | `blood_requests.view` | `GET /blood/requests/{id}`, `/matches` | `blood_requests`, `blood_matches` | C8/C9; no donor PII |
| BLOOD-004 | Donor profile | blood donor | `blood_donors.self_manage` | `GET/PATCH /blood/donors/me` | `blood_donors` | self; location privacy |
| BLOOD-006 | Respond match | donor | `blood_requests.respond` C8/C9 | `POST /blood/matches/{id}/respond` | `blood_matches` | own match only |
| BLOOD-008 | Request decisions | owner / admin / eligible donor | same gate as BLOOD-003 | `GET /blood/requests/{uid}/decisions` | `blood_request_decisions` | append-only; decider reason shown verbatim |
| EMG-002..005 | Emergency | auth/patient | `emergency_requests.*` C14/C10 | `POST /emergency/requests`, `GET /emergency/requests/{id}`, `/cancel`, `/resolve` | `emergency_requests`, `emergency_responders`, `emergency_access_grants` | rate limit; idempotency; audit; bounded override |
| EMG-006 | Access status | patient | `emergency_requests.view` C10 | `GET /emergency/access-grants` | `emergency_access_grants` | bounded, expiring, audited |
| DOC-002 | Verification | doctor | `doctors.self_manage` C5 | `POST /doctors/me/verification` | `doctors`, `verification_documents` | verified-gating |
| DOC-003 | Patients | doctor | `patients.view` C2/3 | `GET /doctors/me/patients` | `patients`, consents | relationship+consent only |
| DOC-004 | Records (doc) | doctor | `medical_records.view` C2/3 | `GET /doctors/me/patients/{uid}/medical-records` | `medical_records*` | consent; authored only unless C15 |
| DOC-006 | Clinical note | doctor/staff | C15 | `POST /patients/{uid}/medical-records` | `medical_records` | clinical authorship; consent |
| DOC-008 | Verification history | self / `doctors.verify` | applicant or reviewer | `GET /doctors/{uid}/verification-history`, `GET /admin/doctors/verification-history` | `doctor_verification_decisions` | append-only; 404 (not 403) for everyone else |
| DOC-009 | Care directory | any auth | `doctors.view` | `GET /doctors`, `?professional_type=` | `doctors` | server narrows to APPROVED + active; public projection; also feeds APP-003's clinician picker |
| CAR-002 | Invite accept | caregiver | `caregivers.invite/accept` C14 | `POST /caregivers/{id}/accept|decline` | `caregivers` | invitee-only; scope+expiry |
| CAR-004 | Auth info view | caregiver | consent scope | scoped `GET /patients/me/*` | `patients`, `medical_records*`, `medications*` | consent scope only |
| CAR-006 | Remove | patient | `caregivers.remove` | `DELETE /caregivers/{id}` | `caregivers`, consents | patient-only; immediate |
| COM-001..005 | Community | all auth | `community.create_post/view/comment/report` | `GET/POST /community/posts`, `…/comments`, `…/reactions`, `POST /community/reports` | `community_posts*`, `reports` | no PHI in feed; moderation |
| CHAT-002 | Thread | chat roles | `chat.send` C13/C13b | `GET /chat/conversations/{id}/messages`, `POST …/messages`, `POST …/read` | `messages`, `conversations` | C13 participants; verified partner |
| EDU-001..003 | Education | public/auth | public | `GET /education/categories`, `/education/content` | `educational_content`, `education_categories` | published only; verified badge |
| DON-002..008 | Donations | donor/org | `donations.*` C11 | `GET /campaigns`, `GET /campaigns/{id}`, `POST /donations`, `GET /donations/{id}`, `GET /donations/{id}/receipt`, `GET /payments` | `campaigns`, `donations`, `payment_transactions`, `refunds` | C11 verified campaign; webhook-verified payment; idempotency |
| NOT-001/002 | Notifications | all | `notifications.view` / `manage_prefs` | `GET /notifications`, `/notifications/{id}/read`, `/read-all`, `GET/PATCH /notifications/preferences`, `POST/DELETE /notifications/devices` | `notifications*`, `notification_preferences` | recipient-scoped; no PHI previews |
| PRO-003 | Security | all | `auth.password_reset` / `auth.mfa_manage` | `/auth/password/change`, `/auth/mfa/*`, `/auth/sessions` | `users`, `security_events`, `token_denylist` | self; audit |
| PRO-009 | Logout | all | `auth.logout` | `POST /auth/logout` | `token_denylist` | revoke refresh |
| PRO-010 | Deactivate | all | `users.view`(self) | admin-or-support workflow (server) | `users` | audited; policy retention |
| SRCH-001 | Search | all | resource-scoped | scoped list endpoints (edu/blood/doctors/community) | per resource | **no patient discovery** |
| ADMIN-* | Admin | SUP/ADM | `users.role_assign` C17 etc. | → admin web (3.7) | — | HIDDEN on mobile |

## QA notes
- Every write path uses idempotency where 3.5 specifies (donations, payments,
  emergency, appointments, dose logs) → UI retry is safe.
- Privacy rails: medical data flows only through `medical_records.*`/`consents.*`
  surfaces; community/education/notifications carry no PHI (§23/§30).
- No screen calls a webhook endpoint (`/webhooks/payments/{provider}`) — those
  are server-to-provider; UI consumes verified state via `GET /payments`.
- No screen depends on an undefined API: matrix covers all inventory screens
  (incl. AI assistant excluded from v1 — 3.5 AD-2 future).