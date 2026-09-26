# 3.4 Database Design / ERD

> Stage: 3.4 — System Design. Status: **Design** (no project models, no project
> migrations, no project DDL. Django core scaffold tables only in `sickle_cell`). Application database `sickle_cell` on system PostgreSQL 18
> (port 5432, 127.0.0.1). Retained dev cluster on 5433 (not used by app).
>
> This revision incorporates the approved Stage 3.3 Roles & Permissions model
> (roles/permissions/role_permissions/user_roles, account status, consent
> permissions, emergency access grants) and maps every design decision to
> requirements. Companion files: `erd/*.md` (Mermaid ERDs) and
> `database-design-review.md` (audit + SDLC gate).

---

## 1. Database Architecture

```
Flutter (Android/iOS) ─┐
Admin Web ─────────────┼──▶ REST API (Django) ─▶ Django Services ─▶ Django ORM ─▶ PostgreSQL
                       └                              │
                                          Background Workers (async) ─┘
```

- Client applications **never** connect to PostgreSQL directly (system-architecture §3.1).
- Single source of truth: PostgreSQL primary. Redis for cache/queue/temp state only.
- Database is an implementation of domain modules: users/identity, patients,
  healthcare, medical, appointments, consent, blood, emergency, donations/payments,
  community, chat, notifications, education, organizations, analytics, audit.
- Boundary: no direct public-IP access to PostgreSQL from clients; only the API
  and workers connect.

Traceability: system-architecture §3.1, §3.10.

---

## 2. Database Technology

- **PostgreSQL 18** (system instance on port **5432**; application database
  `sickle_cell` on `127.0.0.1:5432`, role `sw_db_user`, managed by
  `scripts/setup_system_pg.sh`. Retained dev cluster on 5433 not used by app.)
- Django 6.1 + `psycopg` driver via `django.db.backends.postgresql` (already in
  `backend/config/settings.py`).
- PostgreSQL-native features used:
  - `gen_random_uuid()` — public resource `uid`s (§21).
  - `JSONB` — scopes, triggers, payloads, matching metadata (not for relations).
  - `CHECK` constraints for enum-like statuses (§22).
  - Partial unique indexes for active-record uniqueness.
  - `citext` (optional extension) for case-insensitive email if enabled.
- No SQLite replacement.

Environments: `sickle_cell` (dev) on port 5432; test DB `test_sickle_cell` (Django
prefix); staging via env. Old `sw_db`/`sw_db_test`/`sw_db_staging` retained on
port 5433, not used by the application (§28).

---

## 3. Data Domains

Domains map to the approved module architecture (application-architecture §3.2.2)
and drive app/table organization:

| # | Domain | Django app(s) | Tables (main) |
|---|---|---|---|
| 1 | Identity & Access | `accounts` | `users`, `roles`, `permissions`, `role_permissions`, `user_roles`, `user_permissions`, `verification_documents`, `token_denylist`, `security_events` |
| 2 | Patient | `patients` | `patients`, `caregivers`, `patient_preferences` |
| 3 | Healthcare | `doctors`, `facilities`, `hospitals→facilities` | `doctors`, `healthcare_staff`, `facilities` |
| 4 | Medical | `medical_records`, `medications`, `patients`(symptoms) | `record_categories`, `medical_records`, `clinical_encounters`, `medical_record_files`, `medical_record_links`, `medications`, `medication_schedules`, `medication_events`, `symptoms`, `symptom_types`, `health_timeline` |
| 5 | Appointments | `appointments` | `appointments` |
| 6 | Consent & Privacy | `medical_records` (consent service) | `consents` |
| 7 | Blood Donation | `blood_network` | `blood_donors`, `blood_requests`, `blood_matches`, `blood_donation_events` |
| 8 | Emergency | `emergencies` | `emergency_requests`, `emergency_responders`, `emergency_access_grants` |
| 9 | Donations & Payments | `donations` | `campaigns`, `donations`, `payment_transactions`, `refunds` |
| 10 | Community | `community` | `community_posts`, `comments`, `reactions`, `reports` |
| 11 | Communication | `doctors` (chat) | `conversations`, `conversation_participants`, `messages`, `message_attachments` |
| 12 | Notifications | `notifications` | `notifications`, `notification_preferences` |
| 13 | Education | `community` / `medical_records` | `education_categories`, `educational_content` |
| 14 | Organizations | `accounts` (orgs) / `donations` | `organizations`, `organization_members` |
| 15 | Analytics | `analytics` | `analytics_snapshots` (aggregates only) |
| 16 | Audit & Security | `audit` | `audit_logs`, `security_events`, `token_denylist` |

---

## 4. Identity Model

### 4.1 `users` — central identity

One identity row per human/institution login. Profiles (patient/doctor/staff/
donor/facility/organization) are separate 1:1 tables — no duplicated auth fields.

| Column | Type | Notes |
|---|---|---|
| `id` | `bigint` PK, identity | internal PK |
| `uid` | `uuid` unique | public resource id (§21) |
| `email` | `citext`/`text` unique, not null | lowercase, login identity |
| `phone` | `text` unique, null | alt login/notifications |
| `password_hash` | `text` not null | PBKDF2/argon, never plaintext (NFR-SEC-002) |
| `first_name`, `last_name` | `text` | |
| `account_status` | `text` CHECK | ACTIVE PENDING_VERIFICATION SUSPENDED DISABLED DEACTIVATED (§ role-perm §20) |
| `is_active` | `bool` default true | Django requirement; kept in sync with `account_status` |
| `mfa_enabled` | `bool` default false | |
| `mfa_secret_encrypted` | `bytea` null | protected field |
| `profile_photo_url` | `text` null | |
| `created_at`, `updated_at` | `timestamptz` | |
| `last_login_at` | `timestamptz` null | |
| `deleted_at` | `timestamptz` null | soft delete (§24) |

