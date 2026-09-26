# 3.7 Admin Screen Inventory

> Stage 3.7 Admin Web UI/UX Design. Complete list of admin screens, each with
> ID, purpose, role access, permissions, entry/exit, API dependencies, DB
> resources, sensitive data, loading/empty/error/403/404 behavior, components,
> accessibility and audit obligations. Design only — no implementation.
>
> Role access column lists which of SUP/ADM/VO/MOD can reach the screen
> (contract in `admin-role-ui-matrix.md`; exhaustive map in
> `admin-screen-role-matrix.md`). `(gap)` = API GAP, endpoint does not exist yet.
> `HIDDEN` = not routable (see AD-A-6/AD-A-8).

Screen count: **42** (28 primary + 14 enhanced detail/gap). Future-flagged
screens are listed but inert.

---

## 0. Legend

| Field | Meaning |
|---|---|
| ID | unique admin screen id |
| Roles | SUP / ADM / VO / MOD reachability |
| Permission | 3.3 permission code gating the API call |
| Entry/Exit | route guard in/out |
| API | endpoint(s) used (3.5 matrix §20 & module tables) |
| DB | backing data (3.4 schema) |
| Sens | sensitive data exposed on screen |
| Actions | rendered action affordances |
| Audit | writes to audit_logs on trigger |
| States | defined 200/loading/empty/error/401/403/404 |

---

## 1. Authentication & Shell

| # | ID | Screen | Roles | Permission | Entry/Exit | API | DB | Sens | Actions | Audit | States | Components |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 1 | AUTH-A-01 | Login | all admin roles | `auth.login` | `/auth/login` → `/app/dashboard` | `POST /auth/login`, `POST /auth/mfa/verify` | users/auth | creds never stored | login, MFA step | failed attempts | loading/error/400 | LoginCard, MfaPrompt |
| 2 | AUTH-A-02 | Password reset | all | `auth.password_reset` | `/auth/forgot` | `POST /auth/password/forgot`, `POST /auth/password/reset` | users | — | request reset | event | loading/error/success | FormCard |
| 3 | AUTH-A-03 | MFA setup | all | `auth.mfa_setup` | `/auth/mfa-setup` | `POST /auth/mfa/setup`, `POST /auth/mfa/verify` | mfa props | TOTP secret never shown raw | scan QR, backup codes | setup event | loading/error | QrCard, CodeInput |
| 4 | AUTH-A-04 | Sessions (own) | all | `auth.sessions` | `/profile/me` | `GET/POST /auth/sessions`, `POST /auth/logout` | sessions | device info | revoke/logout all | session revoke | loading/empty/error | SessionList |
| 5 | AUTH-A-05 | Sensitive re-auth | SUP/ADM (, VO none) | `auth.reauth` | `/auth/reauth` | `POST /auth/mfa/re -verify` | mfa props | — | confirm TOTP | reauth event | loading/error/400 | TOTP prompt over AppShell |

---

## 2. Dashboard & Navigation

| 6 | ADM-DASH-001 | Dashboard (SUP kernel) | SUP | `analytics.view`, `dashboard` (gap) | `/app/dashboard` | `GET /admin/dashboard`; widget APIs (gap flags per §20) | analytics_snapshots | aggregates only | open module | — | loading/empty/error/401/403 | DashboardCard, DashboardChart, KpiStrip, QueueBadge |
| 7 | ADM-DASH-002 | Dashboard (ADM ops kernel) | ADM | `analytics.view` | same | `GET /admin/dashboard` | same | aggregates only | open module | — | same states | same |
| 8 | ADM-DASH-003 | Dashboard (VO verification kernel) | VO | `doctors.verify`,`blood_requests.verify`,`campaigns.verify` | same | queue counts (gap) | queue tables | queue counts | open queue | — | same | KpiStrip, QueueTable |
| 9 | ADM-DASH-004 | Dashboard (MOD moderation kernel) | MOD | `community.moderate` | same | report counts (gap) | reports | counts | open queue | — | same | KpiStrip, QueueTable |

---

## 3. Users

