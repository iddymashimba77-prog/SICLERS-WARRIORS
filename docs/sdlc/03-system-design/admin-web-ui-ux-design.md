# 3.7 Admin Web UI/UX Design

> Stage 3.7 — System Design. The **Admin Web Panel** is a separate operational
> client of the approved `/api/v1/` backend (3.5). It serves the four approved
> administrative roles: **SUPER_ADMIN, ADMIN, VERIFICATION_OFFICER,
> MODERATOR** (3.3). **Design only** — no panel is implemented. It complements,
> never duplicates, the mobile app (patient/user-facing) and never bypasses the
> API layer.
>
> Companion deliverables: `admin-navigation.md`,
> `admin-screen-inventory.md`, `admin-component-catalog.md`,
> `admin-role-ui-matrix.md`, `admin-screen-role-matrix.md`,
> `admin-api-ui-traceability.md`, `admin-web-ui-ux-review.md`.
> This document supersedes the thin draft `admin-web-design.md` (kept for
> history).
>
> Rules inherited: **UI visibility is not security**; backend is authoritative.
> **Red is for emergency/danger/destructive only.** No invented endpoints —
> missing APIs are marked `API GAP`. No invented roles.

---

## 1. Objectives

1. **Governance**: verification, moderation, approvals — single operational
   console for SUP/ADM/VO/MOD.
2. **Least privilege**: role-scoped access; medical data only under C4 with
   reason-locked, audited access (AD-A-9).
3. **Transparency**: every consequential action auditable and traceable.
4. **Efficiency**: queue-first UI (verifications, reports, refunds) reducing
   click-count for recurring ops.
5. **Clarity**: real API-driven data always distinguished from placeholders;
   no fabricated statistics.
6. **Trust**: emergency and blood/verification workflows prioritised, safe by
   design (confirmation, no colour-only statuses).

Non-objectives: patient self-service (mobile), clinical charting (mobile),
community/education authoring for patients (mobile), *private* doctor↔patient
chat access (never in panel), direct DB/migrations, bypass of `/api/v1`.

---

## 2. Admin Users

Panel roles = approved 3.3 roles (source `admin-role-ui-matrix.md`):

| Role | Dashboard access | Modules visible | Actions | Sensitive info | Approval | Reporting | Audit visibility | Destructive actions |
|---|---|---|---|---|---|---|---|---|
| **SUPER_ADMIN** | Full platform KPI | All admin modules + security center + system settings | Everything allowed by matrix §2; role/permission assignment (**C17 exclusive**), refunds, emergency, moderation, education | PHI **only C4**, reason-locked | Co-sign for elevation/break-glass; refund thresholds | Full analytics + export | Full audit + export | Account deactivate/suspend, content remove, refund, emergency resolve (all confirmed) |
| **ADMIN** | Full ops KPI | Users, doctors, facilities, blood, emergency, campaigns, donations/payments, moderation, education, notifications, analytics, audit | Full ops; **cannot assign privileged roles**; no routine PHI | PHI C4 only, reason-locked; redacted payment payloads | Verification approvals; co-sign on refund escalation | Analytics + C4 exports | Audit view (C4 export) | Same as SUP minus privileged changes (all confirmed) |
| **VERIFICATION_OFFICER** | Verification KPIs | Doctor/facility/blood/campaign verification queues; own-scope audit; analytics (own scope, C6) | Approve/reject doctor, facility, blood, campaign; run matching | Identity/verification docs (scoped to queue) | Decisions justified, log reason; optional ADMIN co-sign | Scoped verification metrics | Own decisions only | Rejections (reason-locked) — reversible via queue re-open |
| **MODERATOR** | Moderation KPIs | Community reports/moderation only | Review, hide/restore, remove, warn, escalate | Reporter masked; reported content | None (role-appointed) | Moderation metrics (view) | Moderation actions only | Content removal (reversible = hidden-first) |