- Roles are **many-to-many** via `user_roles` (§5). No single `role` column
  (Stage 3.3 gap closed).
- Emergency contacts are DENORMALIZED onto `patients` intentionally (usable when
  network/profile unavailability) — required by FR-PAT-003/emergency flows.

### 4.2 Verification & auth-support tables

- `verification_documents` — `id`, `user_id` FK, `doc_type`
  (`LICENSE|NATIONAL_ID|CERTIFICATE|FACILITY_REGISTRATION|OTHER`), `file_url`
  (secure-storage key, never public URL), `status`
  (`PENDING|VERIFIED|REJECTED`), `reviewed_by` FK, `reviewed_at`, `rejection_reason`,
  `created_at`.
- `token_denylist` — `jti` PK, `user_id` FK, `expires_at`, `revoked_at`
  (JWT logout/rotation revocation; §4 nothing client-side).
- `security_events` — `id`, `user_id` FK null, `event_type`
  (`LOGIN_OK|LOGIN_FAILED|MFA_FAILED|RATE_LIMITED|PASSWORD_RESET|TOKEN_REFRESH`),
  `status`, `ip_address`, `user_agent`, `detail` JSONB, `created_at` (high-volume
  auth telemetry kept separate from operational `audit_logs`).

Traceability: FR-AUTH-001..006, NFR-SEC-002, SR Access Control, role-perm §20/§21.

---

## 5. Role & Permission Data Model

Approved Stage 3.3 model, fully relational (no unsafe hard-coded permission
strings in application tables):

| Table | Purpose | Key columns |
|---|---|---|
| `roles` | role catalog | `id`, `code` unique non-null, `name`, `description`, `is_privileged`, `is_medical`, `is_system` (seeded, non-mutable), `created_at` |
| `permissions` | permission catalog | `id`, `code` unique (`module.resource.action`), `module`, `resource`, `action`, `is_sensitive` (triggers audit), `created_at` |
| `role_permissions` | M2M role→permission | `role_id` FK, `permission_id` FK, UNIQUE(role_id, permission_id), `created_at` |
| `user_roles` | M2M user→role (multi-role) | `user_id` FK, `role_id` FK, `is_active`, `granted_by` FK, `granted_at`, `revoked_at`, UNIQUE(user_id, role_id) |
| `user_permissions` | per-user override grant/deny (rare, audited) | `user_id` FK, `permission_id` FK, `effect` CHECK(`ALLOW|DENY`), `granted_by` FK, `reason`, `granted_at`, `revoked_at`, UNIQUE(user_id, permission_id), `is_active` |

Design rules:
- Effective permission = union over `user_roles`→`role_permissions`, then
  overridden by `user_permissions` (DENY hard-blocks role grant; ALLOW grants an
  exception). Server computes this at request time from DB state; clients never
  supply roles/permissions (role-perm §21).
- Privileged/medical flags support separation-of-duties checks
  (`users.role_assign` is SUPER_ADMIN-only; medical permissions always C —
  role-perm §7, §14).
- No hard-coded permission privileges in application records; catalog changes
  are data + migration, audited.

Traceability: FR-AUTH-005, NFR-SEC-003/004, role-perm §5/§7/§21/§24.

---

## 6. Patient Data Model

| Table | Notes |
|---|---|
| `patients` | `user_id` FK unique (1:1), `date_of_birth`, `gender` CHECK, `genotype` CHECK (SS, SC, SBetaThal, SBetaC, unknown), `diagnosis_date`, `primary_diagnosis`, `emergency_contact_name`, `emergency_contact_phone`, `emergency_contact_relation`, `address_region`, `address_city`, `notes` (private), `created_at`, `updated_at`, `deleted_at` |
| `caregivers` | explicit relationship (role-perm §10): `id`, `patient_id` FK, `user_id` FK (caregiver account), `relationship_type` CHECK, `status` CHECK(PENDING ACTIVE REVOKED EXPIRED), `invited_by` FK, `accepted_at`, `created_at`, `updated_at`; UNIQUE(patient_id, user_id). Scope/duration/revocation are implemented by `consents` (authorization of record) — CAREGIVER role alone grants nothing |
| `patient_preferences` | `patient_id` FK, `language`, `theme`, `reminder_timezone`, `share_blood_status` bool, `updated_at` |

Ownership: patient owns `patients`, all `*_patient` rows under them, and controls
`consents`. Doctors/caregivers are authorized actors, never owners
(role-perm §8, §17).

Traceability: FR-PAT-001..004, FR-SYM-001..005, UR-01, US-PAT-*.

---

## 7. Healthcare Data Model

