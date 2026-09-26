# 3.5 API Design — Review

> Stage 3.5 audit report. Generated after authoring `api-design.md` and
> `api-endpoint-matrix.md` against the approved requirements (Stage 2), module
> architecture (3.2), roles & permissions (3.3) and database design (3.4).
> **Design only** — no serializers, no API views, no URL mappings, no
> implementations created. Gate decision at the end.

---

## 1. Executive Summary

The API design for Sickler's Warriors is complete and consistent with the
approved Stage 2 requirements, the 3.3 role/permission catalog (roles
SUP…ORG, conditions C2–C17) and the 3.4 `sickle_cell` database. The backend
today is a **pure scaffold** (15 Django apps with stub models, no
`serializers.py`, no app `urls.py`; only the Django admin route in
`config/urls.py`). There is therefore no existing API surface to preserve, so
Stage 3.5 was authored fresh from requirements.

Key properties of the proposed API:

- **Base URL** `/api/v1/`, path versioning; JWT access+refresh with rotation and
  denylist (`simplejwt`), TOTP MFA optional; OAuth2 flagged for real-world Learn
  integration (AD-11).
- **Envelope** `{data, meta}` / `{error:{code,message,details,correlation_id}}`;
  DRF `PageNumberPagination` (page_size 1..100, default 20); consistent error
  codes (`AUTH_*`, `PERMISSION_*`, `CONSENT_*`, `VALIDATION_*`, enum-based
  `INTERNAL_*`).
- **Authorization & consent enforcement** mapped against 3.3 codes (C2 consent ·
  C3 object set · C5 verified professional · C6 verification workflow · C7 facility
  context · C8 eligible donors · C9 own match · C10 emergency override · C13 chat
  participants · C14 self/authorized patient · C15 clinical relationship+consent ·
  C16 self-entry · C17 SUP-only privileged assign) with an explicit **object-level
  authorization (IDOR prevention) layer**.
- **Robustness**: idempotency keys (donations, payments, emergency, appointments,
  dose logs), phased rate limiting, signed payment webhooks, private file uploads
  with pre-signed access, OpenAPI via `drf-spectacular` with an explicit
  documentation strategy, and immutable status-transition guards for clinical
  workflows (appointments SCHEDULED→CONFIRMED→COMPLETED/NO_SHOW/MISSED;
  emergency CREATED→VALIDATING→ACTIVE→RESPONDING→ESCALATED→RESOLVED).
- **Consumption by Flutter** documented (§41 — tokens, Dio, image/file upload,
  push, offline) and a Django mapping (§40 — router/response/filter/annotation
  points). API testing requirements are captured for the test stage (§42 — not
  implemented now).

The owner decision recorded in the prompt's Stage 3.5 header still references
the legacy `sw_db` database and port 5433 for the backend runtime environment;
**the current application database is `sickle_cell` on system PostgreSQL
port 5432** (per re-issued 3.4). The API design is environment-agnostic
(settings-driven), so this does not block the design — it is flagged below
(M5) so the runtime documentation is corrected.

---

## 2. Existing API Assessment

| Area | State found | Assessment |
|---|---|---|
| API app code | None — 15 Django apps are scaffolds (stub `models.py`/`views.py`, no serializers, no app `urls.py`) | No existing API surface to preserve or break |
| URL config | `config/urls.py` only serves Django admin | Routed via `/admin/` (default path, not exposed in API design) |
| Auth | Django session via admin only | To be replaced by JWT + MFA per §3; session only for admin/Django internals |
| DRF/REST stack | Not installed | Add `djangorestframework`, `djangorestframework-simplejwt`, `drf-spectacular`, `django-cors-headers` (already pin-listed + installed in venv for a scaffold check) |
| Permissions | None exposed anywhere | Designed via 3.3 codes (see §3 below) |
| Payments | None — no provider, no webhook endpoints | Webhook design drafted (§17/§31), provider list default M-Pesa/AirtelMoney/TigoPesa/ClickPesa/Selcom (AD-5) |
| Rate limiting | None | Designed (§29) with calibration note (AD-9) |
| Versioning | None | `/api/v1/` baseline established (§2/§34) |

Conclusion: the API is a **greenfield design**; no migrations of existing
endpoints/contracts are required.

---

## 3. API Design Coverage

Delivered in `api-design.md` per the mandated sections:

1. API Architecture · 2. Versioning · 3. Authentication · 4. User/Profile ·
5. Role & Permission · 6. Patient · 7. Doctor · 8. Healthcare Facility ·
9. Caregiver · 10. Consent · 11. Medical Record · 12. Medication ·
13. Appointment · 14. Blood Donation · 15. Emergency · 16. Financial Donation ·
17. Payment · 18. Community · 19. Chat · 20. Education · 21. Notification ·
22. Administration · 23. Search & Filtering · 24. Pagination · 25. Response
Format · 26. Error Handling · 27. Security · 28. Object-Level Authorization
(IDOR) · 29. Rate Limiting · 30. Idempotency · 31. Webhooks · 32. File
Uploads · 33. OpenAPI Strategy · 34. Versioning & Deprecation ·
35. Requirements Traceability · 36. Open Design Decisions (AD-1..AD-11) ·
37. Flow Diagrams (auth, medical record, blood request, emergency, payment) ·
38. Security Threat Review · 39. Full Requirements → API Traceability ·
40. Django Mapping · 41. Flutter Consumption · 42. Testing Requirements.

**Endpoint matrix**: full inventory in `api-endpoint-matrix.md` (21 modules,
each row: Module | Method | Endpoint | Auth | Permission | Consent | Object
Rule | Audit | Notes). All FR/BR groups from Stage 2 are reachable; nothing
invented.

---

## 4. Authentication & Authorization Assessment

- **AuthN**: register (role-gated), login, refresh (rotation + reuse
  detection), logout/denylist, password reset/change, email & phone
  verification, TOTP MFA setup/enable/disable, session management. Rate limits
  applied per endpoint (§29).
- **AuthZ**: resolved **at the code level** from the 3.3 catalog (permission
  strings are the same codes used in the DB/seed data: `users.role_assign`,
  `medical_records.view`, `blood_requests.verify`, `emergency_requests.*`,
  `community.moderate`, `education.publish/review`, `doctors.verify`, etc.).
- **Consent & conditions**: run-time conditions C2–C17 embedded in the per-
  endpoint column of the matrix; consent evaluation is a service filter, not an
  ad-hoc check.
- **Emergency**: bounded override (C10) with `emergency_access_grants`,
  auditable, time-limited; no unconditional bypass.
- **IDOR layer**: two distinct strategies (sensitive → 403 + audit; public
  directory → 404) with AD-6 documenting per-resource choice.
- **Gaps**: verification workflow for patient-created records (C16) is
  documented as an open point (AD-12); admin/superuser endpoints assume the
  (separately controlled) admin MFA policy from 3.8.

---

## 5. Security & Privacy Assessment

- **Transport**: TLS only; CORS restricted; no PII in URL paths (public UUIDs,
  internal PKs never exposed).
- **Data minimization**: redacted payment payloads (PCI), no donor PII in
  public blood requests, sanitized push previews, aggregate-only analytics.
- **Threat review** (§38) covers enumeration, IDOR, spoofing, tampering,
  replay, DoS, webhook forgery, upload abuse, privilege escalation — each with
  a mitigation mapped to a design section.
- **Observation carried into implementation**: **field-level encryption** for
  medical files/message attachments/MFA secrets and webhook-signature key
  storage in the secrets manager (not code); this mirrors 3.4's C-series
  recommendations and must be honored.

---

## 6. Django Mapping

- **Stack**: `djangorestframework` + `djangorestframework-simplejwt` +
  `drf-spectacular` + `django-cors-headers` (documented, not yet installed/
  configured — that is implementation work).
- **Structure**: per-app routers, viewset conventions, `perform_create`
  permission hooks, `get_queryset` object-scoping by owner/consent/facility,
  filter backends, custom permission classes wired to the 3.3 catalog, response
  envelope rendering, error handler mapping codes.
- The design explicitly maps each API group to its 3.4 app/model so
  implementation has a 1:1 route→model→authorization path.

---

## 7. Requirements Traceability

All 12 business rules (BR-001..BR-012), all FR modules (auth, patients,
medical records, medications, appointments, symptoms, blood, emergency,
doctors, campaigns, payments, community, education, notifications,
ai_assistant) and the security/performance NFRs are traceable to API groups in
§35/§39. No requirement was dropped; the **AI assistant** group was the only one
missing a dedicated endpoint set in the draft and is added via AD-2 as an open
design decision.

---

## 8. Critical Issues (for implementation)

| # | Issue | Recommendation |
|---|---|---|
| C1 | No authorization/consent enforcement exists yet (backend is scaffold) | Implement the 3.3-catalog permission classes + object-scoping DAO before any public exposure; no feature may ship without the code-level enforcer from §28 |
| C2 | `AUTH_USER_MODEL` change requires recreating `sickle_cell` (carried from 3.4 C1) | At implementation start, recreate `sickle_cell` (+ test/staging), migrate from scratch, seed roles/permissions/catalog before registering any API route |
| C3 | Signal/consent and payment webhook secrets must not live in code | Inject via environment/secrets manager; signing keys rotated; webhook verification must be fail-closed |
| C4 | Emergency/clinical status transitions must be enforced server-side, not client-side | Central transition validator (as documented in §13/§15) with audit on every mutation |