MFA is **mandatory** for all four roles at login (security architecture 3.8);
administrative sessions are short-lived with inactivity timeout (AD-A-2).

---

## 3. Information Architecture

Sections derived from approved permissions; `?` = AD-gated.

```
┌ Admin Shell ─────────────────────────────────────────────┐
│ Top bar: brand, search, bell (admin notifications), user │
│ Sidebar: Section ▸ Subsection, permission-filtered       │
└──────────────────────────────────────────────────────────┘

DASHBOARD (role KPI)
├─ Users → list, detail (+roles), verification queue-ish
├─ Patients (SUP/ADM, C4) → list, detail, health summary, timeline, consents, emergency history
├─ Doctors → registry, verification queue, detail, credentials, documents, decisions
├─ Facilities → list, detail, staff, doctors, verification
├─ Caregivers (SUP/ADM, C4) → relationships, consent scope, revocation
├─ Blood → requests (status pipeline), donors (masked), matching
├─ Emergency (SUP/ADM) → monitor, request list, case detail, escalation, timeline
├─ Donations → campaigns, donations, payments, reconciliation, refunds
├─ Appointments (?) → list/detail  [AD-A-6, API GAP]
├─ Community → reports, moderation, history
├─ Education → CMS: categories, content, drafts, review, publish, archive
├─ Notifications → broadcast, templates, delivery, prefs
├─ Reports → analytics dashboards, exports
├─ Audit → audit log explorer (read-only, filters, export)
├─ Security (SUP) → activity, sessions, alerts, lockouts
└─ Settings (SUP → ADM conditional) → platform, notification, content, emergency, donation, features
```

Grouping rule: sidebar shows **only** groups the role can operate; counts
badges for queues; a `more` never applies — hidden = hidden (403 state handled
case-by-case §36).

---

## 4. Navigation

Detailed guide in `admin-navigation.md`. Conventions:
- Sidebar sections + sub-items permission-filtered (per strategy §5).
- Top bar: global search, notification bell with unread badge, user chip (name +
  role badge + avatar) → profile menu (change password, MFA, sessions, logout).
- Breadcrumbs everywhere under a sub-menu; deep-linkable routes (React Router).
- Navigation guards: auth → session refresh → **403 panel** (message + Home) →
  404 panel (route unknown). Unauthorized ≠ hidden-only (§36).
- Emergency is **not a nav item** — emergencies appear in a live-priority
  region for SUP/ADM only.

---

## 5. Dashboard

Role-adaptive by permission set (`admin-role-ui-matrix.md` §1), not by raw role
string. Real API data only; region captions: `live` vs `demo/placeholder`
(AD-A-10; defaults to `live`, placeholders always labelled).

**SUPER_ADMIN / ADMIN kernel** — widget grid:
- KPI cards: total users, active patients, verified doctors, **pending doctor
  verifications** (queue badge), active blood requests, **active emergency
  cases** (live, severity colour+icon+text), active campaigns, donation totals
  (verified-period sum), **pending moderation**, **pending approvals**,
  system alerts.
- Trend summaries (7/30 day) using line bars; tables for top queues
  (verification, reports) with inline approve/reject.

**VERIFICATION_OFFICER** — verification hub: pending/approved/rejected counts
for doctors, facilities, blood, campaigns + due-date of disposition.

**MODERATOR** — moderation hub: open reports by category with escalation flag.

Rules: no fabricated figures; widget `Last updated 12:04` timestamp; click
widget → filtered module view; `/admin/dashboard` is the only real dashboard
endpoint today (API GAP for role-filtered KPI split — see traceability).

---

## 6. User Management

- List (`ADM-USR-001`): server-side paginated table + filters (status, role,
  verification, created range) + search; columns minimal (name, contact masked,
  role badge, account status, verification status, joined).
- Detail (`ADM-USR-002`): identity, role assignments (C17: EDIT only for SUP),
  account state, verification state, **audit history** for that user.