| Table | Notes |
|---|---|
| `facilities` | `uid`, `name`, `facility_type` CHECK(HOSPITAL CLINIC LABORATORY BLOOD_BANK PHARMACY OTHER), `region`, `city`, `address`, `registration_number`, `is_verified`, `verified_by` FK, `verified_at`, `created_at`, `updated_at`. Replaces `hospitals` (unified facility entity; HOSPITAL role account linked via facility operator) |
| `doctors` | `user_id` FK unique, `facility_id` FK null, `license_number`, `specialty` (code), `registration_body`, `verification_status` CHECK(PENDING APPROVED REJECTED SUSPENDED), `verified_by` FK, `verified_at`, `verification_expires_at` null, `rejection_reason`, `is_active`, `created_at`, `updated_at`. Sensitive documents live in `verification_documents` (secure storage, not public) |
| `healthcare_staff` | `user_id` FK unique, `facility_id` FK, `role_title`, `verification_status`, `verified_by`, `verified_at`, `is_active`, timestamps |

Rules: doctor functions depend on `users.account_status = ACTIVE` **and**
`doctors.verification_status = APPROVED` (role-perm §20, BR-001).

Traceability: FR-DOC-001..005, BR-001, UR-03, US-DOC-*, 3.3 §4.5/§4.6/§4.7.

---

## 8. Medical Data Model

### 8.1 Catalogs

- `record_categories` — `code` (DIAGNOSIS LAB_RESULT PRESCRIPTION CLINICAL_NOTE
  IMAGING DISCHARGE_SUMMARY VACCINATION OTHER), `name`, `is_confidential` bool.
- `symptom_types` — `code`, `name`, `is_pain_related` bool.

### 8.2 Records (normalized, no mega-table)

| Table | Notes |
|---|---|
| `clinical_encounters` | `uid`, `patient_id` FK, `facility_id` FK null, `doctor_id` FK null, `staff_id` FK null, `encounter_type` CHECK, `occurred_at`, `summary`, `created_by` FK, `created_at` |
| `medical_records` | `uid`, `patient_id` FK, `category_id` FK, `encounter_id` FK null, `title`, `description`, `facility_id` FK null, `recorded_by` FK, `recorded_at`, `status` CHECK(ACTIVE ARCHIVED SUPPRESSED), `is_consent_visible` bool default true, `created_at`, `updated_at`, `deleted_at`. Ownership = patient; authorship = `recorded_by` |
| `medical_record_files` | `record_id` FK, `file_url` (storage key), `file_name`, `content_type`, `size_bytes`, `checksum`, `uploaded_by` FK, `uploaded_at` (encrypted-at-rest storage; never a public URL) |
| `medical_record_links` | per-record visibility override (derived artifact of consent): `record_id` FK, `granted_to_user_id` FK, `scope`, `expires_at` null, `granted_by_patient_id` FK, `granted_at`, `revoked_at`, `revoked_by` |

### 8.3 Medication

| Table | Notes |
|---|---|
| `medications` | `uid`, `patient_id` FK, `name`, `generic_name`, `strength`, `dosage`, `route` CHECK, `frequency`, `start_date`, `end_date` null, `prescribed_by_id` FK null, `is_active`, `created_at`, `updated_at`, `deleted_at` |
| `medication_schedules` | `medication_id` FK, `time_of_day` time, `days_of_week` JSONB, `notes` |
| `medication_events` | `schedule_id` FK, `patient_id` FK, `status` CHECK(TAKEN MISSED SKIPPED SNOOZED), `taken_at` null, `note`, `created_at` (immutable; adherence derived) |

### 8.4 Symptoms / pain / timeline

| Table | Notes |
|---|---|
| `symptoms` | `uid`, `patient_id` FK, `symptom_type_id` FK, `pain_level` smallint CHECK 0..10, `triggers` JSONB, `duration_minutes`, `notes`, `recorded_at`, `created_at` |
| `health_timeline` | materialized projection (`patient_id`, `event_type`, `event_id`, `occurred_at`, `summary`, `payload` JSONB) written by domain events; indexed `(patient_id, occurred_at DESC)`. Reading is cheap; rebuild strategy documented for backfill |

Traceability: FR-MED-001..006, FR-SYM-001..005, FR-PAT-002, health-timeline.

---

## 9. Consent Data Model

Per approved 3.3 §15. Consent is the authorization layer for private data.

| Column | Type | Notes |
|---|---|---|
| `id`, `uid` | PK / uuid | |
| `patient_profile_id` | FK `patients` not null | grantor |
| `granted_to_user_id` | FK `users` not null | grantee |
| `authorized_role_id` | FK `roles` null | context (e.g. DOCTOR) |
| `resource_type` | `text` CHECK | `patients medical_records medications symptoms appointments health_timeline emergency` |
| `resource_ids` | JSONB null | specific record ids when scoped to records |
| `permission_scope` | JSONB not null | array of `module.resource.action` codes (e.g. `medical_records.view`) |
| `purpose` | `text` | purpose limitation (SR) |
| `start_date`, `expires_at` | `timestamptz` | expiry enforcement server-side |
| `status` | `text` CHECK | DRAFT ACTIVE REVOKED EXPIRED |
| `revoked_by` | FK null | |
| `revoked_at` | `timestamptz` null | immediate effect |
| `created_at`, `updated_at` | `timestamptz` | |

- Example: `patient A → doctor B → medical_records.view, expires +30d`;
  `patient A → caregiver C → medications.view, +90d`.
- Enforcement at request time: grantee's effective permissions **∩** consent
  `permission_scope`. Expiry/revocation checked against DB clock.
- Consent changes/access always audited (role-perm §15, §22).

Traceability: FR-MEDREC-003..006, SR consent/privacy, BR-002/003/004,
role-perm §10/§15.

---

## 10. Appointment Data Model

