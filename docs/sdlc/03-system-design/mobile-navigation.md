# 3.6 Mobile Navigation

> Navigation structure, role-specific maps, guards, deep links, auth redirects
> and unauthorized-screen behaviour. Companion to `mobile-ui-ux-design.md`
> (§3/§4/§5) and `mobile-screen-inventory.md`. Screen IDs match the inventory.

---

## 1. Navigation Structure

Two stacks:

1. **Auth stack** — `Splash → Welcome → Login/Register → Verify → MFA → Shell`.
   No bottom navigation. Back from Welcome exits (social pattern).
2. **Main shell** — bottom navigation (phone) / `NavigationRail` (≥600dp)
   hosting role-filtered destinations + a persistent **Emergency FAB** that is
   outside the destination list.

Route table (relative paths double as deep-link targets):

| Route | Screen | Auth | Guard |
|---|---|---|---|
| `/splash` | AUTH-001 | public | — |
| `/welcome` | AUTH-002 | public | — |
| `/login` | AUTH-003 | public | redirect → shell if session |
| `/register` | AUTH-004 | public | — |
| `/verify/email` · `/verify/phone` | AUTH-005/006 | pending | — |
| `/reset` | AUTH-007/008 | public | — |
| `/mfa` | AUTH-009 | pending | — |
| `/home` | HOME-001 | auth | shell |
| `/health` | PAT-001 (+children `/health/meds`, `/health/records`, `/health/appointments`, `/health/timeline`) | patient/caregiver(consent) | guard |
| `/consents` | CONS-001 (+`/consents/{id}` CONS-002) | patient | guard |
| `/blood` | BLOOD-001 hub (`/blood/requests` list, `/{id}` BLOOD-003; `/blood/donors/me` BLOOD-004) | patient(donor) | guard |
| `/emergency` | EMG-002/003/004 | auth | guard (C14/operator) |
| `/appointments` | APP-001 (`/{id}` APP-002) | auth | guard |
| `/community` | COM-001 (`/posts/{id}` COM-002) | auth | guard |
| `/messages` | CHAT-001 (`/{id}` CHAT-002) | chat roles | guard (C13) |
| `/education` | EDU-001/002/003 | auth | guard |
| `/donations` | DON-001 (`/campaigns/{id}` DON-002) | auth | guard |
| `/notifications` | NOT-001 | auth | guard |
| `/profile` | PRO-001 + settings/security/privacy/language/help | auth | shell |

## 2. Role-Specific Navigation

Destination derivation (server permission set at login + `GET /users/me`):
rule `destVisible(role, permission)` → membership table (§5 main doc). Bottom
bar slots are filled in priority order and capped at 5; overflow goes into the
`More/Profile` screen.

| Slot | Patient | Doctor | Healthcare Staff | Caregiver | Blood Donor | Financial Donor / Org |
|---|---|---|---|---|---|---|
| 1 | Home | Home | Home | Home | Home | Home |
| 2 | Health | Patients | Patients | Viewing-patient | Blood | Donate |
| 3 | Blood | Appointments | Appointments | Care* | Community | Community |
| 4 | Community | Messages | Messages | — | Education | Education |
| 5 | More | More | More | More | More | More |
| FAB | SOS | SOS | SOS | SOS | SOS | SOS |

\* Caregiver second slot opens the linked patient context (banner C18) — the
caregiver's own profile lives under More.

**Empty-permission rule:** no role ever sees an empty tab set; Home +
Notifications + Profile are always present; everything else hidden (not shown,
not "greyed").

## 3. Navigation Guards

1. **AuthGuard**: no valid access token → `/login` (route preserved for
   post-login return). Splash probes with silent refresh.
