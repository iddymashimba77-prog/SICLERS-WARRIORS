# Stage 3 System Design Verification Report

**Project:** Sickler's Warriors
**Date:** 2026-09-10
**Type:** Stage 3 Design Verification Audit (READ-ONLY)
**Auditor:** opencode (automated verification)

---

## 1. Executive Summary

Stage 3 System Design documents (10 files + ERD) are all present and contain substantive content. The design architecture is sound at a conceptual level: modular client-server, layered application architecture, consent-based medical access, consent-scoped privacy model, and safety-layered AI. However, the audit reveals **significant gaps between design intent and actual implementation readiness**.

**Key findings:**
- All 10 design docs + ERD exist and have content
- 12 requirements docs exist and cover 18 of 24 areas well
- **0 of 15 Django apps have any real code** — all are `startapp` stubs
- **Flutter app is ~3% complete** — 1 form, 1 dashboard, 11 placeholders, zero API integration
- **ERD is missing 6 tables** that are defined in database-design.md
- **No Django apps have models, migrations, views, or tests**
- **No API routes configured** (only `/admin/`)
- PostgreSQL connection works, but `SECRET_KEY` is hardcoded insecure
- Database environment separation is properly configured

**Verdict: PASS WITH MINOR REVISIONS** — The design documents are internally consistent and cover the major requirements. The gaps identified are design-level omissions (missing ERD tables, missing API endpoints, missing permission-to-role mapping) that can be corrected before implementation begins. No architectural contradictions that would block Stage 4.

---

## 2. Requirements → Design Traceability

### Coverage Matrix

| Requirement Area | Requirement Exists | Design Exists | Foundation Exists | Consistent | Gap |
|---|---|---|---|---|---|
| Authentication | ✅ FR-AUTH (6) | ✅ 3.8 Security | ⚠️ Django auth only | ✅ | No custom auth models |
| Patient Management | ✅ FR-PAT (4) | ✅ 3.4 ERD | ❌ No models | ✅ | — |
| Caregiver Management | ⚠️ Partial (no FR-CARE) | ✅ 3.4 ERD | ❌ No models | ✅ | No dedicated FR module |
| Doctor Management | ✅ FR-DOC (5) | ✅ 3.4 ERD | ❌ No models | ✅ | — |
| Healthcare Staff | ❌ No FR | ❌ No design | ❌ No models | ⚠️ | **MISSING** from requirements & design |
| Medical Records | ✅ FR-MEDREC (6) | ✅ 3.4 ERD | ❌ No models | ✅ | — |
| Medication | ✅ FR-MED (6) | ✅ 3.4 ERD | ❌ No models | ✅ | — |
| Appointments | ✅ FR-APP (4) | ✅ 3.4 ERD | ❌ No models | ✅ | — |
| Symptoms/Pain | ✅ FR-SYM (5) | ✅ 3.4 ERD | ❌ No models | ✅ | — |
| Health Timeline | ⚠️ Partial (no FR-HT) | ✅ 3.4 ERD (derived) | ❌ No models | ✅ | No standalone FR |
| Blood Donation | ✅ FR-BLD (10) | ✅ 3.4 ERD | ❌ No models | ✅ | — |
| Emergency | ✅ FR-EMG (6) | ✅ 3.4 ERD | ❌ No models | ✅ | — |
| Financial Donations | ✅ FR-CAM (6) | ✅ 3.4 ERD | ❌ No models | ✅ | — |
| Payments | ✅ FR-PAY (5) | ✅ 3.4 ERD | ❌ No models | ✅ | — |
| Community | ✅ FR-COM (5) | ✅ 3.4 ERD | ❌ No models | ✅ | — |
| Doctor Communication | ⚠️ Partial (UC-015 only) | ✅ 3.4 ERD | ❌ No models | ✅ | No FR module |
| Education | ✅ FR-EDU (4) | ⚠️ ERD missing `educational_content` | ❌ No models | ⚠️ | **ERD gap** |
| Notifications | ✅ FR-NOT (6) | ⚠️ ERD missing `notification_preferences` | ❌ No models | ⚠️ | **ERD gap** |
| Consent/Privacy | ⚠️ Embedded in MEDREC | ✅ 3.8 + 3.4 ERD | ❌ No models | ✅ | No standalone FR |
| Hospitals/Facilities | ❌ No FR | ⚠️ ERD missing `organizations` | ❌ No models | ⚠️ | **MISSING** FR + ERD table |
| Analytics | ⚠️ Partial (FR-AI-004) | ✅ 3.9 Special Systems | ❌ No models | ✅ | No FR-ANALYTICS module |
| AI | ✅ FR-AI (6) | ✅ 3.9 Special Systems | ❌ No models | ✅ | — |
| Administration | ⚠️ No FR-ADMIN | ✅ 3.7 Admin Web | ❌ No models | ✅ | Admin FRs scattered |
| Audit/Security | ⚠️ NFR-SEC only | ✅ 3.8 + 3.4 ERD | ❌ No models | ✅ | No FR-AUDIT module |