- Actions (`ADM-USR-003+`): activate · deactivate/suspend · restore · reset
  password (via reset flow, never shown), verify user (`users.verify` SUP/ADM/VO
  C6), and role/permission management (SUP only).
- **No medical data on this page** (general management list). Where a user is a
  patient, a guarded link to Patient panel (SUP/ADM) replaces raw PHI.
- Every action confirmed (§38); all actions audit-logged.

---

## 7. Patient Management

SUP/ADM only, C4: panel opens a **protected-resource gate** (reason selection
"audit/oversight" + justification) before any PHI loads (AD-A-9). Views:
- List (`ADM-PAT-001`): searchable, PHI-free (uid-agnostic rows: age band,
  blood group, status).
- Profile (`ADM-PAT-002`): identity + emergency contact + preferences.
- Health summary/timeline (`ADM-PAT-003`): consent-scoped read mirror of
  `/patients/me/*` C4 endpoints; **no editing clinical fields** (operational
  edits only via `patients.update` where permitted; C16 stays the author).
- Consents & access history (`ADM-PAT-004`): read-only reflection.
- Emergency history, appointments, blood requests (summary views, no PHI
  leak into list).

Permission checks at page, component, API and object levels — dark-side rule:
**frontend never shows a field the API cannot return.**

---

## 8. Doctor Verification

Major workflow (diagram in `admin-navigation.md` §7.1):

```
Doctor submits profile+documents (mobile) → PENDING_VERIFICATION
→ VO/ADM review (credentials, license, institution)
→ APPROVED (verified badge, active) | REJECTED (reason-locked)
   | REQUEST_CORRECTION (send back with checklist) | SUSPENDED (post-approval)
```

Queue screen (`ADM-DOC-001`): rows with applicant, submitted date, state, doc
count; **view documents** in-file-viewer (image/PDF), never raw download URLs
exposed beyond signed links; **decision panel** (`ADM-DOC-002`) shows: profile,
license, verification documents, institution, reviewer, verification
timestamp (once decided), rejection/correction reason, and requires a written
reason for Reject/Correct. Approve/Reject/Request-correction/Suspend all
confirmed + audited (actor, applicant, decision, reason, correlation id).

Co-sign: configurable threshold where a second approved admin must confirm a
rejection (AD-3.3 «optional ADMIN co-sign»; default off).

---

## 9. Healthcare Facility Management

- List (`ADM-FCL-001`): verified/unverified filter, region, type.
- Detail (`ADM-FCL-002`): profile, contact, location, services, **staff list**,
  linked doctors, verification status + decision action (`/admin/facilities/
  {uid}/verify`, VO/ADM).
- Facility operational data (internal) visible to SUP/ADM/VO (verify scope);
  never published contact misuse; no patient PHI here.

---

## 10. Caregiver Management

SUP/ADM (C4). List of caregiver relationships with consent scope, state
(PENDING/ACTIVE/DECLINED/REMOVED) and expiration. Detail shows scope chips and
a **Remove relationship** action (patient normally owns revocation; admin
removal is exceptional, reason-locked, audited). No PHI in the list; scope
detail only where the resolver has `consents.view` (C4).

---

## 11. Blood Management

- **Requests** (`ADM-BLD-001`): pipeline table (CREATED→VERIFIED→ACTIVE→
  FULFILLED→CLOSED; plus CANCELLED/REJECTED), filters (group, facility,
  urgency, status, date). **No donor PII surfaced** (BR-006).
- **Verification** (`ADM-BLD-002`): approve/reject with reason → Activate →
  Matching; audit.
- **Donors** (`ADM-BLD-003`): masked rows (blood group, region/radius,
  availability, donation history) — contacts never listed (BR-006); VO verify
  scope.