| Column | Type | Notes |
|---|---|---|
| `id`, `uid` | PK / uuid | |
| `patient_id` | FK `patients` not null | |
| `doctor_id` | FK `doctors` null | professional participant |
| `facility_id` | FK `facilities` not null | clinic context |
| `scheduled_time` | `timestamptz` | |
| `duration_minutes` | `smallint` CHECK >0 | |
| `type` | `text` CHECK | CONSULTATION FOLLOW_UP CHECKUP LAB REFERRAL |
| `status` | `text` CHECK | SCHEDULED CONFIRMED CANCELLED COMPLETED NO_SHOW MISSED |
| `cancel_reason` | `text` null | |
| `created_by` | FK `users` | |
| `created_at`, `updated_at` | `timestamptz` | |

- Reminders flow through `notifications` referencing the appointment
  (no duplication in appointments table).
- Staff/hospital sees only facility-scoped appointments (role-perm §3.6).

Traceability: FR-APP-001..004.

---

## 11. Blood Donation Data Model

| Table | Notes |
|---|---|
| `blood_donors` | `user_id` FK unique, `blood_group` CHECK(A+ A- B+ B- AB+ AB- O+ O-), `region`, `city`, `is_available` bool, `last_donation_date`, `donation_count` int, `is_verified` bool, `verified_by`, `verified_at`, timestamps |
| `blood_requests` | `uid`, `patient_id` FK null, `created_by` FK, `blood_group_needed` CHECK, `units` smallint, `urgency` CHECK(NORMAL URGENT CRITICAL), `facility_id` null, `reason`, `location` JSONB (lat/lng/region), `status` CHECK(PENDING_VERIFICATION ACTIVE MATCHING MATCHED FULFILLED EXPIRED CANCELLED REJECTED), `verified_by`, `verified_at`, `rejection_reason`, `created_at`, `updated_at`. **No donor PII in requests** (privacy) |
| `blood_matches` | `request_id` FK, `donor_id` FK, `match_score` numeric, `match_reason` JSONB, `status` CHECK(SUGGESTED NOTIFIED ACCEPTED DECLINED FULFILLED EXPIRED), `notified_at`, `responded_at`, `fulfilled_at`, `created_at` |
| `blood_donation_events` | `donor_id` FK, `request_id` null, `facility_id`, `units`, `donated_at`, `outcome` CHECK(COMPLETED DEFERRED FAILED), `donation_serial` unique, `recorded_by`, `created_at` (immutable history) |

- Donor contact exposure: only released via accepted/fulfilled workflow at a
  facility (BR-006). Matching is compatibility + location + availability;
  **medical eligibility** decided by qualified personnel (special-systems §3.9.1).
- Indexes on `(blood_group, city, is_available)`.

Traceability: FR-BLD-001..010, BR-005/006, UR-04, US-BLD-*.

---

## 12. Emergency Data Model

| Table | Notes |
|---|---|
| `emergency_requests` | `uid`, `requester_user_id` FK, `patient_profile_id` FK null, `severity` CHECK(NORMAL URGENT CRITICAL), `type` CHECK(MEDICAL PAIN_CRISIS BLOOD FALL OTHER), `location` JSONB, `description`, `status` CHECK(CREATED VALIDATING ACTIVE RESPONDING ESCALATED RESOLVED CANCELLED EXPIRED), `rate_limit_ok` bool, `phone_verified` bool, `escalated_at`, `resolved_by` FK, `resolved_at`, `created_at`, `updated_at` |
| `emergency_responders` | `request_id` FK, `responder_user_id` FK, `responder_role` CHECK(STAFF ADMIN CAREGIVER DONOR OTHER), `status` CHECK(NOTIFIED ACKNOWLEDGED EN_ROUTE ARRIVED DONE DECLINED), `notified_at`, `acknowledged_at`, `arrived_at`, `completed_at`, `updated_at` |
| `emergency_access_grants` | 3.3 §16 override grants: `id`, `uid`, `request_id` FK, `patient_profile_id` FK, `grantee_user_id` FK, `scope` JSONB (lifesaving subset), `reason`, `authorized_by` FK, `starts_at`, `expires_at` (default +24h), `status` CHECK(ACTIVE EXPIRED REVOKED), `revoked_by`, `revoked_at`, `created_at` |

- All status transitions and override activations are audited (BR-009,
  FR-EMG-006). Abuse prevention: rate limiting + verification flags.
- No `EMERGENCY = BYPASS ALL` rule; grants are bounded and auto-expire.

Traceability: FR-EMG-001..006, BR-009, role-perm §16, special-systems §3.9.2.

---

## 13. Financial Donation & Payment Model

| Table | Notes |
|---|---|
| `campaigns` | `uid`, `owner_user_id` FK, `organization_id` FK null, `title`, `description`, `goal_amount` numeric(14,2) CHECK >0, `raised_amount` numeric(14,2) default 0, `currency` CHAR(3), `status` CHECK(DRAFT PENDING_VERIFICATION ACTIVE PAUSED CLOSED REJECTED), `verified_by`, `verified_at`, `rejection_reason`, `start_date`, `end_date`, `created_at`, `updated_at`, `deleted_at` |
| `donations` | `uid`, `campaign_id` FK, `donor_user_id` FK, `amount` numeric(14,2) CHECK >0, `currency`, `status` CHECK(PENDING COMPLETED FAILED REFUNDED CANCELLED), `transaction_ref` unique, `idempotency_key` unique, `created_at`, `updated_at` |
| `payment_transactions` | `donation_id` FK, `provider` CHECK(M_PESA AIRTEL TIGO CLICKPESA SELCOM), `provider_ref` unique null, `status` CHECK(PENDING SUCCESS FAILED REFUNDED), `amount`, `currency`, `payload` JSONB (redacted provider response — no card PAN, no tokens in logs), `attempt` int, `created_at`, `updated_at` |
| `refunds` | `donation_id` FK, `transaction_id` FK, `amount`, `reason`, `initiated_by` FK, `approved_by` FK null, `status` CHECK(REQUESTED APPROVED PROCESSED REJECTED), `created_at`, `updated_at` |