### Summary
- **18/24 areas** have requirements + design alignment
- **4 areas** have partial coverage (Caregiver, Health Timeline, Consent, Doctor Communication)
- **2 areas** are MISSING from requirements (Healthcare Staff, Hospitals/Facilities FR)
- **0/24 areas** have implementation foundation (all Django apps are stubs)

---

## 3. Module Architecture Verification

### 22 Design Modules vs 15 Django Apps

| Design Module | Django App | Mapping Status |
|---|---|---|
| Identity & Access | `accounts` | ✅ Mapped |
| Patient Management | `patients` | ✅ Mapped |
| Caregiver Management | `patients` (caregiver links) | ⚠️ Embedded, not separate |
| Doctor Management | `doctors` | ✅ Mapped |
| Medical Records | `medical_records` | ✅ Mapped |
| Medication Management | `medications` | ✅ Mapped |
| Appointment Management | `appointments` | ✅ Mapped |
| Pain & Symptom Tracking | `patients` / `medical_records` | ⚠️ Split across 2 apps |
| Health Timeline | `medical_records` / `analytics` | ⚠️ Split, ownership unclear |
| Blood Donation Network | `blood_network` | ✅ Mapped |
| Emergency Response | `emergencies` | ✅ Mapped |
| Financial Donations | `donations` | ✅ Mapped |
| Payment Management | `donations` (payment service) | ⚠️ Embedded |
| Community | `community` | ✅ Mapped |
| Doctor Communication | `doctors` (chat) | ⚠️ Embedded |
| Health Education | `medical_records` / `community` | ⚠️ Split, ownership unclear |
| Notifications | `notifications` | ✅ Mapped |
| Consent & Privacy | `medical_records` (consent) | ⚠️ Embedded |
| Analytics | `analytics` | ✅ Mapped |
| AI / Intelligence | `ai_assistant` | ✅ Mapped |
| Administration | `accounts` admin / `config` | ⚠️ Scattered |
| Audit & Security | `audit` | ✅ Mapped |

### Issues Flagged
- **`facilities` app** exists but has no design module equivalent — may be orphaned or under-scoped
- **Pain & Symptom Tracking** splits across `patients` and `medical_records` — ownership unclear
- **Health Timeline** splits across `medical_records` and `analytics` — aggregation strategy deferred
- **Consent** is embedded in `medical_records` — may cause that app to become oversized
- **No `organizations` table** in ERD despite `ORGANIZATION` role in permissions design

---

## 4. Django App Verification

### Status: ALL 15 APPS ARE EMPTY STUBS

| App | Real Models | Real Views | Migrations | Tests | Total Files |
|---|---|---|---|---|---|
| accounts | ❌ | ❌ | ❌ | ❌ | 8 (stub) |
| patients | ❌ | ❌ | ❌ | ❌ | 8 (stub) |
| medical_records | ❌ | ❌ | ❌ | ❌ | 8 (stub) |
| medications | ❌ | ❌ | ❌ | ❌ | 8 (stub) |
| appointments | ❌ | ❌ | ❌ | ❌ | 8 (stub) |
| doctors | ❌ | ❌ | ❌ | ❌ | 8 (stub) |
| blood_network | ❌ | ❌ | ❌ | ❌ | 8 (stub) |
| donations | ❌ | ❌ | ❌ | ❌ | 8 (stub) |
| emergencies | ❌ | ❌ | ❌ | ❌ | 8 (stub) |
| facilities | ❌ | ❌ | ❌ | ❌ | 8 (stub) |
| community | ❌ | ❌ | ❌ | ❌ | 8 (stub) |
| notifications | ❌ | ❌ | ❌ | ❌ | 8 (stub) |
| ai_assistant | ❌ | ❌ | ❌ | ❌ | 8 (stub) |
| analytics | ❌ | ❌ | ❌ | ❌ | 8 (stub) |
| audit | ❌ | ❌ | ❌ | ❌ | 8 (stub) |