- **Matching** (`ADM-BLD-004`): run matcher (`blood_matches.run` A for
  SUP/ADM/VO), view candidate pairs (C9-scoped, no contact leakage), per-match
  response status, notification log.

---

## 12. Emergency Management

SUP/ADM only (C4): **live monitoring region** on dashboard + dedicated section.
- Monitor (`ADM-EMG-001`): active cases by severity (LOW/MEDIUM/HIGH/CRITICAL
  → colour+icon+text), unresolved count, response status, escalation status.
- Case list (`ADM-EMG-002`): filters severity/hospital/status/date range.
- Case detail (`ADM-EMG-003`): request details, patient info **appropriate to
  role** (C4-minimal), caregiver contact (emergency context), hospital, blood
  requirement, **timeline** (CREATED→VALIDATING→ACTIVE→RESPONDING→ESCALATED→
  RESOLVED/CANCELLED), responders, escalation history, actions
  (respond/escalate/resolve), **audit trail**.
- Resolve/Escalate/Cancel are confirmed with consequence copy; override action
  is C10-bounded and logs.

Severity is never colour-only: badge = colour + icon + text label.

---

## 13. Financial Donations

- **Campaigns** (`ADM-DON-001/002`): PENDING_VERIFICATION queue, ACTIVE,
  CLOSED, REJECTED, SUSPENDED; detail = overview (story), beneficiary, target,
  financial status (raised within verified window), transactions, **approval
  history**, audit. Approval workflow §14.
- **Donations** (`ADM-DON-003`): list + status (`INITIATED/CONFIRMED/FAILED/
  REFUNDED`), provider, timestamps, receipts (confirmed only).
- **Reconciliation** (`ADM-DON-004`): successful/failed/pending/duplicate/
  disputed; **ons auto-mark success never allowed** — only the webhook-verified
  state writes CONFIRMED (BR-008). Human-driven refunds (`donations.refund` /
  `payments.refund`, SUP/ADM) are confirmed + reason-locked + audited; ADM
  refunds over a config threshold need co-sign (AD-A-11).

---

## 14. Campaign Approval

`Pending → Review → Verify → Approve/Reject → Publish (ACTIVE)`.
Review screen shows campaign details, beneficiary, target, supporting docs,
creator, approval **status**, reviewer + timestamps, rejection reason. Decide
(approve/reject/correct) with mandatory reason for reject. `campaigns.verify`
SUP/ADM/VO; publication honours BR-007 verified-only.

---

## 15. Appointment Management

`?` — approved 3.3 gives **no appointments permission** to admin roles
(matrix §3.6 all `D` for SUP/ADM/VO/MOD). Two options (AD-A-6): (a) leave
appointments on mobile surfaces only — panel hides the section; (b) proposed
conditional `appointments.view` `C4` added to 3.3 **in a future 3.3 revision
for explicit approval — never silently**. Default = **HIDDEN / API GAP** in v1;
AD-A-6 records the decision.

---

## 16. Community Moderation

- Reports queue (`ADM-COM-001`): open reports with reporter masked, reason
  chips, escalation flag; content preview **with spoiler** (med/community
  separation).
- Decision panel (`ADM-COM-002`): hide (default, reversible) / remove
  (irreversible, strong confirm) / warn / escalate; reason-locked.
- Restore visible in history (`ADM-COM-003` moderation history incl. action,
  actor, reason).
- Actions require `community.moderate` (SUP/ADM/MOD); all logged. Hiding
  surfaces moderations as `HIDDEN` to the author (no dead UI).

---

## 17. Education Management

CMS-style: categories, articles/videos/materials, drafts, review, approval,
publishing, archiving. Lifecycle `DRAFT→REVIEW→APPROVED→PUBLISHED→ARCHIVED`
(only approved statuses). Screen `ADM-EDU-001` content list + `ADM-EDU-002`
editor + `ADM-EDU-003` review/approve; bulk archive/approve limited §26; SW/EN
content slots refeld; **unpublished drafts locked** from public.