- Server-side verification: `payments.verify` is service-internal (webhook +
  signature); success never trusted from client (BR-008, FR-PAY-004).
- Refunds go through the approval workflow (`users`/`payments.refund` =
  SUP/ADM only).

Traceability: FR-CAM-001..006, FR-PAY-001..005, BR-007/008.

---

## 14. Community Model

| Table | Notes |
|---|---|
| `community_posts` | `uid`, `author_user_id` FK, `title`, `content`, `category` CHECK(SUPPORT EDUCATION GENERAL VENTING), `status` CHECK(PUBLISHED HIDDEN REMOVED PENDING_REVIEW), `moderated_by` FK null, `moderated_at` null, `moderation_reason`, `created_at`, `updated_at`, `deleted_at` |
| `comments` | `post_id` FK, `author_user_id` FK, `content`, `status` CHECK(PUBLISHED HIDDEN REMOVED), `created_at`, `updated_at` |
| `reactions` | `post_id` FK, `user_id` FK, `reaction_type`, UNIQUE(post_id,user_id,reaction_type), `created_at` |
| `reports` | `reporter_user_id` FK, `target_type` CHECK(POST COMMENT), `target_id` (int, polymorphic), `reason`, `status` CHECK(OPEN IN_REVIEW RESOLVED DISMISSED), `reviewed_by` FK null, `review_notes`, `created_at`, `updated_at` |

Community data is fully separable from private medical records (data boundary).

Traceability: FR-COM-001..005.

---

## 15. Communication Model

| Table | Notes |
|---|---|
| `conversations` | `uid`, `type` CHECK(DOCTOR_PATIENT PEER GROUP), `created_by` FK, `status` CHECK(ACTIVE CLOSED ARCHIVED), `last_message_at`, `created_at`, `updated_at` |
| `conversation_participants` | `conversation_id` FK, `user_id` FK, `role_in_chat`, `status` CHECK(ACTIVE LEFT BLOCKED REMOVED), `invited_by` FK, `joined_at`, UNIQUE(conversation_id,user_id) |
| `messages` | `uid`, `conversation_id` FK, `sender_id` FK, `content`, `message_type` CHECK(TEXT IMAGE FILE SYSTEM), `status` CHECK(SENT DELIVERED READ FAILED DELETED), `created_at`, `deleted_at` (own-view tombstone) |
| `message_attachments` | `message_id` FK, `file_url` (storage key), `content_type`, `size_bytes`, `uploaded_by` FK, `uploaded_at` |

- Doctor-patient chat requires an active consent/authorized context; participant
  object-level checks at API layer (role-perm §17). Attachments stored encrypted.

Traceability: FR-DOC-005, UR-01 (chat with verified professionals).

---

## 16. Notification Model

| Table | Notes |
|---|---|
| `notifications` | `recipient_user_id` FK, `type` CHECK(MEDICATION_REMINDER APPOINTMENT BLOOD EMERGENCY PAYMENT COMMUNITY CONSENT SYSTEM), `channel` CHECK(PUSH IN_APP EMAIL SMS), `title`, `body`, `related_resource_type`, `related_resource_id`, `status` CHECK(PENDING SENT DELIVERED READ FAILED SUPPRESSED), `delivery_key` unique null (dedupe), `read_at`, `sent_at`, `created_at` |
| `notification_preferences` | `user_id` FK, `category` CHECK(mirrors type), `enabled` bool, UNIQUE(user_id, category), `updated_at` |

- Emergency notifications are high-priority and cannot be disabled by the user
  (special-systems §3.9.4); enforced at service layer, not by the table.
- Notifications reference resources — no per-module notification duplication.

Traceability: FR-NOT-001..006.

---

## 17. Education Model

| Table | Notes |
|---|---|
| `education_categories` | `code`, `name`, `sort_order` |
| `educational_content` | `uid`, `title`, `body`, `category_id` FK, `author_user_id` FK, `status` CHECK(DRAFT IN_REVIEW PUBLISHED ARCHIVED REJECTED), `reviewed_by` null, `reviewed_at` null, `rejection_reason`, `cover_url`, `published_at` null, `created_at`, `updated_at` |

Traceability: FR-EDU-001..004.

---

## 18. Organization Model

| Table | Notes |
|---|---|
| `organizations` | `uid`, `org_type` CHECK(NGO COMPANY COMMUNITY TRUST HEALTH_FACILITY_BODY OTHER), `name`, `registration_number`, `contact_email`, `is_verified`, `verified_by` FK null, `verified_at`, `created_at`, `updated_at` |
| `organization_members` | `organization_id` FK, `user_id` FK, `member_role` CHECK(OWNER MANAGER MEMBER), `is_active`, `granted_by` FK, `created_at`, `updated_at`, UNIQUE(organization_id, user_id) |

- ORGANIZATION role users operate organization accounts through membership
  (open decision ODD-5 default: designate authorized operator user).

Traceability: UR-05 (campaigns), FR-CAM-001.

---