| 10 | ADM-USR-001 | Users list | SUP/ADM | `users.view` | list↔detail | `GET /admin/users` | users | masked contacts only | paginate/filter/search/sort | — | loading/empty/error/403 | DataTable, SearchBar, FilterPanel, Pagination, EmptyState |
| 11 | ADM-USR-002 | User detail | SUP/ADM | `users.view` | `ADM-USR-001`→detail | `GET /admin/users/{uid}` | users | masked; role data | back/edit | view | loading/404/403 | DetailPanel, StatusBadge, AuditTimeline(shadow) |
| 12 | ADM-USR-003 | Account state actions | SUP/ADM | `users.update`, `users.deactivate` | sheet on detail | `POST /admin/users/{uid}/activate|deactivate|suspend` | users | — | activate/deactivate/suspend/restore | all | confirm/error | ActionSheet |implied|
| 13 | ADM-USR-004 | Verify user | SUP/ADM/VO (C6) | `users.verify` | on detail/queue | `POST /admin/users/{uid}/verify` | users + audit | verifying docs | approve/reject | decision | confirm/error | ApprovalPanel, ConfirmationDialog |
| 14 | ADM-USR-005 | Role & permission assignment | **SUP only** (C17) | `users.role_assign` | on user detail, SUP-only slot | `POST /admin/users/{uid}/roles` | user_roles/perms | role graph | assign/revoke (typed confirm) | every change | confirm/error/403 | RolePicker, ConfirmationDialog |

---

## 4. Patients (C4)

| 15 | ADM-PAT-001 | Patients list | SUP/ADM (C4) | `patients.view` (C4), `consents.view` (C4) | gate → list | `GET /admin/patients` (gap? per §20 partial) | patients (aggregate rows) | PHI-free rows | filter/search | open | gate states + list states | ProtectedGate, DataTable |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 16 | ADM-PAT-002 | Patient profile | SUP/ADM (C4) | `patients.update` (operational) | list→profile | `GET /admin/patients/{pid}` | patients/profile | PHI (C4-locked) | edit operational fields | access-open | gate/403 | DetailPanel, ConsentBadges |
| 17 | ADM-PAT-003 | Health timeline | SUP/ADM (C4) | `medical_records.view` (C4) | profile→timeline | `GET /patients/me/records/*` mirrored | medical_records | PHI clinical (C4) | view only, no edit | access-open/download | gate/403 | Timeline, RecordCard |
| 18 | ADM-PAT-004 | Consents & access history | SUP/ADM (C4) | `consents.view` | profile→consents | `GET /patients/me/consents` | consents + access logs | consent graph | view | access-open | gate/403 | ConsentList, AuditTimeline |

---

## 5. Doctors & Facilities

| 19 | ADM-DOC-001 | Doctor verification queue | SUP/ADM/VO | `doctors.verify` (C6) | queue → doctor detail | `GET /admin/doctors/verification-queue` | doctor_profiles + pending docs | verifying identity docs | open case | — | loading/empty/error/403 | QueueTable, SearchBar, FilterPanel |
| 20 | ADM-DOC-002 | Doctor review & decision | SUP/ADM/VO | `doctors.verify` | queue→detail →decide | `POST /admin/doctors/{uid}/verify`, `/admin/doctors/{uid}/suspend` | doctor + verify decision | docs (signed view) | approve/reject/correct/suspend | decision | loading/error/confirm | DocumentViewer, ApprovalPanel, ReasonInput, ConfirmationDialog |
| 21 | ADM-FCL-001 | Facilities list | SUP/ADM/VO | `facilities.verify`, `facilities.view` | list | `GET /admin/facilities` | facilities | contacts (internal) | filter/search | — | loading/empty/error | DataTable |
| 22 | ADM-FCL-002 | Facility detail & verify | SUP/ADM/VO | `facilities.verify` | list→detail | `GET /admin/facilities/{fid}`, `POST /admin/facilities/{fid}/verify` | facilities | internal ops data | verify/reject/edit(SUP/ADM) | decision | loading/error/confirm | DetailPanel, ApprovalPanel |

---

## 6. Caregivers (C4)

| 23 | ADM-CAR-001 | Caregivers list | SUP/ADM (C4) | `caregivers.view` (C4) | list | `GET /admin/caregivers` | caregiver_relationships | scope data only | filter/remove | — | loading/empty/403 | DataTable, RelationshipCard |
| 24 | ADM-CAR-002 | Caregiver relationship remove | SUP/ADM (C4) | `caregivers.remove` (C4) | detail sheet | `POST /admin/caregivers/{rel}/remove` (gap) | caregivers | scope data | remove (reason+confirm) | removal | confirm/error/403 | ReasonDialog |

---

## 7. Blood