---

## 18. Communication

**Announcements/broadcasts** only (SUP/ADM `notifications.broadcast`):
`ADM-COM-MSG-001` composer (target role, priority class incl. emergency,
scheduled send, privacy-safe preview). **No access to private doctor↔patient
chats** (`chat.*` = D for all admin roles); a permanent note on this screen
states chats are private. Communication history retained read-only.

---

## 19. Notifications

- Templates + categories (`ADM-NOT-001`): edit via safe placeholders; **no PHI
  in previews** (G4-style preview like §23 mobile).
- Delivery status / failures / scheduled (`ADM-NOT-002`): delivery log,
  resend, cancel schedule.
- User preferences read-only (except SUP override where policy allows).

---

## 20. Reports & Analytics

Aggregates only (3.5 AD-7; `analytics_snapshots`). Reports: user growth,
patient statistics, doctor verification, blood requests, donor activity,
emergency activity, campaigns, donations, education engagement, system
activity. Server-computed aggregates with date range; **no patient-identifying
fields in aggregate exports**; `analytics.export` SUP (ADM C4, VO none) — a
least-privilege export gate confirms scope; exports are audited.

---

## 21. Audit Logs

- Explorer (`ADM-AUD-001`): read-only table (actor, action, module,
  object/resource, timestamp, IP/device metadata, previous state, new state,
  result, correlation/request id). Filters: actor, module, action, object,
  time range; detail drawer (`ADM-AUD-002`).
- **Append-only** — no delete/edit affordances for any admin role
  (`audit_logs` C-series; export A/C4). Technology mirrors `security_events`/
  `audit_logs` tables.
- Audit bodies never hold PHI content (3.4 §20); the explorer links to the
  object only via authorized resolver.

---

## 22. Security Center

SUP primary (ADM conditional AD-A-7). Views: suspicious logins, failed auth,
account lockouts, privileged actions, unusual activity, active sessions
(where supported), security alerts. **No credentials/secrets ever rendered** —
values masked; detail only via admin security ops (ADD note: no such endpoint
today → API GAP, see traceability). Alerts link into audit explorer.

---

## 23. System Settings

Only approved settings (`settings` guarded): platform, notification, content
config, emergency config (severity thresholds), donation config (provider set,
refund thresholds), localization, feature flags. Elevated: any **secret-saving**
field requires re-authentication (TOTP) + audit. Config is server storage —
frontend form never bypasses backend validation. `API GAP` for most saved
settings (no endpoints yet; AD-A-8).

---

## 24. Search

Global search (`ADM-SRCH-001`) over **authorized** indexes only: users,
doctors, facilities, blood requests, campaigns, emergency cases, appointments
(if unlocked AD-A-6). Result rows respect view-permissions; zero PHI preview
for patients; **never patient-data discovery via search**. Each result deep
links to the detail page the role can actually open.

---

## 25. Tables

All lists: server-side pagination (≥ page_size 20, AD 3.5 §24), search,
filters (status/role/date/type), sorting, **column visibility** (choose),
row actions, safe bulk actions, empty/loading/error states, export where
authorized (none by default on PHI lists). Never load thousands of rows —
server pages + "load more".

---

## 26. Detail Pages

Standard structure (three-region layout):
1. Header: title, identity chips, state badge, primary actions.
2. Body tabs/sections per resource (e.g. Doctor: Overview · Verification ·
   Documents · Authorized relationships · Appointments(? ) · Audit).
3. Footer panel: audit trail tail with link to full log.

`ADM-DOC-002` (doctor), `ADM-FCL-002` (facility), `ADM-DON-002` (campaign),
`ADM-EMG-003` (emergency) follow a strict **left-to-right reading order**:
overview → operational → sensitive → audit.

---

## 27. Bulk Actions