2. **RoleGuard**: role/permission/consent required by the screen (from the
   3.5 endpoint matrix). Violation → `AccessDeniedState` ("You don't have
   access to this." + Home) — no existence hints, mirrors API 403/404 policy.
3. **StateGuard**: action buttons hidden unless backend state permits (§42
   UI state machines).
4. **ConsentGuard**: patient-visible data requires active consent where
   granted; revoked → `AccessDeniedState` with "Request access / Contact
   patient".

Guards are **UX**; every guarded screen still verifies with the API.

## 4. Deep Links

- Notification → relative route (`/blood/requests/{uid}`, `/consents/{id}`,
  `/appointments/{id}`, `/messages/{id}`, `/community/posts/{id}`).
- Scan/QR (future) for verified campaigns, doctor profiles.
- Resolution: auth required first; then guard; then load. Never *preview*
  sensitive content in the link target before auth.

## 5. Authentication Redirects

| Situation | Behaviour |
|---|---|
| Launch with valid session | `Splash → /home` (role-aware) |
| Launch without session | `Splash → /welcome` |
| 401 on a resource | silent refresh once → retry; else `/login` + "Please sign in again." |
| MFA required | `/mfa` after login, then continue to original route |
| Signed out mid-flow | route preservation; after login return to original route |

## 6. Unauthorized Screen Behaviour

AccessDeniedState copy, variants:
- Not your role → "This area isn't available for your account."
- Revoked consent → "Access to this was removed. Contact {owner} if needed."
- Admin toolbar item (scaffold leftover `admin_panel_page`) → **removed from
  navigation** (moved to 3.7 web) — no dead route for ordinary users.

---

## 7. Navigation Maps (Mermaid)

### 7.1 Authentication flow
```mermaid
flowchart TD
  A[App open] --> B[Splash AUTH-001]
  B --> C{Valid session?}
  C -- no --> W[Welcome AUTH-002]
  C -- yes --> SH[Main shell]
  W -->|Login| L[Login AUTH-003]
  W -->|Register| R[Register AUTH-004]
  L --> V1[Verify email/phone]
  R --> V1
  V1 --> MFA{ MFA enabled? }
  MFA -- yes --> M[MFA AUTH-009]
  MFA -- no --> SH
  M --> SH
  L -->|Forgot| P1[Reset request AUTH-007]
  P1 --> P2[Reset confirm AUTH-008]
  P2 --> L
  SH -->|session expired| L
```

### 7.2 Patient navigation
```mermaid
flowchart LR
  SH[Shell] --> HOME[Home]
  HOME --> HEALTH[Health]
  HEALTH --> MEDS[Medications]
  HEALTH --> REC[MED Records]
  HEALTH --> APPTS[Appointments]
  HEALTH --> TIME[Timeline]
  REC --> CONS[Consent/Sharing]
  SH --> BLOOD[Blood]
  BLOOD --> BLRQ[My requests]
  BLRQ --> BLMATCH[Matches]
  SH --> COMMUNITY[Community]
  COMMUNITY --> EDU[Education]
  COMMUNITY --> POST[Create post]
  SH --> MESS[Messages]
  SH --> MORE[More/Profile]
  SH -.-> EMG[SOS FAB]
```

### 7.3 Doctor navigation
```mermaid
flowchart LR
  SH[Shell] --> DH[Doctor dashboard]
  DH --> VERIF[Verification status]
  DH --> PTS[Authorized patients]
  PTS --> PREC[Patient records - consent]
  PREC --> CLIN[Clinical entry]
  SH --> DAPP[Appointments]
  SH --> DMESS[Messages patient]
  SH --> DEDU[Education CE]
  DH -.-> EMG[SOS FAB]
```

### 7.4 Caregiver navigation
```mermaid
flowchart LR
  SH[Shell] --> CH[Caregiver hub]
  CH --> INV[Invitations]
  INV --> ACC[Accept/Decline]
  CH --> LP[Linked patients]
  LP --> VIEW[Authorized info view - banner]
  VIEW --> MEDS[Medications scoped]
  VIEW --> CP[Consent status]
  CP --> REM[Remove relationship]
  SH --> MORE[Profile/Settings]
  SH -.-> EMG[SOS FAB]
```

### 7.5 Donor navigation
```mermaid
flowchart LR
  SH[Shell] --> DH[Home]
  DH --> BLD[Blood hub]
  BLD --> DP[Donor profile]
  BLD --> ELIG[Eligible requests]
  ELIG --> RESP[Respond to match]
  BLD --> HIST[Donation history]
  SH --> COMM[Community]
  SH --> EDU[Education]
  SH -.-> EMG[SOS]
```

### 7.6 Emergency flow
```mermaid
flowchart TD
  FAB[SOS FAB] --> CONFIRM[EMG-002 Confirm sheet]
  CONFIRM -->|press & hold| REQ[EMG-003 Request - prefilled]
  REQ -->|POST /emergency/requests| TRACK[EMG-004 Tracking]
  TRACK --> RES[EMG-005 Resolution]
  TRACK --> CANCEL[Cancel - owner only]
  CANCEL --> REQ
  REQ -. offline .-> CALL[Show call 112 / facility - never queued]
```

### 7.7 Blood request flow
```mermaid
flowchart TD
  BLD[Blood hub] --> CR[Create request BLOOD-002]
  CR -->|POST /blood/requests| DET[BLOOD-003 detail]
  DET --> ST[Status timeline CREATED/V/ACTIVE..]
  DET --> MATCH[Matches - C8/C9]
  MATCH -->|[donor]| RESP[Respond BLOOD-006]
  ST --> FULL[FULFILLED/CLOSED]
```

### 7.8 Medical record access
```mermaid
flowchart TD
  REC[List] --> DET[Detail]
  DET --> DOCVIEW[File viewer]
  DET --> SHARE[Share/Consent]
  SHARE --> CONS[Consent page]
  CONS --> REVOKE[Revoke access]
  DET --> DECLINED{Authorized?}
  DECLINED -- no --> DENIED[AccessDeniedState]
```

### 7.9 Consent flow
```mermaid
flowchart TD
  PRO[Privacy] --> LIST[Consent list CONS-001]
  LIST --> DET[Consent detail CONS-002]
  DET --> GRANT[Grant CONS-003]
  DET --> RENEW[Renew]
  DET --> REV[Revoke - DestructiveDialog]
  REV --> DONE[Immediate ack EXPIRES/REVOKED]
```

### 7.10 Donation/payment flow
```mermaid
flowchart TD
  CAM[Campaigns DON-001] --> CDET[Campaign detail DON-002]
  CDET --> AMT[Donate DON-003 amount]
  AMT --> PAY[Payment method DON-004]
  PAY -->|POST /donations idempotent| INIT[Donation initiated]
  INIT --> WAIT[Provider confirm via webhook]
  WAIT -->|verified| CONFIRM[Payment confirmed DON-005]
  WAIT -->|fail| FAIL[Failed DON-006 - retry allowed]
  CONFIRM --> HIST[History DON-007]
  CONFIRM --> RC[Receipt DON-008]
```