| 25 | ADM-BLD-001 | Blood requests | SUP/ADM/VO (VO verify scope) | `blood_requests.view` (C6), `blood_requests.verify` | list↔detail | `GET /admin/blood/requests*` | blood_requests | no donor PII (BR-006) | filter/search | — | loading/empty/error | DataTable, StatusBadge, FilterPanel |
| 26 | ADM-BLD-002 | Blood request verification | SUP/ADM/VO | `blood_requests.verify` | queue→detail→decide | `POST /admin/blood/verification-queue…` | blood_requests | verification docs | approve/reject | decision | loading/error/confirm | ApprovalPanel, ReasonInput |
| 27 | ADM-BLD-003 | Donors (masked) | SUP/ADM/VO (verify) | `blood_donors.view` (C6/7) | list | `GET /admin/blood/donors` | blood_donors | masked (region/group) | verify donor | decision | loading/empty/403 | DataTable(masked) |
| 28 | ADM-BLD-004 | Matching (run + results) | SUP/ADM/VO | `blood_matches.run`, `blood_matches.view` (C6/7) | run→result | `POST /admin/blood/matches/run` | blood_matches | matched pairs C9-scoped | run matcher/view | run event | loading/wait/progress | ActionPanel, MatchCard |

---

## 8. Emergency

| 29 | ADM-EMG-001 | Emergency monitor | SUP/ADM (C4) | `emergency_requests.view` (C4) | `/app/emergency` | `GET /admin/emergency` | emergency_requests | operational (op info) | open case / esc | open | loading/empty/error/403 | LiveRegion, CaseCard, KpiStrip |
| 30 | ADM-EMG-002 | Emergency case list | SUP/ADM | same | monitor→list | `GET /admin/emergency?...` | emergency_requests | same | filters | — | loading/empty/error/403 | DataTable, FilterPanel |
| 31 | ADM-EMG-003 | Emergency case detail | SUP/ADM (C4) | `emergency_requests.view`, `emergency_requests.manage` | list→detail | `GET /admin/emergency/{caseId}`, `POST /admin/emergency/{caseId}/respond|escalate|resolve` | emergency_requests + timeline | case PHI minimal (C4) | respond/escalate/resolve | action per case | loading/404/403 | CaseTimeline, ActionPanel, ConfirmationDialog |

---

## 9. Donations / Payments

| 32 | ADM-DON-001 | Campaign verification queue | SUP/ADM/VO | `campaigns.verify` | queue→campaign | `GET /admin/campaigns/verification-queue` | campaigns | beneficiary docs | open | — | loading/empty/403 | QueueTable |
| 33 | ADM-DON-002 | Campaign review & decision | SUP/ADM/VO | `campaigns.verify` | queue→detail→decide | `POST /admin/campaigns/{cid}/verify` | campaigns | beneficiary/supporting docs | approve/reject/correct | decision | loading/error/confirm | DocumentViewer, ApprovalPanel, ReasonInput |
| 34 | ADM-DON-003 | Donation transactions | SUP/ADM | `donations.view`,`payments.view` | list | `GET /admin/donations*` | donations/payments | redacted payer refs | filter/export(A) | (export on view) | loading/empty/403 | DataTable, StatusBadge, ReconciliationChip |
| 35 | ADM-DON-004 | Reconciliation | SUP/ADM | `donations.view` (policy) | list→reconciliation | `GET /payments/verify`? (gap) + `POST /payments/refund` | payments | redacted | review/refund | refund | loading/empty/error/403 | ReconciliationTable, RefundFlow |

---

## 10. Appointments (AD-A-6 HIDDEN)

| 36 | ADM-APP-001 | Appointment management | `HIDDEN` | none approved (AD-A-6) | — | — | appointments | — | — | — | — | — | (future) |

---

## 11. Community & Education

| 37 | ADM-COM-001 | Reports queue | SUP/ADM/MOD | `community.moderate` | `/app/community` | `GET /admin/community/reports` | community reports | reported content (spoiler) | open decision | — | loading/empty/403 | QueueTable, SpoilerCard |
| 38 | ADM-COM-002 | Moderation decision | SUP/ADM/MOD | `community.moderate` | queue→detail→decide | `POST /admin/community/reports/{rid}/resolve` (gap) | reports/moderations | reported content | hide/remove/warn/escalate | decision | loading/error/confirm | DecisionPanel, ConfirmationDialog |
| 39 | ADM-EDU-001 | Education content list | SUP/ADM | `education.review` | `/app/education` | `GET /admin/education/content` (gap) | content | drafts (locked) | filter/edit(new) | — | loading/empty/403 | ContentTable, CategoryFilter |
| 40 | ADM-EDU-002 | Content editor (draft) | SUP/ADM | `education.review` (write) | list→editor | `POST /admin/education/content/{id}/draft` (gap) | content | draft text | save draft | draft save | loading/error/403 | MarkdownEditor, FilePicker |
| 41 | ADM-EDU-003 | Review & publish | SUP/ADM | `education.review` | editor→review | `POST /admin/education/content/{id}/review`, `/publish` (gap) | content | draft review | approve/reject/publish | publish | loading/error/confirm | ApprovalPanel, ReasonInput |