**Implementation status: 0/15 apps have any real code.**
**Total models: 0. Total views: 0. Total URL routes: 1 (admin only). Total tests: 0.**

---

## 5. ERD Verification

### Tables Defined in database-design.md: 34

### Tables in ERD (erd.md): 28

### Missing from ERD (6 tables):

| Table | Defined In | Purpose |
|---|---|---|
| `user_permissions` | database-design.md (core/identity) | Role→permission mapping |
| `verification_documents` | database-design.md (core/identity) | Doctor/donor verification docs |
| `reactions` | database-design.md (community) | Post reactions |
| `reports` | database-design.md (community) | Content reports |
| `educational_content` | database-design.md (education) | Health education articles |
| `notification_preferences` | database-design.md (notifications) | User notification settings |

### ERD Missing Columns:

| Table | Missing Columns |
|---|---|
| `patients` | `address_region`, `address_city`, `notes`, `diagnosis_date`, `primary_diagnosis` |

### Missing Tables (defined in roles/design but not ERD):

| Table | Referenced By |
|---|---|
| `organizations` | campaigns FK (`org_id FK hospitals/orgs`), role-permission-design ORGANIZATION role |

### ERD Strengths:
- Core identity tables well-defined with proper FKs
- Blood network (donors→requests→matches) correct cardinality
- Emergency (requests→responders) correct
- Medical records → consent links correctly modeled
- Community (posts→comments→reports) correct hierarchy

### ERD Weaknesses:
- `health_timeline` marked as "derived/materialized" with deferred decision — not a real table
- No soft delete strategy documented (only `is_active` mentioned in database-design.md)
- No explicit index definitions in ERD (only in database-design.md notes)
- No audit trail table for medical record access (audit_logs exists but not specifically linked to medical access)

---

## 6. Role & Permission Verification

### Role ≠ Permission Model

**Design supports the model:**
- 12 roles defined (SUPER_ADMIN → ORGANIZATION)
- 20 sample permissions with `PERM-[MODULE]-[ACTION]` format
- Consent-based access: `Role + Permission + Patient Consent + Context`
- Enforcement flow documented (8-step check)

### Conceptual Test: Doctor A → Patient B Medical Record

**Flow as designed:**
1. Doctor A logged in? → YES
2. Doctor A verified? → YES
3. Has permission (view record)? → YES
4. Patient B granted access (consent active)? → **MUST BE YES**
5. Access record → YES
6. Write audit log

**Verdict: Design correctly prevents access without consent.** Role alone is insufficient.

### Gaps Found:
- **No permission-to-role mapping table** — which roles get which permissions is not documented
- **`HEALTHCARE_STAFF` role** has no defined permissions
- **`ORGANIZATION` role** has no defined permissions
- **`HOSPITAL` role** has no defined permissions
- **Emergency override policy** mentioned but not detailed ("policy-defined" only)

---

## 7. Privacy Verification

### Medical Records Private by Default: ✅ SUPPORTED

- `consents` table with `status` (active|revoked|expired)
- `medical_record_links` table with `scope`, `expires_at`, `revoked_at`
- Consent model: patient controls who sees what, for how long
- BR-002: "Medical records are private by default" — ✅ enforced by design
- BR-003: "Doctor cannot access complete medical history merely because they have an account" — ✅ enforced by consent check

### Gaps:
- No explicit data retention policy for medical records
- No "right to erasure" implementation detail (mentioned in security-architecture.md but no table/column for soft delete)
- No record-level access logging table (audit_logs exists but not specifically tied to medical record reads)

---

## 8. Healthcare Safety Verification

### AI Safety: ✅ CORRECTLY BOUNDED