## 19. Analytics Data Considerations

- Store **aggregate/anonymized** snapshots only: `analytics_snapshots`
  (`metric_key`, `dimensions` JSONB, `value` numeric, `granularity`
  CHECK(DAILY WEEKLY MONTHLY), `measured_at`, UNIQUE(metric_key, dimensions,
  granularity, measured_at)).
- Health-trend analysis reads from `symptoms`/`medication_events` in aggregate
  with de-identification; **no** duplicate PHI in analytics tables.
- No medical content duplicated for analytics; joins over minimum required
  columns with access controls (role-perm §3.19).

Traceability: FR-AI-004, NFR-PERF-002, admin-web-design (reports).

---

## 20. Audit & Security Model

`audit_logs` (append-only, operational):

| Column | Type | Notes |
|---|---|---|
| `id` | `bigint` PK | |
| `actor_user_id` | FK `users` null | system events have null actor |
| `action_code` | `text` | e.g. `consents.grant`, `medical_records.view`, `doctors.verify` |
| `resource_type`, `resource_id` | `text`/`bigint` null | polymorphic |
| `result` | `text` CHECK | SUCCESS FAILURE DENIED |
| `ip_address`, `user_agent` | `text` | |
| `request_id` | `uuid` | trace |
| `details` | JSONB | minimal context (**no** medical payload, no card data — role-perm §22) |
| `created_at` | `timestamptz` | |

- No update/delete path (application and DB-level restrictions).
- High-volume auth telemetry lives in `security_events` (§4.2) to keep
  `audit_logs` clean.
- `token_denylist` for revocation (JWT).

Traceability: BR-012, NFR-SEC-004, FR-EMG-006, role-perm §22.

---

## 21. Primary Key Strategy

- **Internal PK:** `bigint identity` (`bigserial`) on every table — fast joins,
  compact pages, cheap FKs, aligns with Django.
- **Public id:** `uid uuid DEFAULT gen_random_uuid() UNIQUE` on every resource
  exposed via API (patients, records, consents, blood requests, campaigns,
  donations, emergency requests, posts, conversations, messages, facilities,
  organizations). Prevents predictable/sequential resource enumeration
  (SR/security, threat "unauthorized medical access").
- `transaction_ref`, `provider_ref`, `delivery_key`, `donation_serial` use
  `text`/`uuid` with UNIQUE + UUID/random generation (non-sequential).
- API design: internal `id` NEVER in URLs; `uid` used externally.

Documented architecture: internal numeric identity + external UUID, with a
mapping maintained by ORM.

---

## 22. Constraints

- **PK/UNIQUE:** all tables PK; UNIQUE on `users.email`, `users.phone`,
  `users.uid`, `roles.code`, `permissions.code`, M2M composites, `campaigns.uid`,
  `donations.transaction_ref`, `donations.idempotency_key`,
  `payment_transactions.provider_ref`, `reactions` triple, participant Pairs,
  `blood_donation_events.donation_serial`.
- **NOT NULL:** critical fields (identity/status/amount/scope) as specified in §4–§20.
- **CHECK (enum values):** `account_status`, role-level `is_system` rules,
  `verification_status`, consent `status`, blood `blood_group` and request
  statuses, `urgency`, `severity`, emergency/responder statuses, appointment
  `type`/`status`, payment/donation/refund statuses, notification `type`,
  community/report/education statuses, `pain_level` 0..10, positive `amount`/
  `units`/`duration_minutes`.
- **FK:** all relationships enforced (no orphan rows); `ON DELETE RESTRICT`
  (immutable history: audit, transactions, events) with `SET NULL` where a
  nullable professional/facility is soft-retired.
- **Partial unique indexes:** active-only uniqueness where a hard UNIQUE would
  block soft-delete (e.g. `users` email on not-deleted).
- Business-critical integrity lives in the database, not only application code
  (NFR-MAIN-002, BR rules).

---

## 23. Indexing Strategy

Primary indexes by real query patterns (from requirements/API design):

| Table / expression | Index | Why |
|---|---|---|
| `users.email`, `users.phone` | UNIQUE | login lookup (FR-AUTH) |
| `user_roles(user_id)`, `role_permissions(role_id)` | B-tree | permission resolution hot path |
| `patients(user_id)` | UNIQUE | 1:1 lookup |
| `doctors.verification_status` | B-tree | admin verification queues (FR-DOC-003) |
| `appointments(patient_id, scheduled_time)` | B-tree | schedule queries / reminders |
| `blood_donors(blood_group, city, is_available)` | B-tree | matching filter (FR-BLD-007) |
| `blood_requests.status`, `urgency` | B-tree | request monitoring |
| `emergency_requests.status, severity, created_at` | B-tree | live feed + triage push |
| `payment_transactions.provider_ref`, `donations.transaction_ref` | UNIQUE | idempotent webhooks (FR-PAY-004) |
| `notifications(recipient_user_id, created_at)` | B-tree | inbox (NFR-PERF-002 pagination) |
| `consents(granted_to_user_id, status)`, `consents(patient_profile_id,status)` | B-tree | consent checks (FR-MEDREC-005) |
| `audit_logs(resource_type, resource_id, created_at)` | composite | audit lookup (role-perm §22) |
| `messsages(conversation_id, created_at)` | B-tree | chat history |
| `health_timeline(patient_id, occurred_at DESC)` | B-tree | timeline view |

No speculative indexes beyond these; add in implementation when explain-plans
show writes/reads skew.

---

## 24. Soft Delete & Data Retention