---

## 12. Communications & Notifications

| 42 | ADM-COM-MSG-01 | Broadcast composer | SUP/ADM | `notifications.broadcast` | `/app/notifications/broadcast` | `POST /notifications/broadcast` | notifications | privacy-safe preview only | send/schedule | send | loading/error/confirm | Composer, PrivacyPreview |
| 43 | ADM-NOT-001 | Notification templates | SUP/ADM | `notifications.broadcast` | templates | `GET/POST /admin/notifications/templates` (gap) | templates | placeholders only | edit/save | save | loading/error | FormCard |
| 44 | ADM-NOT-002 | Delivery history | SUP/ADM | `notifications.broadcast` | history | `GET /admin/notifications/log*` (gap) | notification log | — | view/resend | — | loading/empty/error | DataTable, FilterPanel |

---

## 13. Reports & Audit

| 45 | ADM-RPT-001 | Analytics reporting | SUP/ADM (+VO scoped) | `analytics.view` | `/app/reports/analytics` | `GET /admin/analytics?...` | analytics_snapshots | aggregates only | date range/export(SUP) | export | loading/empty/403 | ChartDashboard, DateRangePicker, ExportButton |
| 46 | ADM-RPT-002 | Exports | SUP (ADM C4) | `analytics.export` | reports→exports | `POST /admin/exports` (gap) | audit + exports | scope preview | download | export | loading/error/403 | ExportWorkflow, ScopeConfirm |
| 47 | ADM-AUD-001 | Audit explorer | SUP/ADM (C6 VO own) | `audit_logs.view` | `/app/audit` | `GET /admin/audit-logs?...` | audit_logs | never PHI bodies | filter/search/view | — | loading/empty/error/403 | AuditTable, FilterPanel, AuditDetail |

---

## 14. Security & Settings

| 48 | ADM-SEC-001 | Security center | SUP (ADM conditional AD-A-7) | `security_events` (gap) | `/app/security` | `GET /admin/security/alerts*` (gap) | security_events | masked creds never rendered | view alerts/lockout | access-open | loading/empty/403 | AlertList, LockoutCard |
| 49 | ADM-SET-001 | System settings | SUP (ADM conditional AD-A-8) | settings (gap) | `/app/settings` | `GET/POST /admin/settings*` (gap) | settings | secret values (masked) | edit/save | save | loading/break-glass/403 | SettingsForm, ReauthPrompt |

---

## 15. Cross-cutting

| 50 | ADM-SRCH-001 | Global search | all (authorized indexes) | per index view | `/app/search?q=` | `GET /admin/search?q=` (gap) | authorized indexes | no PHI previews | deep-link | — | loading/empty/403 | SearchBar, ResultGroup |
| 51 | COM-P-001 | ProtectedResourceGate | SUP/ADM | on C4 pages | C4 open | none (UI) → logs to `audit_logs.access_open` | audit_logs | reason string | confirm | access_open | gate/error | ReasonDialog |
| 52 | COM-H-001 | ForbiddenPanel / NotFound / Empty / Error / Loading defaults | all | — | — | — | — | — | Home | — | — | Panel primitives |

---

Total **52 entries** (v1 routable ≈ 48; `ADM-APP-001`, inactive gap routes are
documented but not routable).

## 16. Counts & Coverage

| Module | Screens | Roles covered | Gaps |
|---|---|---|---|
| Auth/shell | 5 (+1) | all | — |
| Dashboard | 4 | SUP/ADM/VO/MOD | role-filtered KPIs |
| Users | 5 | SUP/ADM/VO | — |
| Patients | 4 | SUP/ADM(C4) | `GET /admin/patients` partial |
| Doctors/Facilities | 4 | SUP/ADM/VO | — |
| Caregivers | 2 | SUP/ADM(C4) | remove endpoint |
| Blood | 4 | SUP/ADM/VO | — |
| Emergency | 3 | SUP/ADM(C4) | — |
| Donations | 4 | SUP/ADM | reconciliation verify |
| Appointments | 1 | **HIDDEN** | full (AD-A-6) |
| Community | 2 | SUP/ADM/MOD | resolve endpoint |
| Education | 3 | SUP/ADM | several endpoints |
| Notifications | 3 | SUP/ADM | templates/log |
| Reports/Audit | 3 | SUP/ADM(+VO) | exports |
| Security/Settings | 2 | SUP(+,ADM) | full (AD-A-8) |
| Cross-cutting | 3 | all | search/full |
| **Total** | **52** | | documented |

---

END — next: `admin-component-catalog.md`.