- FR-AI-006: "System shall clearly communicate that AI output is not a medical diagnosis"
- BR-010: "AI must not autonomously diagnose patients"
- BR-011: "AI must not autonomously prescribe or modify medication dosage"
- Safety layer documented: Input → Safety Filter → AI Processing → Medical Safety Validation → Response
- Emergency detection: AI identifies emergency language → encourages appropriate urgent care

### Blood Matching Safety: ✅ CORRECTLY BOUNDED

- Matching engine identifies "potentially suitable donors" (FR-BLD-007)
- Final medical eligibility determination left to blood bank/qualified personnel
- No medical eligibility claims in matching algorithm

### Gaps:
- No clinical governance framework documented (who validates AI models?)
- No version control for AI safety rules
- Emergency override medical access scope is vague ("policy-defined")

---

## 9. API Verification

### API Design Coverage

| Resource | Endpoints Defined | Status |
|---|---|---|
| `/api/v1/auth` | 6 | ✅ |
| `/api/v1/patients` | 4 | ✅ |
| `/api/v1/medications` | 5 | ✅ |
| `/api/v1/appointments` | 2 | ✅ |
| `/api/v1/medical-records` | 4 | ✅ |
| `/api/v1/blood` | 6 | ✅ |
| `/api/v1/emergency` | 3 | ✅ |
| `/api/v1/campaigns/donations/payments` | 6 | ✅ |
| `/api/v1/community` | 5 | ✅ |
| `/api/v1/chat` | 2 | ✅ |
| `/api/v1/education` | 2 | ✅ |
| `/api/v1/notifications` | 2 | ✅ |
| `/api/v1/admin` | 6 | ✅ |
| `/api/v1/doctors` | ❌ | **MISSING** — no doctor endpoints |
| `/api/v1/caregivers` | ❌ | **MISSING** — no caregiver endpoints |
| `/api/v1/consents` | ❌ | **MISSING** — listed but no endpoints |
| `/api/v1/ai` | ❌ | **MISSING** — listed in resources but no endpoints |
| `/api/v1/analytics` | ❌ | **MISSING** — listed but no endpoints |
| `/api/v1/health` | ❌ | **MISSING** — referenced in infrastructure-design |
| `/api/v1/hospitals` | ❌ | **MISSING** — no hospital endpoints |

### API Implementation Status:
- **0/56 endpoints implemented** — `config/urls.py` only has `admin/`
- No `urls.py` in any app
- No `serializers.py` in any app
- No `views.py` with real code in any app

### Structural Issues:
- No file upload endpoints for medical documents
- No `PUT` methods defined (only GET/POST/PATCH/DELETE)
- No explicit rate limiting configuration
- No API versioning middleware configured

---

## 10. Flutter Architecture Verification

### Feature-First Structure: ⚠️ PARTIALLY FOLLOWED

**Folder structure IS feature-first** — 14 feature directories exist.

**But only `presentation/pages/` exists within each feature.** No:
- `data/` (repositories, data sources)
- `domain/` (entities, use cases)
- `models/` (data models)
- `services/` (API clients)
- `blocs/` or `providers/` (state management)

### Backend-Flutter Module Mapping:

| Backend App | Flutter Feature | Status |
|---|---|---|
| accounts | auth | ⚠️ Login form only |
| patients | profile | ❌ Placeholder |
| medical_records | medical | ❌ Placeholder |
| medications | medication | ❌ Placeholder |
| doctors | doctor_network | ❌ Placeholder |
| facilities | clinic | ❌ Placeholder |
| appointments | ❌ | **MISSING** — no feature |
| blood_network | blood_donation | ❌ Placeholder |
| donations | donations | ❌ Placeholder |
| community | community | ❌ Placeholder |
| emergencies | emergency | ⚠️ Minimal UI (no-op button) |
| notifications | notifications | ❌ Placeholder |
| ai_assistant | ai_assistant | ❌ Placeholder |
| analytics | ❌ | Backend-only (acceptable) |
| audit | ❌ | Backend-only (acceptable) |

### Critical Missing:
- No `appointments` feature
- No network/API integration code
- No state management
- No secure storage
- No auth token handling
- No push notification handling
- No deep linking

### Android Manifest:
- No INTERNET permission (needed for API calls)
- No ACCESS_FINE_LOCATION (needed for blood matching/emergency)
- No Firebase metadata (needed for push notifications)

