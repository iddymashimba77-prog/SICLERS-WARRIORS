# 3.7 Admin Screen ↔ Role Matrix

> Exact **VISIBLE / CONDITIONAL / HIDDEN** mapping of every admin screen to the
> four admin roles (SUP/ADM/VO/MOD). Source of truth:
> `admin-role-ui-matrix.md` (contract) and `admin-screen-inventory.md` (IDs).
> UI visibility is UX only; backend authorization remains authoritative.

Legend: **V** visible · **C** conditional (gate/reason/scope) · **H** hidden
(not routable, no nav entry, no content)

---

## 1. Screen × Role

| ID | Screen | SUP | ADM | VO | MOD |
|---|---|---|---|---|---|
| AUTH-A-01 | Login | V | V | V | V |
| AUTH-A-02 | Password reset | V | V | V | V |
| AUTH-A-03 | MFA setup | V | V | V | V |
| AUTH-A-04 | Sessions (own) | V | V | V | V |
| AUTH-A-05 | Sensitive re-auth | V | V | H | H |
| ADM-DASH-001 | Dashboard (SUP kernel) | V | H | H | H |
| ADM-DASH-002 | Dashboard (ADM ops) | H | V | H | H |
| ADM-DASH-003 | Dashboard (VO verification) | H | H | V | H |
| ADM-DASH-004 | Dashboard (MOD moderation) | H | H | H | V |
| ADM-USR-001 | Users list | V | V | H | H |
| ADM-USR-002 | User detail | V | V | H | H |
| ADM-USR-003 | Account state actions | V | V | H | H |
| ADM-USR-004 | Verify user | V | V | C (verify scope) | H |
| ADM-USR-005 | Role & permission assignment | V | **H** (C17) | H | H |
| ADM-PAT-001 | Patients list | C (C4) | C (C4) | H | H |
| ADM-PAT-002 | Patient profile | C (C4) | C (C4) | H | H |
| ADM-PAT-003 | Health timeline | C (C4) | C (C4) | H | H |
| ADM-PAT-004 | Consents & access history | C (C4) | C (C4) | H | H |
| ADM-DOC-001 | Doctor verification queue | V | V | V | H |
| ADM-DOC-002 | Doctor review & decision | V | V | V | H |
| ADM-FCL-001 | Facilities list | V | V | C (verify scope) | H |
| ADM-FCL-002 | Facility detail & verify | V | V | C (verify) | H |
| ADM-CAR-001 | Caregivers list | C (C4) | C (C4) | H | H |
| ADM-CAR-002 | Caregiver relationship remove | C (C4) | C (C4) | H | H |
| ADM-BLD-001 | Blood requests | V | V | C (verify scope) | H |
| ADM-BLD-002 | Blood verification | V | V | V | H |
| ADM-BLD-003 | Donors (masked) | V | V | C (verify scope) | H |
| ADM-BLD-004 | Matching (run + results) | V | V | C (C6/C7) | H |
| ADM-EMG-001 | Emergency monitor | C (C4) | C (C4) | H | H |
| ADM-EMG-002 | Emergency case list | C (C4) | C (C4) | H | H |
| ADM-EMG-003 | Emergency case detail | C (C4) | C (C4) | H | H |
| ADM-DON-001 | Campaign verification queue | V | V | V | H |
| ADM-DON-002 | Campaign review & decision | V | V | V | H |
| ADM-DON-003 | Donation transactions | V | V | H | H |
| ADM-DON-004 | Reconciliation | V | C (C4 export etc) | H | H |
| ADM-APP-001 | Appointment management | H (AD-A-6) | H | H | H |
| ADM-COM-001 | Reports queue | V | V | H | V |
| ADM-COM-002 | Moderation decision | V | V | H | V |
| ADM-EDU-001 | Education content list | V | V | H | H |
| ADM-EDU-002 | Content editor | V | V | H | H |
| ADM-EDU-003 | Review & publish | V | V | H | H |
| ADM-COM-MSG-1 | Broadcast composer | V | V | H | H |
| ADM-NOT-001 | Templates | V | V | H | H |
| ADM-NOT-002 | Delivery history | V | V | H | H |
| ADM-RPT-001 | Analytics reporting | V | V | C (own scope) | H |
| ADM-RPT-002 | Exports | V | C (C4) | H | H |
| ADM-AUD-001 | Audit explorer | V | V | C (own actions, C6) | H |
| ADM-SEC-001 | Security center | V | C (AD-A-7) | H | H |
| ADM-SET-001 | System settings | V | C (AD-A-8) | H | H |
| ADM-SRCH-001 | Global search | V | V | V (scoped indexes) | V (mod indexes) |
| COM-P-001 | ProtectedResourceGate | V (on C4) | V | H | H |
| COM-H-001 | Default states (403/404/empty/error) | V | V | V | V |

---

## 2. Rules

1. **HIDDEN = never routable.** A hidden screen returns the panel's 403 view if
   forced by deep link — proof not existence.
2. **CONDITIONAL** (C4/C6/C7/own-scope) means the role *may* pass the gate;
   auto-closed by ProtectedResourceGate (`COM-P-001`) if reason missing.
3. **C17** makes `ADM-USR-005` and privileged assignments **invisible to
   ADMIN**, only `SUP` may act — enforced at both API and UI (no button, no
   route).
4. **Moderation vs verification separation**: a MOD is invisible to operational
   screens; a VO is invisible to moderation screens. No user can preview
   another dashboard's kernel.
5. Screen-console visibility must match `admin-role-ui-matrix.md` exactly; a
   drift (e.g. API allows but UI omits) is a bug, never a guard.
6. A row that is `H` for a role may still be listed here for completeness;
   tracing is done in `admin-api-ui-traceability.md`.

---

## 3. Verification of Permutation Coverage

- Each of the four roles: menu = union of its `V` screens.
- Intersections: `ADM-DOC-002` (SUP/ADM/VO) — shared decision surface with
  per-actor audit; `ADM_BLD-002` same triple; `ADM-DON-002` same.
- `ADM-COM-002` shared by SUP/ADM/MOD — MOD and ADM both act, distinct from VO.
- Zero screen is `V` for MOD but `H` for SUP or ADM (hierarchy preserved).
- Zero screen is `V` for VO in the medical/financial domain beyond scoped
  verification.
- `ADM-APP-001` is the single deliberate `H` (AD-A-6: no approved permission).
- `ADM-SEC/SET` are `V`/`C` only for SUP(+ADM conditional) — never VO/MOD.

---

## 4. Denied-Flow Demonstration (examples)

| Attempt | Role | Result |
|---|---|---|
| Open `/app/emergency` | VO | `ForbiddenPanel` (route guard 403) |
| Deep-link `/app/patients/:pid` | MOD | `ForbiddenPanel` |
| Edit roles on any user | ADM | no route, no button; API 403 |
| Open `/app/security` | VO | `ForbiddenPanel` |
| Run export from analytics | ADM | only C4-gated; co-sign check for refunds in separate flow |
| Moderation decision | VO | `ForbiddenPanel` |

---

END — next: `admin-api-ui-traceability.md`.