---

## 9. Minor Issues

| # | Issue | Recommendation |
|---|---|---|
| M1 | Err-code and envelope consistency: there are places where 401 vs 422 semantics are easy to blur on validation of consents/scope | Decide once in the error handler; document in API reference |
| M2 | Chat realtime is polling-based (AD-4) | Acceptable for launch; confirm in 3.6/3.7 that mobile UX tolerates polling latency, else add websockets early |
| M3 | `sw_db`/5433 references still appear in the 3.5 prompt header (owner env note) | Correct runtime-doc references to `sickle_cell`/5432; the design is env-agnostic so no rework required |
| M4 | Admin analytics can leak risk if raw medical data ever lands in a query | Enforce aggregate-only via `analytics_snapshots`/views, as designed (§22, AD-7) |
| M5 | File routes use pre-signed access URLs; object-store key scheme is a dependency of 3.6+ storage work | Define bucket/key/encryption scheme before implementation of §32 |

---

## 10. Design Decisions

- Base URL + query/path-param conventions fixed at `/api/v1/` (§1/§2/§23/§24).
- JWT access+refresh with rotation; denylist on logout (AD-1).
- Consent evaluated server-side via service filters, with `{data,meta}` envelope
  carrying `consent` state where relevant (§10/§11).
- Public UUIDs for API-exposed resources; internal bigint PKs never in URLs
  (aligned with 3.4 §21).
- Status-transition guard for clinical workflows (appointments/emergency)
  enforced in a validator, audited.
- Idempotency keys on donation/payment/emergency/appointment/dose-log writes.
- Payment webhooks signed + idempotent; provider set handled as configuration.
- Aggregate-only admin analytics; no raw PII (AD-7).

---

## 11. Open Questions (defer decisions to implementation)

1. AD-1 — JWT access+refresh vs cookies for a single-client rollout.
2. AD-2 — AI assistant endpoint shape/location (`ai_assistant` app).
3. AD-3 — consent granularity: general scope JSONB now, per-record links if needed.
4. AD-4 — chat realtime: polling now vs websockets for 3.6 UX.
5. AD-5 — payment providers list & per-provider configuration keys.
6. AD-6 — IDOR masking policy per resource (403+audit vs 404).
7. AD-7 — analytics aggregates only (no raw PII query surface).
8. AD-9 — rate-limit values: calibrate after load tests.
9. AD-10 — FCM push infra details.
10. Reconfirm the stale `sw_db*`/5433 runtime references (M3) — update docs to
    `sickle_cell`/5432.
11. Confirm OAuth2 for real-world Learn/Sofr exchange integration (AD-11).

---

## 12. Recommended Implementation Changes (for later stages)

1. Install/configure DRF stack; set `AUTH_USER_MODEL` and recreate `sickle_cell`
   (per 3.4 C1); seed roles/permissions (3.3) and catalog data before routing.
2. Implement the object-scoping DAO / permission classes first; every viewset
   uses `get_queryset` scoping by owner/consent/facility (§28).
3. Wire idempotency middleware and the transition validator before clinical
   write endpoints go live (§13/§15/§30).
4. Stand up payment webhook verification with env-injected keys, fail-closed
   verification, and idempotent replay protection (§31).
5. Envelope renderer + central error handler with the M1 semantics decided.
6. OpenAPI schema (drf-spectacular) generated as the single API reference and
   kept in sync by CI.
7. Private file upload with pre-signed access (§32) and the object-store key/
   encryption scheme defined with 3.6 storage work.
8. Load-test to calibrate rate limits (AD-9) before production.

---

## 13. SDLC Gate Decision

# **PASS WITH MINOR REVISIONS**

The API design is complete, internally consistent, consistent with Stages 2/3.1/
3.2/3.3/3.4 and the `sickle_cell`/5432 environment, greenfield-safe (nothing to
migrate), and fully mapped to implementation via the endpoint matrix + Django
mapping. Ten minor/administrative corrections (M1–M5, decisions AD-1..AD-11,
and the stale runtime-doc references) are implementation-time actions and do
not block this stage.

> STOP — no further stage started. `3.6 Mobile UI/UX Design` begins only after
> project owner approval of this design. Implementation (serializers, views,
> routes, code) stays outside this stage's scope.