---

## 11. Security Verification

### Security Layers (as designed):

| Layer | Design Document | Implementation |
|---|---|---|
| Authentication | ✅ 3.8 (JWT) | ❌ No auth system |
| Token Validation | ✅ 3.8 | ❌ No tokens |
| Role Check | ✅ 3.3 | ❌ No roles in code |
| Permission Check | ✅ 3.3 | ❌ No permissions |
| Consent Check | ✅ 3.8 | ❌ No consent |
| Business Rule Check | ✅ 2.5 | ❌ No rules |
| Resource Access | ✅ 3.8 | ❌ No access control |
| Audit Logging | ✅ 3.8 | ❌ No audit |

### Security Issues Found:

| # | Severity | Issue |
|---|---|---|
| 1 | **HIGH** | `SECRET_KEY` hardcoded in `settings.py:23` — not loaded from env |
| 2 | **HIGH** | `DEBUG = True` hardcoded — not read from `.env` |
| 3 | **MEDIUM** | `ALLOWED_HOSTS = []` — empty, blocks production |
| 4 | **MEDIUM** | `CORS_ALLOW_ALL_ORIGINS = True` — no restriction |
| 5 | **LOW** | No `DEFAULT_AUTO_FIELD` setting |
| 6 | **LOW** | No `AUTH_USER_MODEL` override (uses default Django User) |
| 7 | **INFO** | `python-dotenv` installed but not used in settings |

### No SQLite Leakage: ✅ VERIFIED
- Zero `.sqlite3` files found
- Zero `sqlite` references in any config file
- PostgreSQL is the only database engine

---

## 12. Database Environment Verification

### Environment Separation:

| Environment | Database | PostgreSQL Status | Django Config |
|---|---|---|---|
| Development | `sw_db` | ✅ Running (port 5433) | ✅ Connected |
| Test | `sw_db_test` | ✅ Exists | ⚠️ Not explicitly configured |
| Staging | `sw_db_staging` | ✅ Exists | ⚠️ Not explicitly configured |

### Django Migrations:
- **18/18 applied** (all Django built-in: admin, auth, contenttypes, sessions)
- **0 custom migrations** — no app models exist yet
- **10 tables in `sw_db`** — all Django system tables

### PostgreSQL Instance:
- Version: 18.6 (Debian)
- User: `sw_db_user`
- Port: 5433 (dev instance, no sudo required)
- Data dir: `infrastructure/postgres/data/`
- Control script: `scripts/postgres.sh`

### Issues:
- Test database (`sw_db_test`) not explicitly configured in `settings.py` — Django will use `test_sw_db` pattern by default
- Staging database (`sw_db_staging`) exists but no `.env` variant for staging
- `SECRET_KEY` and `DEBUG` not reading from `.env` despite `python-dotenv` being installed

---

## 13. Architectural Contradictions

### Checked: Requirements → System Architecture → Module Architecture → ERD → Django Apps → API → Flutter

| # | Contradiction | Severity |
|---|---|---|
| 1 | **ERD missing 6 tables** defined in database-design.md | ⚠️ MEDIUM |
| 2 | **`organizations` table** referenced in campaigns FK and ORGANIZATION role but never defined | ⚠️ MEDIUM |
| 3 | **`HEALTHCARE_STAFF` role** defined in permissions but has no Django app, no API endpoints, no ERD table | ⚠️ LOW |
| 4 | **Health Timeline** defined as module in application-architecture but has no ERD table (marked "derived") and no API endpoint | ⚠️ LOW |
| 5 | **`educational_content`** table missing from ERD despite being in database-design.md | ⚠️ MEDIUM |
| 6 | **No `/api/v1/ai` endpoints** defined despite being listed in api-design.md resources | ⚠️ LOW |
| 7 | **No `/api/v1/doctors` endpoints** despite doctor module being critical | ⚠️ MEDIUM |
| 8 | **Mobile `appointments` feature missing** despite backend `appointments` app existing | ⚠️ LOW |
| 9 | **`facilities` Django app** exists but has no design module in application-architecture.md | ⚠️ LOW |

**No CRITICAL DESIGN GAPS found** — all contradictions are at the "missing detail" level, not "architecturally broken" level.