Whitelist only and confirmed: approve selected education (`education.review`),
assign categories, archive selected content, verify selected blood requests
(VO scope), notify selected users where explicitly authorized
(`notifications.broadcast`). High-risk bulk ops require a typed confirmation
(§38); **no bulk deletion**, no bulk refund, no bulk PHI export.

---

## 28. Exports

Where a permission exists (`analytics.export`, `audit_logs.export`, report
exports) — formats CSV/Excel/PDF with:
- permission check + scope preview,
- sensitive-field stripper (no PHI in aggregates; redacted values),
- audit log entry per export (actor, format, filters, row-count),
- access control: only pre-approved destination (browser download with
  anti-CSRF; server streams from snapshots).
**No unrestricted medical-record export** (`medical_records.download` in admin
is C4 reason-locked; we do not expose a "export all records" UI).

---

## 29. Accessibility

Keyboard-first (full tab order, role=menu/grid/dialog semantics, ESC to close
dialogs, visible focus), readable contrast (AA), screen-reader labels for
charts (data description, not just pixels), accessible tables
(`aria-sort`, caption), accessible dialogs (`aria-modal`, focus trap,
return focus), non-colour-only statuses (badge = icon + text), large targets in
any hover/dropdown actions, reduced motion.

---

## 30. Responsive Design

**Desktop-first** (1280+), laptop (≥1024) comfortable, tablet (≥768) usable:
sidebar collapses to overlay drawer ≤1024, tables become card-lists ≤900 with
expansion, KPI grid reflows 4→2→1 columns, no horizontal scroll beyond data
table (which can scroll its own viewport with sticky header). The admin UI is
not required to mirror mobile UX.

---

## 31. Design System

Same Sickler's Warriors tokens as mobile (§6/§7/§37 of mobile doc), adapted for
dense desktop:
- **Colors**: identical semantic tokens — primary Dark Blue `#0D47A1`,
  secondary Blue `#1976D2`, accent Red `#C62828` (emergency/danger only),
  success teal `#00897B`, warning amber `#F9A825`, surfaces `#FFFFFF`/
  `#F6F9FC`, text `#12202F`/`#5C6B7A`, borders `#DCE4EE`; dark mode honours
  same rules. No red-branding in normal UI.
- **Typography**: system sans; display 24, H1 20, H2 16/600, body 14/400 (dense
  admin), caption 12, label 13/500; tabular numerals in tables; 16px min for
  primary content.
- **Spacing/radius/elevation**: 4-based grid (4/8/12/16/24/32); radius 4 cards /
  8 tables / 12 dialogs; elevation 0 cards / 2 tabs / 4 dialogs.
- **Density**: rows ≤48px with comfortable padding; density toggle but never
  below 40px.
- **Status**: `StatusBadge` colour+icon+text; queues show count badges.
- **Charts**: line/bars from snapshots with accessible summaries.

---

## 32. Privacy-by-Design

- **Least privilege**: sidebars, columns, exports, and file views all follow
  the 3.3 matrix; no "admin sees all" model.
- **Data minimization**: masked contacts (users list), masked donors
  (BR-006), redacted payment payloads, aggregate-only reports.
- **Field-level visibility**: component renders only fields returned by
  permission-resolved API; hidden ≠ present in DOM.
- **Object-level authorization**: panel resolves via the same API the mobile
  uses (owner/consent/facility filters) — never direct DB.
- **Audit logging**: every sensitive open (`C4 gate`), decision, export,
  destructive action writes audit.
- **Secure downloads**: signed URLs only; file viewer streams via API, no
  raw paths, no cache of PHI to disk.
- **Protected-resource gate** (AD-A-9): SUP/ADM opening a C4 medical surface
  must state reason; logged.

---

## 33. Security UX

- Login = email/phone + password + **mandatory TOTP MFA** (admin roles);
  PKCE-deep-linked session; idle timeout (config, default 15 min — AD-A-2) with
  keep-alive prompt; logout everywhere (denylist).