| Data class | Strategy |
|---|---|
| Users, patients, profiles | Soft delete (`deleted_at`) — legal/identity history retained |
| Medical records, files | Soft delete (status `ARCHIVED`/`SUPPRESSED`) — never hard-purge PHI |
| Consents | Terminal status `REVOKED`/`EXPIRED`; retained for audit |
| Medications, appointments, campaigns, posts, comments | Soft delete / status transitions |
| Medication events, donations, payment transactions, blood donation events, emergency requests/responders, audit logs, security events | **Immutable** — no delete; corrected via compensating events/refunds |
| Notifications, reactions, preferences, participants | Hard delete acceptable (re-creatable, low audit value) |
| Health timeline | Derived — rebuilt on source changes; not user-deletable |

Retention: audit ≥ durable/append-only (retention policy, non-destructive);
PHI kept per data-protection/erasure policy with a documented retention window
(security-architecture §3.8.6). Soft-delete only where it has legal/audit value —
not a blanket rule.

---

## 25. Privacy Classification

| Class | Data | Protection |
|---|---|---|
| **Highly Sensitive** | medical records/files, medications, symptoms, consent details, `mfa_secret`, auth hashes, payment payload | encrypted at rest, consent-gated access (role-perm conditional C), strict audit, no PHI in log payloads |
| **Private** | patient profile, appointments, donor contact, chat content, notification bodies | authorization + object-level checks; donor contact hidden publicly (BR-006) |
| **Internal** | audit logs, analytics aggregates, verification documents, role/permission config | admin-scope, read-only, MFA-requiring |
| **Public** | verified campaign metadata, education content, community posts (as authored), doctor directory (`doctors.view`) | no access control beyond rate limiting |

Minimize storage: payment `payload` redacted (no PAN/token in columns);
analytics stores aggregates only; audit logs store references not content.

---

## 26. Django Model Mapping

| Domain Entity | Django App | Django Model | DB Table | Responsibility |
|---|---|---|---|---|
| Identity | accounts | `User` (custom) | `users` | auth, status, profile pointer |
| Roles | accounts | `Role` | `roles` | catalog |
| Permissions | accounts | `Permission` | `permissions` | catalog |
| Role-Permission M2M | accounts | `RolePermission` | `role_permissions` | matrix |
| User-Role M2M | accounts | `UserRole` | `user_roles` | assignment |
| User Permission override | accounts | `UserPermissionOverride` | `user_permissions` | exceptions |
| Verification docs | accounts | `VerificationDocument` | `verification_documents` | proof files |
| Security events | accounts | `SecurityEvent` | `security_events` | auth telemetry |
| Token denylist | accounts | `TokenDenylistEntry` | `token_denylist` | JWT revoke |
| Patient | patients | `Patient` | `patients` | profile/ownership |
| Caregiver link | patients | `CaregiverRelationship` | `caregivers` | explicit links |
| Preferences | patients | `PatientPreference` | `patient_preferences` | prefs |
| Symptom type | medical_records | `SymptomType` | `symptom_types` | catalog |
| Symptom | patients | `Symptom` | `symptoms` | tracking |
| Record category | medical_records | `RecordCategory` | `record_categories` | catalog |
| Encounter | medical_records | `ClinicalEncounter` | `clinical_encounters` | visits |
| Record | medical_records | `MedicalRecord` | `medical_records` | documents |
| Record file | medical_records | `MedicalRecordFile` | `medical_record_files` | attachments |
| Record link | medical_records | `MedicalRecordLink` | `medical_record_links` | visibility |
| Medication | medications | `Medication` | `medications` | regimen |
| Schedule | medications | `MedicationSchedule` | `medication_schedules` | timing |
| Event | medications | `MedicationEvent` | `medication_events` | adherence |
| Timeline | medical_records/analytics | `HealthTimelineEvent` | `health_timeline` | projection |
| Appointment | appointments | `Appointment` | `appointments` | visits |
| Consent | medical_records (consent svc) | `Consent` | `consents` | authorization |
| Facility | facilities | `Facility` | `facilities` | institutions |
| Doctor | doctors | `Doctor` | `doctors` | professionals |
| Staff | facilities/doctors | `HealthcareStaff` | `healthcare_staff` | staff |
| Donor | blood_network | `BloodDonor` | `blood_donors` | donors |
| Blood request | blood_network | `BloodRequest` | `blood_requests` | requests |
| Blood match | blood_network | `BloodMatch` | `blood_matches` | matching |
| Donation event | blood_network | `BloodDonationEvent` | `blood_donation_events` | history |
| Emergency request | emergencies | `EmergencyRequest` | `emergency_requests` | SOS |
| Responder | emergencies | `EmergencyResponder` | `emergency_responders` | responses |
| Override grant | emergencies | `EmergencyAccessGrant` | `emergency_access_grants` | bounded override |
| Campaign | donations | `Campaign` | `campaigns` | fundraising |
| Donation | donations | `Donation` | `donations` | contributions |
| Payment txn | donations | `PaymentTransaction` | `payment_transactions` | provider |
| Refund | donations | `Refund` | `refunds` | returns |
| Post/comment/reaction/report | community | `CommunityPost/Comment/Reaction/Report` | per table | community |
| Conversation/participant/message/attachment | doctors (chat) | `Conversation/.../MessageAttachment` | per table | chat |
| Notification/pref | notifications | `Notification`, `NotificationPreference` | per table | inbox |
| Education category/content | community/medical_records | `EducationCategory`, `EducationalContent` | per table | content |
| Organization/member | accounts/donations | `Organization`, `OrganizationMember` | per table | orgs |
| Analytics snapshot | analytics | `AnalyticsSnapshot` | `analytics_snapshots` | aggregates |
| Audit log | audit | `AuditLog` | `audit_logs` | trail |