---

## 14. Critical Gaps

| # | Gap | Impact |
|---|---|---|
| 1 | **`SECRET_KEY` hardcoded** — not from env | Security risk for any non-dev deployment |
| 2 | **`DEBUG = True` hardcoded** — not from env | Security risk for production |
| 3 | **`CORS_ALLOW_ALL_ORIGINS = True`** — no restriction | Security risk for production |
| 4 | **0/15 Django apps have models** | No implementation foundation exists |
| 5 | **0 API endpoints configured** | No API layer exists |
| 6 | **ERD missing 6 tables** from its own design document | Design inconsistency |
| 7 | **`organizations` table undefined** despite role + FK reference | Design inconsistency |

---

## 15. Minor Gaps

| # | Gap | Impact |
|---|---|---|
| 1 | Acceptance criteria: only 4/67 FRs have AC (6%) | Testing will need more work |
| 2 | Traceability matrix: only 5/67 FRs traced (7%) | Traceability incomplete |
| 3 | Use cases: only 1/25 has detailed flow (4%) | Use case docs are skeleton |
| 4 | User stories: thin coverage for Caregiver, Donor, Community, Education, Notifications, AI | Stories incomplete |
| 5 | No `requirements.txt` — dependencies only in venv | Reproducibility risk |
| 6 | No `DEFAULT_AUTO_FIELD` in settings | Minor Django config |
| 7 | No `AUTH_USER_MODEL` override | May limit role flexibility |
| 8 | AndroidManifest missing permissions (INTERNET, LOCATION) | App won't work with API |
| 9 | Flutter has no state management, networking, or storage packages | Foundation incomplete |
| 10 | No JWT token expiry durations documented | Security design gap |
| 11 | No Docker/containerization strategy | Deployment gap |
| 12 | No disaster recovery RTO/RPO targets | Operations gap |

---

## 16. Recommended Corrections

### Before Stage 4 (Implementation Planning):

| Priority | Correction |
|---|---|
| **P0** | Add 6 missing tables to `erd/erd.md`: `user_permissions`, `verification_documents`, `reactions`, `reports`, `educational_content`, `notification_preferences` |
| **P0** | Define `organizations` table in `database-design.md` and `erd/erd.md` |
| **P0** | Fix `settings.py`: load `SECRET_KEY`, `DEBUG`, `ALLOWED_HOSTS` from env vars |
| **P1** | Add missing API endpoints: `/doctors`, `/caregivers`, `/consents`, `/ai`, `/health` |
| **P1** | Add permission-to-role mapping in `role-permission-design.md` |
| **P1** | Add JWT token expiry durations in `security-architecture.md` |
| **P2** | Create `requirements.txt` from venv |
| **P2** | Add `DEFAULT_AUTO_FIELD = "django.db.models.BigAutoField"` to settings |
| **P2** | Add Android permissions to AndroidManifest (INTERNET, ACCESS_FINE_LOCATION) |
| **P2** | Add Flutter dependencies: `http`/`dio`, state management, `flutter_secure_storage` |

---

## 17. SDLC Gate Decision

### 🟡 PASS WITH MINOR REVISIONS

**Rationale:**

The Stage 3 System Design documents are **conceptually sound and internally consistent** at the architectural level. The module architecture, layered design, consent-based privacy model, and safety-bounded AI approach are all correct and well-reasoned.

However, the design has **detail-level gaps** that should be corrected before implementation:

1. ERD is missing 6 tables from its own design document
2. `organizations` table is referenced but never defined
3. API design is missing endpoints for 4 critical modules
4. Permission-to-role mapping is absent
5. Security settings are hardcoded

None of these are architectural blockers — they are "fill in the blanks" corrections. The design can proceed to Stage 4 (Implementation Planning) **after these corrections are made**.

**What must NOT happen:**
- Do NOT advance to coding before corrections
- Do NOT create new Django models until ERD gaps are fixed
- Do NOT add API routes until endpoint gaps are documented

**What CAN happen now:**
- Correct the 6 missing ERD tables
- Define the `organizations` table
- Add missing API endpoints
- Add permission-to-role mapping
- Fix settings.py environment loading

---

*End of Stage 3 System Design Verification Report*
*Generated: 2026-09-10*