- Password change + MFA manage + active sessions (own):
  `AUTH-010`-style API (`/auth/sessions`).
- **Re-authentication** for highly sensitive actions (role assignment, refunds,
  emergency override, security settings) — secondary TOTP prompt.
- No invented auth architecture; uses 3.5 auth endpoints + `auth.mfa_*`.

---

## 34. API Integration

Plan: SPA consumes `/api/v1/*` with a typed client layer; every screen maps in
`admin-api-ui-traceability.md`. Conventions: bearer refresh via interceptor;
envelope/error handling shared with mobile client decisions; server-side
pagination everywhere; **missing endpoints are `API GAP` and listed — never
silently invented**. Webhook endpoints are server-side only (not consumed here).

---

## 35. Role-to-Screen Mapping

Full matrix in `admin-screen-role-matrix.md`. Summary invariant:
- **SUP**: all screens (security/settings privileged) — C4 gates.
- **ADM**: all operational screens (no `role assignment` edit, no security
  center default, C4 on PHI).
- **VO**: queues + own-scope audit + scoped analytics only.
- **MOD**: community moderation + moderation analytics only.
- UI hiding is UX; backend 403 authoritative (§36).

---

## 36. Screen Inventory

Complete spec (ID, name, purpose, role, permission, entry, exit, API deps,
DB resource, components, sensitive info, actions, loading/empty/error/401/403/
404, a11y, audit) in `admin-screen-inventory.md`. IDs: `ADM-DASH-`,
`ADM-USR-`, `ADM-PAT-`, `ADM-DOC-`, `ADM-FCL-`, `ADM-CAR-`, `ADM-BLD-`,
`ADM-EMG-`, `ADM-DON-`, `ADM-CAM-`, `ADM-APP-`(?), `ADM-COM-`, `ADM-EDU-`,
`ADM-COM-MSG-`, `ADM-NOT-`, `ADM-RPT-`, `ADM-AUD-`, `ADM-SEC-`, `ADM-SET-`,
`ADM-SRCH-`.