**Findings:** (1) `hospitals` app/table merges into `facilities` — the app list
will add `facilities` (already scaffolded) and re-home hospital logic; keep app
name `facilities`. (2) `healthcare_staff` needs a new model. (3) A custom
`User` model (`AUTH_USER_MODEL`) is required for roles/status/profile pointer —
see migration strategy §27 (core auth tables already exist; this is a critical
implementation note). (4) Chat/education/organization models need new apps or
placement per mapping. No implementation performed in this stage.

---

## 27. Migration Strategy

- Migrations are the only structural change path (no raw SQL for dev; README
  infra note). Version controlled alongside code.
- Deterministic, reviewable; each migration small; indexes/check constraints in
  the same migration as their tables.
- Destructive migrations (drops, data loss) require explicit owner approval and
  are never auto-generated in this stage.
- Data migrations for: seeding `roles`/`permissions`/`record_categories`/
  `symptom_types`/`education_categories`; backfilling `uid` where tables already
  carry data; consent/status backfill.
- **Critical: custom user model.** Django core migrations (`auth_*`) are already
  applied in `sickle_cell` with the default `User`. Introducing
  `AUTH_USER_MODEL = "accounts.User"` requires one of:
  (a) recreate `sickle_cell` (and test/staging DBs, empty, safe) then migrate
  fresh; or
  (b) a documented zero-data conversion. RECOMMEND (a) at implementation time.
- Migrations run in CI for test database (`test_sickle_cell`); staging applied
  only after dev green.

---

## 28. Database Environment Strategy

| Env | DB | Server | Purpose | Notes |
|---|---|---|---|---|
| Development | `sickle_cell` | System PG, port 5432 | daily work, seeded fixtures | role `sw_db_user`; old `sw_db` on 5433 retained (not used by app) |
| Testing | `test_sickle_cell` | same as dev | automated test runs (Django `test_` prefix), recreated per run | isolated; never production data |
| Staging | (future, env-driven) | staging server | UAT/integration; schema parity with dev | only synthetic/anonymized data |
| Production | (future, env-driven) | production server | real users | no dev credentials; secrets via env (infra §3.10) |

- All environments PostgreSQL (never SQLite).
- Tests use synthetic data; no real patient information in test/staging
  (healthcare-safety + SR privacy).
- Separation enforced at connection-string level (settings env-driven).

---

## 29. Open Design Decisions

| # | Decision | Default / note |
|---|---|---|
| DBD-1 | Custom `User` against existing core tables | Recreate `sickle_cell` + test/staging DBs at migration time (recommended); confirm owner approval |
| DBD-2 | `health_timeline` materialization | Materialized on write from domain events; backfill script documented; decide rebuild-on-read alternative during analytics stage |
| DBD-3 | `reports` polymorphic `target_id` | Alternative: per-target FKs `post_id`/`comment_id` with CHECK. Default: single-tab polymorphic with check — reconsider if constraint/reporting needs diverge |
| DBD-4 | Emergency override duration | 24h default, config-driven (3.3 ODD-2) |
| DBD-5 | `verification_expires_at` for doctors | Confirm whether licensure expiry enforcement is required (default: tracked, not blocking) |
| DBD-6 | Blood donor verification documents | Blood-bank attestation default (3.3 ODD-10) |
| DBD-7 | Chat/education/org app placement | Chat under `doctors`, education under `community`/`medical_records`, orgs under `accounts`+`donations` (confirm) |
| DBD-8 | Citext vs lower() index on email | Default: `citext` if extension available, else functional lower index |
| DBD-9 | Audit retention | Rolling + immutable compliance partition (3.3 ODD-9) |
| DBD-10 | Soft-delete partial-unique email | Active-record uniqueness via partial index on non-deleted rows |

---

## Traceability (database → requirements)

Covered in `database-design-review.md` §6. Major anchors:

- FR-AUTH → `users`, `roles/permissions`, `security_events`, `token_denylist`
- FR-PAT/FR-SYM → `patients`, `patient_preferences`, `symptoms`, `symptom_types`
- FR-DOC/BR-001 → `doctors`, `healthcare_staff`, `facilities`, `verification_documents`
- FR-MEDREC/consent → `consents`, `medical_records*`, `clinical_encounters`, `medical_record_links`
- FR-MED → `medications*`
- FR-APP → `appointments`
- FR-BLD/BR-005/006 → `blood_donors`, `blood_requests`, `blood_matches`, `blood_donation_events`
- FR-EMG/BR-009 → `emergency_requests`, `emergency_responders`, `emergency_access_grants`
- FR-CAM/PAY/BR-007/008 → `campaigns`, `donations`, `payment_transactions`, `refunds`
- FR-COM → `community_posts`, `comments`, `reactions`, `reports`
- FR-EDU → `educational_content`, `education_categories`
- FR-NOT → `notifications`, `notification_preferences`
- FR-AI → `analytics_snapshots` + de-identified joins
- BR-012/NFR-SEC → `audit_logs`, `security_events`
- 3.3 roles/permissions → `roles`, `permissions`, `role_permissions`, `user_roles`, `user_permissions`, `consents`, `emergency_access_grants`