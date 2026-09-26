# 3.4 Database / ERD Design — Review

> Stage 3.4 audit report (re-issued). Generated after updating `database-design.md`
> and the ERD set in `erd/`. This revision reflects the owner decision to move the
> application database to `sickle_cell` on system PostgreSQL (port 5432).
> **Design only** — no project models, no project migrations, no project DDL.
> Gate decision at the end.

---

## 1. Executive Summary

The database design for Sickler's Warriors has been re-derived from the
approved requirements (Stage 2), module architecture (3.2), roles & permissions
(3.3), healthcare safety, privacy and business rules. The existing design was a
sound, well-normalized draft that lacked the Stage 3.3 authorization model and
a few workflow entities. This revision:

- Adds the full **role/permission/consent/account-status** relational model
  (approving 3.3), closing the single-`users.role` gap.
- Introduces **public UUID `uid`s** separate from internal `bigint` PKs to stop
  predictable resource enumeration on sensitive data.
- Splits the "hospitals" concept into a unified **`facilities`** entity and adds
  **`healthcare_staff`**, **`organizations`, `organization_members`,
  `emergency_access_grants`, `refunds`, `security_events`, `token_denylist`,
  `clinical_encounters`, `analytics_snapshots`**.
- Keeps medical model normalized (no mega-record-table), adds
  record categories, files/attachments storage, and a materialized
  health-timeline projection.
- Splits the ERD into an overall view + six domain views (all Mermaid).
- Moves the application database to **`sickle_cell`** on system PostgreSQL
  **port 5432** (owner decision) while leaving the previous `sw_db*` dev cluster
  on port 5433 untouched ("usiitoe").

Verified: `sickle_cell` present on `127.0.0.1:5432` with 10 Django core tables
(`auth_*`, `admin`, `contenttypes`, `sessions`, `django_migrations`), role
`sw_db_user`, app connected through Django settings (DB_PORT=5432).
**No new server, no SQLite.**

---

## 2. Existing Database Assessment