Admin states (§37 prompt) → standard `AsyncView` + Unauthorised panel:
- `401` → silent refresh → login redirect.
- `403` → `ForbiddenPanel` («You don't have permission for this.›» + Home) —
  never imply data exists.
- `404` → `NotFoundPanel` (invalid route/object).
- validation errors inline; loading/empty/error/retry everywhere.

---

## 37. Component System

Reusable catalog in `admin-component-catalog.md` (DataTable, SearchBar,
FilterPanel, StatusBadge, ApprovalPanel, ConfirmationDialog, DetailPanel,
AuditTimeline, FileViewer, NotificationPanel, DashboardCard, Chart, Pagination,
Empty/Error/LoadingState, ForbiddenPanel...). Every component tokens-drive,
a11y-modeled, with states defined.

---

## 38. Open Design Decisions

| # | Decision | Default |
|---|---|---|
| AD-A-1 | Panel framework | **React 18 + TypeScript + Vite** (recommended); alt: Vue 3 + Vite. Standalone SPA in `apps/admin-web`. |
| AD-A-2 | Session policy | MFA mandatory; idle timeout 15 min (config), force logout on expiry; reauth for sensitive ops |
| AD-A-3 | C4 gate UX | Reason required before PHI open; logged; auto-close after inactivity |
| AD-A-4 | Approve/reject co-sign | Education/refund thresholds; doctor-rejection co-sign configurable (default off) |
| AD-A-5 | Charts lib | Recharts (React), server-aggregate data only |
| AD-A-6 | Appointments in admin | Default **HIDDEN / API GAP** (no approved permission) — revisit in 3.3 revision |
| AD-A-7 | Security center for ADM | Conditional C4 read for alerts; write SUP-only |
| AD-A-8 | System settings API | **API GAP** today — build settings endpoints in Stage 4 *only as approved* |
| AD-A-9 | PHI reason-lock | SUP/ADM C4 opens require stated reason + audit |
| AD-A-10 | Live vs placeholder | `demo/placeholder` widgets labelled; live defaults |
| AD-A-11 | Refund escalation | ADM refund > threshold requires SUP co-sign |
| AD-A-12 | Bulk verify scope | VO bulk verify limited to same-day same-queue batch with typed confirm |
| AD-A-13 | HOSPITAL in admin | Excluded v1 (facility ops via mobile/clinical) — possible future |
| AD-A-14 | Education editor | Markdown + file upload draft CM; publish flow only after review |
| AD-A-15 | Localization of admin | English-only UI v1; Kiswahili labels FUTURE (admin ops staff) |

---

## 39. Workflow Diagrams (extension)

Six Mermaid diagrams in `admin-navigation.md` §7 (doctor verification, campaign
approval, blood request, emergency, donation/webhook, moderation).

## 40. Design Threat Review (extension)

Complete in `admin-web-ui-ux-review.md` §(threat review matrix): privilege
escalation, accidental data exposure, unauthorized patient access, export leak,
dangerous bulk actions, insecure file viewing/downloads, session hijacking,
unauthorized moderation, unauthorized payment actions, unauthorized emergency
actions — each with mitigation mapped to a design/API rule.

## 41. Requirements Traceability (extension)

`admin-api-ui-traceability.md` §(trace): Requirement → Admin Module → Screen →
API → Permission → DB → Audit rule. Covered: verification (FR-DOC/BLD/CAM/…),
moderation (FR-COM), campaigns/donations (FR-CAM/PAY), notifications (FR-NOT),
education (FR-EDU), audit/analytics (NFR-SEC-004, FR-AUD). **Gaps
identified**: appointments (AD-A-6), security center endpoints, system settings
save endpoints — all marked API GAP, none invented.

## 42. Mobile Relationship (extension)

| Concern | Mobile app | Admin panel |
|---|---|---|
| Patient/user interaction | Yes (self-service) | No (unless C4 oversight) |
| Governance / verification | Request submission (doctor docs) | Decision console |
| Moderation | Report submitter | Decision console |
| Operational management | Limited self-touch | Full (per role) |
| Reporting | Self aggregates | Org aggregates |
| Private chats | Yes (participants) | **Never** |
| PHI surface | Patient-own + consent | C4 reason-locked only |

The panel must not migrate patient self-service screens onto admin.

## 43. Innovation Review (extension)

| Innovation | Problem | Benefit | Data | Privacy | API | DB | Complexity | Class |
|---|---|---|---|---|---|---|---|---|
| Verification pipeline dashboard | slow review | queue SLA tracking | queue statuses | none | `verify` queues | none | Low | CORE |
| Emergency response monitor | no live ops view | severity-response timeline | emergency statuses | operational | `/admin/emergency` | none | Med | CORE |
| Donation reconciliation dashboard | payment drift | provider vs verified | payments (redacted) | masked | `/payments` | snapshots | Med | CORE |
| Blood demand heatmap | regional shortage blind spots | region demand view | request aggregates | aggregate | `analytics` | snapshot | Med | FUTURE |
| Verification workflow automation | repeat approvals | automation rules | queue history | none | — (server) | — | Med | FUTURE |
| Anomaly alerts (payments/logins) | fraud/blips | alert feed | security events | masked | security (gap) | `security_events` | Med | FUTURE |
| Content quality workflow | inconsistent CE | review stats | education states | none | `education.review` | none | Low | CORE |
| Privacy/access monitoring | invisible C4 access | access-heat view | audit C4 rows | sensitive-locked | audit (gap) | audit | Med | FUTURE |

No speculative AI. CORE items integrate; FUTURE items inert with markers.

---

END OF STAGE 3.7 MAIN DESIGN — gate in `admin-web-ui-ux-review.md`.