| Area | State found | Assessment |
|---|---|---|
| Server | System PG 18 on port **5432** (`/var/lib/postgresql/18/main`); legacy dev cluster on 5433 retained | App DB verified on 5432 |
| Databases | `sickle_cell` (app DB) on 5432; `sw_db`/`sw_db_test`/`sw_db_staging` remain on 5433 | App DB active; legacy DBs untouched (owner decision) |
| `sickle_cell` state | 10 Django core tables (`auth_*`, `admin`, `contenttypes`, `sessions`, `django_migrations`) | Clean scaffold; **no project tables/migrations** |
| Identity | Default Django `auth_user` | Works but cannot express roles/status/verification; must be replaced by custom `User` (see Critical #1) |
| Roles/permissions | None in DB (only `auth_group`, `auth_permission` unused) | Gap — designed in §5/§7 |
| Consent | None in DB | Designed (§9) |
| Audit | App scaffold only | Designed (§20) |
| ERD draft | Good base; `users.role` single column; `hospitals` entity | Conflicts with 3.3; redesigned |
| Dev script | `scripts/postgres.sh` computes `DATA_DIR` as `scripts/data`, but cluster lives in `infrastructure/postgres/data` | **Bug** — script cannot start its own cluster (minor issue #3); app DB now managed via `scripts/setup_system_pg.sh` |

---

## 3. New/Updated Database Design

Delivered in `database-design.md` per the 29 mandated sections:

1. Database Architecture · 2. Technology · 3. Data Domains · 4. Identity Model ·
5. Role & Permission Data Model · 6. Patient · 7. Healthcare · 8. Medical ·
9. Consent · 10. Appointments · 11. Blood Donation · 12. Emergency ·
13. Financial Donation & Payment · 14. Community · 15. Communication ·
16. Notifications · 17. Education · 18. Organization · 19. Analytics ·
20. Audit & Security · 21. Primary Key Strategy · 22. Constraints · 23. Indexing ·
24. Soft Delete & Retention · 25. Privacy Classification · 26. Django Model
Mapping · 27. Migration Strategy · 28. Environment Strategy · 29. Open Decisions.

**Table count:** ~40 tables across 16 domains, each justified (why it exists /
which requirement / module / owner / access / sensitivity — §5–§20 of the doc).

---

## 4. ERD Assessment

7 files in `erd/`:

- `erd.md` (index) · `overall-erd.md` (high-level)
- `identity-access-erd.md` · `patient-medical-erd.md` · `blood-emergency-erd.md`
  · `donations-payments-erd.md` · `community-communication-erd.md` ·
  `notifications-audit-erd.md`

Each shows entities, PK/UK/FK, cardinality and key CHECK constraints in
Mermaid `erDiagram`. Cardinality is explicit for every important relationship
(1:1 profiles, 1:N patient→records/consents/events, M:N roles↔permissions,
users↔roles, organizations↔members; 1:N campaign→donations→transactions).

**Remaining ERD caveats:** `reports` uses polymorphic `target_id`
(design decision DBD-3); `health_timeline` is a derived projection, not a
source of truth.

---

## 5. Django Model Mapping

Complete mapping in `database-design.md` §26 (entity → app → model → table →
responsibility). Highlights:

- `accounts`: custom `User`, `Role`, `Permission`, `RolePermission`,
  `UserRole`, `UserPermissionOverride`, `VerificationDocument`, `SecurityEvent`,
  `TokenDenylistEntry`.
- `patients`: `Patient`, `CaregiverRelationship`, `PatientPreference`, `Symptom`.
- `medical_records`: record machinery + **`Consent`** (consent service).
- `medications`/`appointments`/`blood_network`/`emergencies`/`donations`/
  `community`/`notifications`/`analytics`/`audit`: per-table models.
- `facilities`: `Facility`, `HealthcareStaff` (hospital logic merged here —
  `hospitals` app table absorbed).
- Chat (`doctors`), education (`community`/`medical_records`), organizations
  (`accounts`/`donations`): placement proposed (confirm DBD-7).

Gaps found: no `HealthCareStaff`, `Organization*`, `Refund`,
`AnalyticsSnapshot`, `SecurityEvent`, `TokenDenylistEntry`, `ClinicalEncounter`
models exist yet — all mapped for implementation.

---

## 6. Requirements Traceability

| Requirement | Domain | Entity | Relationship | Constraint | Security/Privacy rule |
|---|---|---|---|---|---|
| FR-AUTH-001..006 | Identity | `users`, `user_roles`, `security_events` | role M2M | UNIQUE email/phone, account_status CHECK | hashed passwords, MFA, denylist |
| FR-AUTH-005 / 3.3 | RBAC | `roles`, `permissions`, `role_permissions`, `user_roles`, `user_permissions` | M:N | UNIQUE codes, effect CHECK(ALLOW/DENY) | server-side resolution; SUP-only `role_assign` |
| FR-MEDREC-001..006, BR-002/003/004 | Medical/Consent | `consents`, `medical_records*` | patient 1:N, consent M:N | status CHECK, JSONB scope | consent-gated, expiry/revocation, audit |
| FR-DOC-001..005, BR-001 | Healthcare | `doctors`, `healthcare_staff`, `facilities`, `verification_documents` | 1:1 user, facility 1:N | status CHECK | verified-only activation; secure doc storage |
| FR-BLD-001..010, BR-005/006 | Blood | `blood_donors`, `blood_requests`, `blood_matches`, `blood_donation_events` | patient 1:N requests, N:M matches | blood_group CHECK, statuses | no donor contact exposure; no donor PII in requests |
| FR-EMG-001..006, BR-009 | Emergency | `emergency_requests`, `emergency_responders`, `emergency_access_grants` | requester 1:N, responders N:1 | severity/status CHECK | bounded override + audit; spam controls |
| FR-CAM/PAY, BR-007/008 | Donations | `campaigns`, `donations`, `payment_transactions`, `refunds` | org 1:N cmp, cmp 1:N don, don 1:N txn | unique refs, amount>0 | server-side verify; redeact payload |
| FR-COM-001..005 | Community | `community_posts`, `comments`, `reactions`, `reports` | post 1:N | UNIQUE reaction | moderator-only moderation |
| FR-NOT-001..006 | Notifications | `notifications`, `notification_preferences` | user 1:N | UNIQUE pref, delivery_key | emergency unfilterable |
| FR-EDU-001..004 | Education | `educational_content`, `education_categories` | category 1:N | status CHECK | review workflow |
| BR-012, NFR-SEC-004 | Audit | `audit_logs`, `security_events` | actor nullable FK | append-only | no PHI in logs |

All 12 business rules (BR-001..BR-012) and all module FRs have database support.
No requirements were invented.

---

## 7. Privacy & Security Assessment

- **Classification** defined (Public / Internal / Private / Highly Sensitive) with
  per-class protection (§25) — records/consents/payment payloads/mfa/auth highest.
- **Minimization:** redacted payment payload; aggregate-only analytics; audit
  logs store references, not content.
- **Exposure:** public UUIDs for all API-exposed resources; internal PKs never
  in URLs (§21).
- **Consent enforcement:** data model makes consent joinable at query time;
  revocation immediate (status flip + clock checks).
- **Emergency** bounded and auditable; no unconditional bypass.
- **Recommendation carried into implementation:** field-level encryption for
  `medical_record_files`/`message_attachments`/`mfa_secret`; TLS +
  restricted CORS (settings); admin MFA.

---

## 8. Critical Issues

| # | Issue | Recommendation |
|---|---|---|
| C1 | Custom `User` vs applied default-auth migrations | `AUTH_USER_MODEL` cannot be introduced without rework; **recreate `sickle_cell`** (and test/staging DBs) at implementation start (safe — no project data) rather than convert in place |
| C2 | `hospitals` entity merges into `facilities`; `users` needs profile-pointer columns | Execute as planned in implementation; keep `users` slim, profiles 1:1 |
| C3 | No authorization enforcement exists anywhere yet | The DB model supports it; enforcement depends on API layer (3.5+) — flag: don't launch without it |
| C4 | Dev script `postgres.sh` `DATA_DIR` mismatch | Fix script or retire it (legacy 5433 cluster); app DB managed via `scripts/setup_system_pg.sh` (infra, not schema) |
| C5 | App DB on system PG (5432) needs admin (sudo) for DB/role lifecycle | Old 5433 cluster was self-service (no sudo). Define owner/admin workflow for 5432 DB operations; document who runs `setup_system_pg.sh` |

---

## 9. Minor Issues

| # | Issue |
|---|---|
| M1 | `reports.target_id` polymorphic — acceptable, but prefer explicit FKs if reporting needs grow (DBD-3) |
| M2 | `health_timeline` is materialized — must define rebuild/backfill job (DBD-2) |
| M3 | `citext` dependency — falls back to functional lower-index if extension unavailable (DBD-8) |
| M4 | `security_events` vs `audit_logs` overlap risk — keep semantics strict (auth telemetry vs operational trail) |
| M5 | `message_attachments`/`medical_record_files` need an object-storage key scheme + encryption policy doc during implementation |

---

## 10. Design Decisions

- Internal `bigint` PK + public UUID (`uid`) everywhere exposed (§21).
- Multi-role M2M; `user_permissions` reserved for audited overrides; no
  permission strings buried in app tables (§5).
- Unified `facilities`; `hospitals` dissolved (§7).
- Consent stores permission-scope JSONB referencing catalog codes (§9).
- Emergency override as first-class bounded, time-limited grant (§12).
- Payments/transactions immutable; refunds via workflow (§13).
- Analytics aggregates only (§19).
- Soft delete only where legal/audit value exists; financial/clinical/
  audit/event data immutable (§24).

---

## 11. Open Questions

1. Owner approval to recreate `sickle_cell` (and test/staging DBs) for custom
   `User` (C1).
2. Confirm chat/education/org app placement (DBD-7).
3. Confirm verification-expiry enforcement for doctors (DBD-5).
4. Confirm emergency override duration default 24h (DBD-4 / 3.3 ODD-2).
5. Confirm citext acceptable (DBD-8).
6. Confirm audit retention split (DBD-9 / 3.3 ODD-9).
7. Confirm disposition of the retained 5433 cluster (`sw_db*`) — keep as
   offline backup or retire once the app is fully on `sickle_cell`.

---

## 12. Recommended Implementation Changes (for later stages)

1. Set `AUTH_USER_MODEL = "accounts.User"` and (re)create `sickle_cell` (empty,
   safe) + test/staging DBs; migrate from scratch; seed `roles`/`permissions`/
   catalog data.
2. Implement models per §26 mapping; every table carries `id` PK + `uid` +
   timestamps; CHECK constraints added via migrations (Django does not emit
   `CheckConstraint` automatically for `choices`).
3. Encrypt sensitive payload/secret columns at rest; store file keys not URLs.
4. Add partial unique indexes for active-record uniqueness.
5. Wire audit hooks into authorization/permission/consent paths.
6. Materialize `health_timeline` with a documented backfill.
7. Fix `scripts/postgres.sh` data-dir path (or retire it; C4).
8. Add DAO/repository layer mapping object-level authorization to queries
   (owner/consent/facility filters) — foundation for 3.5 API design.

---

## 13. SDLC Gate Decision

# **PASS WITH MINOR REVISIONS**

Execution order before/at implementation (not now): resolve C1 (DB recreates +
custom user), C2, C4, C5, and the open questions 1–7. All are implementation-phase
actions; the database design itself is complete, consistent with Stage 2/3.1/3.2
and the approved 3.3 authorization model, re-issued for the `sickle_cell`/5432
environment (owner decision), and audited with no hidden issues.

> STOP — no further stage started. `3.5 API Design` begins only after project
> owner approval of this design.