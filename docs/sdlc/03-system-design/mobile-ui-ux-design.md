# 3.6 Mobile UI/UX Design

> Stage 3.6 — System Design. Companion deliverables:
> `mobile-navigation.md`, `mobile-screen-inventory.md`,
> `mobile-component-catalog.md`, `mobile-api-traceability.md`,
> `mobile-ui-ux-review.md`.
>
> **Design only.** This document supersedes the earlier thin draft in
> `mobile-design.md` (kept for history). It does not implement screens. The
> Flutter app is a **client of the backend API**; backend authorization remains
> the final security boundary. Nothing here invents endpoints — every screen
> maps to the approved `api-endpoint-matrix.md` (3.5).
>
> All screens are referenced by stable IDs defined in
> `mobile-screen-inventory.md` (e.g. `AUTH-001`, `PAT-001`, `EMG-001`).

---

## 1. UX Goals

Derived from `NFR-USE-001..003`, `NFR-SEC-*`, FR modules and the healthcare
domain. Ten goals, ordered by priority:

| # | Goal | Requirement source | Key measurable outcome |
|---|---|---|---|
| G1 | **Safety first** | BR-001..012, healthcare-safety reqs | No accidental dangerous action; critical info never obscured |
| G2 | **Simplicity for all literacy levels** | NFR-USE-001 | ≤3 taps to every primary action; plain-language labels |
| G3 | **Accessibility** | WCAG 2.1 AA intent | Min 48px targets, 4.5:1 contrast, screen-reader labels |
| G4 | **Privacy by design** | NFR-SEC-002/004, privacy reqs | No PHI in push previews, notifications, URLs or screenshots |
| G5 | **Emergency usability** | NFR-USE-002/003, FR-EMG-* | Emergency reachable from entire app, fast, accident-resistant |
| G6 | **Clear health information** | FR-MEDREC/FR-MED/FR-SYM | Non-clinical, plain-language display; no diagnosis language |
| G7 | **Low cognitive load** | NFR-USE-001 | Max 5 primary destinations; one primary action per screen |
| G8 | **Fast navigation** | FR-* (all) | Role-filtered destinations; deep links for recurring flows |
| G9 | **Trust** | FR-DOC, FR-EDU, FR-CAM | Verification badges; clear source labels (trust & safety §39) |
| G10 | **Reliability on poor networks** | NFR-AVL, NFR-PERF | Never silently lose input; explicit success/failure |

---

## 2. Target Users

Primary consumers of the mobile app (per 3.3 roles). Administrative functions
are **not** exposed on mobile (admin web UI = 3.7; `ADMIN-*` screens HIDDEN).

| User | Literacy/context | Primary needs | Language |
|---|---|---|---|
| Patient / Sickler | Mixed digital literacy; possibly low | Health tracking, meds, blood, emergency, community, education | EN + SW |
| Caregiver | Family member; may act for patient | Authorized access to patient info (consent-based), medication support | EN + SW |
| Doctor | Professional | Verified patients, records (consent-gated), appointments, education | EN |
| Healthcare Staff | Facility worker | Facility-scoped appointments, records, blood records | EN |
| Blood Donor | General public | Requests, matching, history, community | EN + SW |
| Financial Donor / Organization | General / org representatives | Campaigns, donations, receipts | EN + SW |
| Admin | Ops | Not on mobile → 3.7 web. HIDDEN here | EN |

**Design consequence:** every flow must be usable by a first-time user with no
medical or technical vocabulary. Kiswahili must be available for patient/community
roles (i18n §38).

---

## 3. Information Architecture

Auth-block, then a single role-aware main shell. Content is grouped by user
task, not by database module.

```
┌ AUTH BLOCK (pre-login) ──────────────────────────────────────┐
│ Splash → Welcome → Login | Register → Email/Phone verify      │
│ → Password reset | MFA → Main Shell                            │
└───────────────────────────────────────────────────────────────┘

┌ MAIN SHELL (role-filtered) ──────────────────────────────────┐
│ 5 max primary tabs (role-dependent, §4)                       │
│ Floating EMERGENCY action (always present, exempt from tabs)  │
│ Global search in app bar                                      │
└───────────────────────────────────────────────────────────────┘

┌ CONTENT AREAS (feature-first folders) ───────────────────────┐
│ Health  → dashboard, meds, records, appointments, consent     │
│ Blood   → hub, requests, donor, history                       │
│ Community → feed, posts, education                            │
│ Messages → chats (doctor/healthcare vs community discussion)  │
│ Donations → campaigns, giving, receipts                       │
│ Profile → account, security, privacy, settings, help          │
└───────────────────────────────────────────────────────────────┘
```

**Grouping rules**
- **Home** = role-relevant start screen (patient: status summary; doctor:
  schedule; donor: blood hub prompt). Never overloaded (§9).
- **Health** (patient-only cluster) contains medication, appointments,
  symptoms, records, timeline, consent.
- **Blood** is a hub shared by patients (request side) and blood donors
  (donate side) with role-filtered landing.
- **Messages** is a top-level destination only for roles that chat
  (patient↔doctor, doctor↔patient). Community discussions stay in Community.
- **Donations** groups campaigns + giving + receipts (financial donors,
  organizations, and patients who donate).
- **Notifications** is reached from the shell app-bar bell and profile; it is
  not a tab (fewer tabs, G7).
- **Education** lives under Community (curated vs community content clearly
  segregated), plus deep links from health topics.

---

## 4. Navigation Architecture

Full routing rules, guards, deep links are defined in `mobile-navigation.md`.
Summary:

- **Auth stack** (pre-auth): Splash → Welcome → Login/Register → verification
  → MFA → Main Shell. Login required except public data listed in §30.
- **Main shell**: Material bottom-navigation with **≤5 destinations** chosen by
  role; on tablets (>600dp) a `NavigationRail`. Emergency action floats
  *outside* the destination list (§10).
- **Navigation guards**: (1) auth — no token → Login; (2) session expiry →
  refresh, on failure → Login with friendly message; (3) role/permission guard
  per screen via the 3.5 permission codes — **UI guards are UX, not security**;
  screens still expect backend to enforce (1) every sensitive request.
- **Deep links**: relative paths mirror API routes (e.g. `/blood/requests/{uid}`,
  `/emergency`, `/medical-records/{uid}`, `/consents/{id}`) so a push tap or
  QR opens the exact record. Sensitive deep links require an authenticated
  session; the screen still re-verifies with the API.
- **Unauthorized behaviour**: instead of a dead-end, show a "You don't have
  access to this." state that offers "Go back to Home" — never imply the data
  exists (IDOR-safe UX, mirrors API 403/404 policy AD-6).

---

## 5. Role-Aware Navigation

Destination membership is driven by **backend role + permission codes** (3.3),
evaluated from the `/users/me` profile + a per-session permission set returned by
the API at login. Derivation (final, not from prompt examples blindly):

| Destination | Patient | Doctor | Staff | Caregiver | Blood Donor | Fin. Donor / Org |
|---|---|---|---|---|---|---|
| Home | ✓ | ✓ day-view | ✓ | ✓ | ✓ | ✓ |
| Health | ✓ own | ✗ (enters via Patient records) | ✗ | ✓ authorized only | ✗ | ✗ |
| Blood hub | ✓ (request side) | ✗ | ✓ (facility records) | ✗ | ✓ (donor side) | ✗ |
| Community | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| Messages | ✓ (doctor chats) | ✓ (patient chats) | ✓ (facility) | ✓ (with patient) | ✗ | ✗ |
| Donations | ✓ (giving allowed) | ✗ | ✗ | ✗ | ✗ | ✓ |
| Notifications (bell) | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| Profile/Settings | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |

Rules:
- Doctor/Staff **never** see a "Health" tab; they reach a patient's records only
  through an explicitly authorized patient list (`DOCTOR patients *` — a patient
  is not visible merely because it exists).
- Caregiver sees the health of a **linked patient** with a persistent
  "Viewing: [Patient Name]" banner (C18 requirement) plus consent-expiry status.
- Blood Donor landing lists **eligible** requests only (backend C8/C9 scoping).
- One tab max default set of 5; any role with >5 gets a "More" overflow tab into
  `PROFILE` → destinations.
- Empty permissions → still see Home + notifications + profile; every other
  destination hidden (no broken dead-end tabs).

---

## 6. Design System

Brand colours: **Dark Blue · Blue · Red · White**. Red is **reserved** for
emergency, danger, critical and strong-warning only — it is never a primary
brand colour in normal surfaces. (The current scaffold uses red as primary —
this is corrected here and flagged in the review.)

| Token role | Light (default) | Dark | Usage |
|---|---|---|---|
| primary | `#0D47A1` Dark Blue | `#5C9BE8` | Brand, app bar, primary buttons, active nav |
| secondary / on-primary | `#1976D2` Blue / `#FFFFFF` | `#90CAF9` / `#0B1A33` | Secondary controls, links, highlights |
| accent | `#C62828` Red | `#EF5350` | **Emergency/danger/critical/warning-strong only** |
| danger/error | `#D32F2F` | `#EF5350` | Errors, destructive, failed states |
| success | `#00897B` teal | `#4DB6AC` | Success, confirmed, resolved, healthy |
| warning | `#F9A825` amber | `#FFB74D` | Warnings, pending attention |
| info | `#1565C0` | `#64B5F6` | Informational, neutral notices (never critical) |
| background | `#F6F9FC` | `#0C1626` | Scaffold |
| surface | `#FFFFFF` | `#152131` | Cards, sheets, dialogs |
| surface-variant | `#EDF2F8` | `#1E2D42` | Chips, dividers, hollow areas |
| text-primary | `#12202F` | `#E8EDF4` | Body |
| text-secondary | `#5C6B7A` | `#9FB0C3` | Secondary, captions |
| text-on-red / on-blue | `#FFFFFF` | `#FFFFFF` | Contrast text on accent/primary |
| disabled (fg/bg) | `#9AA7B8` / `#E9EEF5` | `#5C6B7A` / `#233549` | Disabled controls |
| border | `#DCE4EE` | `#2B3D55` | Input borders |
| divider | `#E5EAF1` | `#22344C` | Dividers |
| scrim | `#66000A1E` | `#99000000` | Modal scrim |
| emergency-bg | `#FBE7E7` | `#3B1820` | Emergency surface tint (label + strong border, never alone) |
| focus-ring | `#0D47A1` | `#90CAF9` | Keyboard/accessibility focus |

Rules:
- Emergency/danger states MUST pair colour with icon **and** text (never colour
  alone — §25).
- Success/confirmed uses teal; red is not used for "positive" confirmation.
- Contrast verified for AA (4.5:1 body, 3:1 large text/UI).

---

## 7. Typography

Default system stacks (Roboto on Android, SF Pro on iOS) — no web font
download cost, matures with OS accessibility (AD-MD-7). Optional bundled
variable font as future enhancement.

| Style | Size/spacing | Weight | Usage |
|---|---|---|---|
| Display (H1) | 32 / 40 | 700 | Welcome/splash hero only |
| Headline (H2) | 24 / 32 | 700 | Screen titles, dashboard numbers |
| Title (H3) | 20 / 28 | 600 | Card titles, section headers |
| Subtitle | 16 / 24 | 600 | Sub-sections, list headlines |
| Body | 16 / 24 | 400 | Reading text (16 min) |
| Body-emph | 16 / 24 | 600 | Key values (blood group, dose) |
| Caption | 12 / 16 | 400 | Metadata, timestamps, legal (12 min) |
| Label | 14 / 20 | 500 | Buttons, chips, form labels |
| Overline | 11 / 16 | 500 | Hints, small badges (11 min; larger in a11y) |

- **Scaling**: all text scales with the OS `textScaleFactor` (no `maxLines` that
  truncate content or fixed heights on text containers). Buttons/inputs grow.
- Never use all-caps for long strings; Kiswahili translations commonly run
  longer — allocate flexible width (AD §38).
- Numbers (doses, units, countdowns) always `Body-emph`/tabular figures for
  legibility.

---

## 8. Components

Component-driven system (catalog with specs in `mobile-component-catalog.md`).
Consistent state model for every interactive component:
`idle → loading → success | empty | error`, retry where applicable.

Core set:
- **Buttons**: `AppPrimaryButton` (Filled, 48+ h), `AppSecondaryButton`
  (tonal/outlined), `AppTextButton`, `AppIconButton`, `DangerButton`,
  `EmergencyButton` (FAB + banner variant), `LoadingButton` (spinner swap),
  `ConcernDrawerButton` (confirmed+destructive style).
- **Cards**: `FeatureCard` (existing, restyled to Blue family), `StatusCard`,
  `DataCard`, `RecordCard`, `SummaryCard`, `CampaignCard`, `RequestCard`,
  `ConversationTile`, `EducationCard`.
- **Inputs**: `AppTextField` (with label, error, helper, prefix/suffix, obscure
  toggle), `AppDropdown`, `AppSearchField`, `AppDatePicker`, `AppChipInput`,
  `OtpInput` (verification), `AmountInput` (TZS with formatting + min).
- **Pick/selection**: `AppChip`, `FilterChipRow`, `ChipBadge`,
  `SegmentedControl`.
- **Status**: `StateBadge` (maps domain state → semantic colour/icon, never raw
  colour alone), `StatusTimeline` (multi-step progress), `VerificationBadge`
  (doctor/campaign/facility ✓).
- **Surface**: `AppAppBar`, `EmergencyBanner`, `OfflineBanner`, `AppBottomSheet`,
  `ConfirmDialog`, `DestructiveDialog`, `NoticeBottomSheet`, `Snackbar`
  (success/error/info variants).
- **Navigation**: `BottomNavBar` (≤5, role-filtered), `NavigationRail` (>600dp),
  `EmergencyFab` (floating, app-wide), `ProfileDrawer`/`MoreMenu`.
- **States**: `EmptyState`, `ErrorState` (friendly + retry), `LoadingState`
  (skeleton for lists, spinner for actions), `SuccessState`, `NeedsUpdate`
  (offline/unsynced chip), `SensitiveLockState`, `AccessDeniedState`.
- **Charts**: `SimpleLineSpark` (symptoms/pain trend), `AdherenceRing`
  (supportive, non-clinical wording).

---

## 9. Home

Patient-style home (template; role variants in §17/§18). Structure and
priority order (top = most important):

```
AppBar: greeting + name, notification bell (badge)    ← always
Health/status summary card  (1 line, non-clinical)    ← e.g. "3 medications due today"
[ EMERGENCY action — persistent, see §10 ]             ← always visible ringtop
Next appointment / request status cards
Medication reminders card (today, ≤3)  → Medication [MEDT-001]
Blood request shortcut (patient) / eligible requests (donor)
Community highlights (1–2 curated posts) → Community
Education pick (1 article, topic-matched)
Donation opportunities (verified campaigns only)  → Donations
```

Rules (G7/G8):
- One primary action per card; at most ~5 cards + emergency.
- Cards surface **counts, not data walls**: "2 appointments this week",
  "3 doses done today" — details after tap.
- Emergency is a distinct, persistent red element with icon+label (never
  confused with navigation).
- Pull-to-refresh; skeleton load; offline card shows cached safe summary with
  "Retry" (not silent stale data).

---

## 10. Emergency UX

Emergency is a *workflow*, reaches the real emergency request API
(`/emergency/requests`, 3.5 §15), and is **not** a replacement for emergency
services. It is clearly branded:

- Red handled ONLY for: emergency/danger/critical/warning. Font + icon + label
  always accompany red (§25).
- Persistent **Emergency FAB** on all main-shell screens and home (never on
  auth/onboarding).

**Flow (10.1):** `EmergencyFab` (red, `sos` icon + "SOS") → **EMG-002
Confirmation sheet** (shows: What happens, automatic contact of linked
contacts, "This is not a replacement for dialling emergency services (112
TZ); if you need urgent medical help now, call your nearest facility or 112.")
→ press & hold-to-arm (accident-proof) → **EMG-003 Emergency request** (prefilled
from patient emergency profile; editable: urgency, location, notes; consent
checkbox to share emergency info with responders) → submit (idempotency key,
rate-limited by API) → **EMG-004 Status tracking** (CREATED→VALIDATING→ACTIVE→
RESPONDING→ESCALATED→RESOLVED mapped to `StatusTimeline`; live refresh) →
**EMG-005 Resolution** (clear "Request resolved" + next-steps + log entry).

**Safety rules:**
- Never an instantly-triggering single tap (long-press + confirm is default,
  AD-MD-4).
- A cancel path always visible on tracking screen (owner cancel).
- If offline: block with "Cannot reach emergency service — call 112 / your
  facility now" and show local emergency contacts as cards; **never** silently
  queue an emergency request.
- Emergency banner appears at top of tracking screen explaining current step.
- Seizure-safe: no flashing animations, reduced motion honoured (§25).

---

## 11. Blood Donation UX

Hub split by role at first top-level route (`/blood/donors/me` vs
`/blood/requests`, backend-scoped).

**Patient/request-side (11.1)**
- My requests list with status badges (`CREATED→VERIFIED→ACTIVE→FULFILLED→
  CLOSED`, plus `CANCELLED/REJECTED`).
- Create request form (`BLOOD-002`): patient info, blood group (from own
  profile, read-only default), hospital/facility (picker of verified), units,
  urgency (segmented control), caregiver contact, notes → submit (idempotency).
- Request detail + status tracking; **matches appear only when backend allows**
  (C8/C9); match rows show blood-group needs never donor PII; respond to match
  (donor side) with "available / not now".
- Donation history (immutable events from facility, `BLOOD-007`).

**Donor-side (11.2)**
- Donor profile: blood group, location (privacy — shown to matches only as
  region/radius, never exact), availability toggle.
- Eligible request list = backend-filtered only (no scaping attempt in UI).
- Respond → confirm → history.
- **Privacy**: the app never displays another donor's phone/address to a
  patient; the facility mediates. UI simply reflects what API returns.

---

## 12. Health Dashboard

Dedicated patient health area (from `/health`), the "subject-matter core":

```
Health overview  → timeline summary (FR-SYM, health_timeline)
Medications     → [MEDT-001 list/reminders/adherence dashboard]
Symptoms        → log + simple trend chart (FR-SYM-001..005)
Pain tracking   → intensity (0-10) + timeline
Appointments    → [APP-*]
Medical records → [MED-*]
Health timeline → materialized timeline (3.4 health_timeline)
Consent & access→ [CONS-*] who-can-see-what
Education picks → topic-matched (sickle cell basics)
```

Rules:
- Non-clinical language; no diagnostic claims.
- Adherence shown as a supportive ring, never a grade or shame (§13).
- Medical content surfaces only on their own screens (records/consent),
  protected by privacy markers (§15/§30).

---

## 13. Medication UX

Workflow: `Meds list → Schedule → Reminder → Log dose → Missed dose → History →
Adherence summary`.

- **List/dashboard (MEDT-001)**: today's meds (Hydroxyurea, Folic Acid etc.),
  due times, dose-due badge; "Log dose" one-tap per medication with undo.
- **Add/edit med (MEDT-002)** + **schedule (MEDT-003)**: name, dose, unit,
  frequency/daily times, start, active toggle.
- **Reminder**: local scheduled notifications + FCM fallback (AD-MD-9); app-side
  snooze.
- **Log dose (MEDT-004)**: confirm "Taken" (idempotent `POST
  /medications/{id}/log-dose`); server-ack required before showing success.
- **Missed dose (MEDT-006)**: supportive, unconditional language — e.g.
  "No worries — take your next dose on time today." Never a red "missed!",
  never clinical judgement. Language switchable.
- **Adherence (MEDT-005)**: ring/percentage + trend, labelled "Your routine",
  explicitly non-diagnostic, shareable only via consent flows.

---

## 14. Appointment UX

- **List (APP-001)**: upcoming (top) vs past; **status badge** from server:
  `SCHEDULED→CONFIRMED→COMPLETED | NO_SHOW | MISSED`, `CANCELLED`.
- **Detail (APP-002)**: doctor/facility cards, date/time, status timeline,
  notes, actions allowed by state (confirm, reschedule, cancel, complete).
- **Request (APP-003)**: purpose dropdown, preferred date/time, doctor/facility,
  submit (idempotency) → pending confirmation from recipient.
- **Reschedule (APP-004) / Cancel (APP-005)**: cancellation = destructive→
  `DestructiveDialog` explaining "The slot will be released" and whether a fee/
  policy applies; confirm keeps copy of original.
- Reminder bell synced to local notifications (FR-APP-002).
- UI reflects exact backend transitions only (§42 state machines); a button is
  shown only when the current state permits the action.

---

## 15. Medical Records UX

Highly sensitive — a `Medical` privacy surface (lock icon + "Private" banner).

- **List (MED-001)**: own records; category chips; created-by label
  (self / doctor / facility) with authorship clarity (C15/C16).
- **Detail (MED-002)**: full record; attachments preview; "Ask to share /
  sharing" entry; created timestamp.
- **Document viewer (MED-003)**: in-app viewer; **no screenshots are surfaced**
  (no share/screenshot affordance; `FLAG_SECURE` window on OS where supported);
  files fetched via signed download URL (§32 of 3.5).
- **Access & sharing (CONS-*)**: "Who has access → What → Why → Until → Revoke"
  (§16). Access-history where backend provides it (`MED-007`).
- **No medical content appears** in public feed, push previews, or recents
  screenshots (§23/§30/§24).
- If a record is shared, UI shows an explicit "Shared with [name] until [date]"
  indicator and a one-tap Revoke reminder.

---

## 16. Consent & Privacy UX

Patient-facing consent made legible (no legal wall-of-text):

```
MY ACCESS — screen CONS-001
[Doctor A]   Medical Records · View   · until 30 Sep 2026
             [Revoke access]          (DestructiveDialog: "Doctor A will no
                                       longer be able to view your records.")
--------------------------------------------------------------
[Caregiver]  Medications · View+Log · until 31 Dec 2026
             [Revoke access]
+MORE: "Who can see my information"

CONSENT DETAIL (CONS-002): who · what (scopes) · why · since · until · Revoke
GRANT (CONS-003): choose person (verified doctor/staff/caregiver) → scopes
(e.g. Medications, Records) → purpose → expiry date → review summary → confirm.
```

- Wording plain: "They can see: Medications and appointments. They cannot see:
  your personal notes." instead of permission strings.
- Expiry shown as a human date + countdown; auto-expired consent highlighted as
  `EXPIRED` (still revocable).
- Revocation is immediate per API (`POST /consents/{id}/revoke`); UI confirms
  "Done — access removed now".
- Grant requires the patient's authenticated gesture; never granted by
  attachment alone (consent is an explicit action).

---

## 17. Doctor UX

Doctor-specific experience (no "Health" tab §5):

- **Dashboard (DOC-001)**: today's confirmed appointments, verification status
  banner (PENDING/VERIFIED/REJECTED), pending docs upload. Verification gating:
  unverified doctor can still use app but sees "Profile under review by our
  team" and cannot access patients (backend enforces; UI hides).
- **Patients (DOC-003)**: only patients from `/doctors/me/patients` — never
  browsable. Each row shows linkage + consent status; "No records" empty state
  is indistinguishable from "not authorized" (no data-leak hints).
- **Patient records (DOC-004)**: read-only for non-authors (unless the same
  doctor authored), with consent badge visible; clinical entry (`DOC-006`) for
  those with C15 scope.
- **Appointments (DOC-005)**: confirm/reschedule/complete/no-show per state.
- **Messages (CHAT-*)**: DOCTOR_PATIENT conversations only for linked+consented
  relationships.
- **Profile (PROFILE)**: professional profile edit, verification documents
  upload/review status.
- Education: optional CE content.

---

## 18. Caregiver UX

Caregiver acts for a linked patient with a consent card at top:

- **Always-visible "Viewing: [Patient Name]" banner** (role-of-context, C18)
  prevents cross-patient confusion; switching patients is explicit.
- **Invitations (CAR-002)**: accept/decline with clear scope explanation
  ("You'll be able to log medications for [Patient] until [date]").
- **Linked patients (CAR-003)**: list with consent scope + expiry countdown.
- **Authorized views**: reflection of `CONS` scope only (e.g. meds list/Log
  dose, appointments); medical record detail only where granted.
- **Permission/consent status (CAR-005)**: "You can see: Medications. You
  cannot see: Personal notes." + "Ask the patient to change this."
- **Remove relationship (CAR-006)**: patient-side destructive dialog; cleaner
  revokes immediately (API).
- Caregiver home mirrors the patient's safe info but never PHI in home summary
  without authorization from API.

---

## 19. Community UX

Public/social surface, fully separated from medical.

- **Feed (COM-001)**: verified-content badges on official & education posts;
  author labels; not medical.
- **Post detail (COM-002)** with comments, reactions; **create (COM-003)**
  (text; optional image ≤ limit; consent checkbox to publish).
- **Report (COM-005)** inline ("Report post") with simple reason chips →
  moderation queue (3.3 `community.moderate`).
- **Moderation states** mirrored: PUBLISHED / (author-edited) / hidden when
  moderated (`HIDDEN` shows "This post is no longer visible.").
- **Profile (COM-006)**: my posts, my reports status.
- No patient identifiers in created content by default; composer warns
  (best-effort, not enforcement): "Don't share personal medical information in
  posts."
- Community is **not** the channel for medical advice — a gentle, repeated
  notice distinguishes community discussion from verified education and from
  professional care (§39).

---

## 20. Chat UX

Two explicitly separated conversation types:

| Type | Purpose | Markers |
|---|---|---|
| Doctor/Healthcare | clinical follow-up (consented) | "Private" + doctor verified badge + consent scope banner |
| (No community chat on mobile in v1) | — | — |

- **List (CHAT-001)**: conversations with participant, last message, delivery
  & read ticks, unread badge; doctor threads show "Verified doctor" and cannot
  be confused with community.
- **Thread (CHAT-002)**: bubbles, timestamps, delivery ticks (sent→delivered→
  read), attachment chips (images/documents ≤ limit) via signed upload, composer
  (CHAT-003). Medical terms allowed only inside doctor conversations; composer
  is otherwise content-neutral.
- **Privacy rails**: no message content in push previews ("New message from Dr.
  X" only); no screenshot affordance within doctor threads; participant list
  restricted (C13).
- Polling now (3.5 AD-4) → websockets later; UI uses a `ConversationRepository`
  so transport can swap without screen changes.

---

## 21. Education UX

Curated, verifiable content (`FR-EDU-001..004`).

- **Categories (EDU-001)**: topics (Sickle-cell basics, crisis prevention,
  nutrition, exercise, careers/family planning, living well).
- **Library (EDU-002)**: cards with thumbnail, reading-time, type (article/
  video), verified-origin badge; search ED-*.
- **Detail (EDU-003)**: short summary first, then sections with clear headings;
  video player inline; "reading progress" saved locally; bookmark (EDU-005).
- **Language**: article content in EN with SW translations where provided;
  UI chrome fully localized (§38).
- Content authors are labelled (organization/verified educator), distinguishing
  official education from community posts.
- Offline: already-opened articles cached (safe, non-PHI) for re-reading.

---

## 22. Financial Donation UX

Clarity of states above all (FR-PAY, BR-007/008).

- **Campaigns (DON-001)**: verified campaigns only (badge); raised/target,
  days-left, urgency tier.
- **Campaign detail (DON-002)**: story, funds progress, verified org,
  "Donate now".
- **Donate (DON-003)**: preset + custom TZS amount, min set from campaign;
  **payment method (DON-004)** M-Pesa/AirtelMoney/TigoPesa/ClickPesa/Selcom
  (matches 3.5 AD-5); consent to share donation reference.
- **Confirmation (DON-005)**: explicitly distinguishes **"Donation initiated"**
  (payment pending) from **"Payment confirmed"** (only after backend webhook
  status). Sequence: initiating, waiting for provider, confirmed/failed.
- **Donation status (DON-006)**: `INITIATED→CONFIRMED | FAILED`; retry only on
  PENDING/FAILED with same idempotency key.
- **History (DON-007)** + **receipt (DON-008)** (only when confirmed).
- Never claim success client-side; the app trusts the API's webhook-verified
  status.

---

## 23. Notifications

- **Center (NOT-001)**: grouped by category (Medical, Appointments, Blood,
  Emergency, Community, Donations, System); unread/read; per-item tap deep-link
  (relative route §4).
- **Preferences (NOT-002)**: per-category on/off (except emergency →
  non-disableable per BR; UI explains why), quiet hours.
- **Preview privacy (G4/§30)**: previews are de-identified:
  - ❌ "Your sickle cell crisis record has been updated."
  - ✅ "You have a new health update."
  Emergency notifications stay alert-style but still avoid diagnosis detail.
- Push payload contains only localised short text + route; body renders from
  local text table.

---

## 24. Profile & Settings

- **Profile (PRO-001)**: name/avatar/role badges, blood group (patient),
  emergency contact shortcut.
- **Account (PRO-002)**: linked contact methods (email/phone) + verification
  status, active sessions mgmt.
- **Security (PRO-003)**: password change, MFA setup/manage, biometric app lock
  (local, optional; AD-MD-5), "log out all other devices".
- **Privacy (PRO-004)**: consent overview (→ CONS-001), data visibility
  summary, export of my data (API), sensitive-screen lock toggles.
- **Notification settings (PRO-006→ NOT-002).**
- **Language (PRO-007)**: English / Kiswahili (system-default + manual).
- **Help (PRO-008)**: FAQs, contacts, emergency numbers card.
- **Logout (PRO-009)**: confirm → revoke refresh token (aligned 3.5 auth/logout).
- **Deactivate (PRO-010)**: destructive, long confirm with clear consequences
  ("Your data is kept per policy; you can reactivate by contacting support").
- Settings persist locally for prefs; user/consent always server truth.

---

## 25. Accessibility

- **Targets**: ≥48×48 touch (≥44 iOS minimum); inputs/buttons/rows padded.
- **Contrast**: AA (4.5:1 text, 3:1 large/UI). Portuguese of emergency red:
  `#EF5350` on `#152131` still passes; large variants allowed.
- **Screen readers**: every icon has semantic label (icons never alone);
  status set via `Semantics` (e.g. "Dose logged"); live regions for
  confirmations; image alts.
- **Reduced motion**: respect `disableAnimations`; no pulsing emergency
  (seizure-safe); progress via text crumbs not flash.
- **Focus/keyboard**: full tab order (Android TalkBack, iOS switch control);
  form `textInputAction` chains; focus-ring visible (§6).
- **Text scaling**: all layouts reflow at up to 200%; no overflow; buttons grow.
- **Cognitive**: plain language, icons+text, no heavy jargon;
  Kiswahili/English togglable per screen; learn-mode help text.
- Error messages are actionable and human (§28).

---

## 26. Responsive Design

- **Layout modes** (Material breakpoints): compact (<600dp phone portrait),
  medium (600–840 portrait tablets), expanded (>840 landscape/tablet).
- `NavigationRail` at medium/expanded (tabs become rail items); grids resize;
  forms use 2-column where sensible ≥600dp.
- No fixed pixel widths/`SizedBox` with hard sizes on text-bearing widgets —
  relative layout + `Flexible`/`Expanded`.
- SafeAreas (notches/gesture bars); bottom nav guarded from home-indicator.
- Tablet: content re-flows, never scales-up phone layouts awkwardly; chart
  sparklines get more width; card columns 2-up.
- Test matrix: 5.0" / 6.1" / 6.7" Android, iPhone SE / 14 family, iPad &
  10" Android tablet.

---

## 27. Offline / Poor-Network UX

Reality of Tanzanian networks — design for degraded mode, never silent loss:

- **Global surface**: `OfflineBanner` atop shell when no connectivity;
  pull-to-refresh everywhere; timeouts (~10s default) with retry.
- **Cached safe data** (local, encrypted for tokens; plaintext only for
  non-sensitive): role destinations, education articles opened, campaign
  summaries, medication names/labels. Medical obs never cached without
  encryption; display labelled "May be out of date".
- **Queued non-sensitive writes** (e.g. reaction, reach) with visible
  "Pending sync" chip; **sensitive writes never silently queued** — show
  "Couldn't reach the server. Your action was not sent." with Retry, and keep
  the draft.
- **Drafts**: forms auto-save drafts locally (registration, blood request,
  appointment, donation, post) so nothing is lost; restore on reopen.
- **Confirmations**: a success state only appears when the server acked
  (idempotency keys reused on retry to avoid dupes).
- Emergency offline behavior is explicit (§10): never claim sent, show direct
  call actions.

---

## 28. Error Handling

Every important screen: `loading → success | empty | error` + retry.

- **User-facing messages** are plain and actionable; technical detail goes to
  logs/crash reports only (correlation not shown to user).
- Error code map (from 3.5 §26 envelope errors):
  - `NETWORK` → "Can't reach the server. Check your connection."
  - `AUTH_*`/session → login redirect with "Please sign in again."
  - `PERMISSION_*`/403 → friendly "You don't have access to this." (no
    existence hint).
  - `CONSENT_*`/409 → "Access to this was revoked." with option to request
    access.
  - `VALIDATION_*`/422 → inline field errors, first-focus.
  - `THROTTLED`/429 → "Too many attempts. Try again in a few minutes."
  - 5xx/known → "Something went wrong on our side. Please try again." + retry.
- Toast/snackbar variants: success (teal), error (red, icon+text), info (blue).
- Destructive confirmations repeat the exact consequence in the dialog §42.

---

## 29. Security UX

Aligns with backend; never contradicts it.

- **Login** with email/phone + password; password managers supported;
  show/hide toggle; MFA flow (TOTP 6-digit) when enabled.
- **Session expiry**: on 401, silent refresh (access+refresh) once; on failure,
  friendly re-auth screen (no data loss; route preserved).
- **Logout** everywhere accessible; device/session management list (revoke
  session) — mirrors `/auth/sessions`.
- **Biometric lock** (local_auth) as app-level & sensitive-screen protection,
  *optional*; biometric is never the sole auth to server.
- **Sensitive screen protection**: `FLAG_SECURE` where OS allows (recents
  screenshot blur) for records/consent/doctor-chat; no share affordances.
- **Confirmations** for every critical/destructive action (§42).
- Passwords/reset tokens never echoed; input `autofillHints` set.

---

## 30. Privacy UX

- Sensitive surfaces carry explicit markers: `Medical Records · Private`,
  `Consent · Private`, `Messages · Private` (lock icon + text, not icon-only).
- No PII in URLs (UUIDs), push previews, notifications, app recents, or
  community content defaults.
- Permission prompts are explained before asking (location, camera, biometrics).
- Donation/emergency consent checkboxes are explicit user actions, default-off
  where sensitive.
- Data flows on screen are visible: "This information is stored on the secure
  server"; export/delete-my-data available (PRO-004).
- Accessibility to this design: Übmerged with §16/§29; a single "Privacy"
  hub gives one place to understand exposure.

---

## 31. Forms

Standard form contract (detailed table in `mobile-component-catalog.md` Appendix A).
Each field defined by: field · type · required · validation · error message ·
keyboard · sensitive · backend mapping. Core forms (all map to 3.5 endpoints):

| Form | Screen | Fields summary | Backend |
|---|---|---|---|
| Registration | AUTH-004 | names, email, phone, password, role_code | `POST /auth/register` |
| Login | AUTH-003 | identifier, password | `POST /auth/login` |
| Password reset | AUTH-007/008 | email/phone, code, new password | `/auth/password-reset/*` |
| Patient profile | PAT-002 | name, DOB, blood group, genotype | `PATCH /patients/me` |
| Doctor registration | DOC-002+ | professional info + verification docs | `POST /doctors/me/verification` |
| Caregiver invite | CAR-002 | caregiver contact, scopes, expiry | `POST /caregivers` |
| Blood request | BLOOD-002 | group (prefilled), facility, units, urgency | `POST /blood/requests` |
| Blood donor | BLOOD-004 | group, location, availability | `PATCH /blood/donors/me` |
| Emergency request | EMG-003 | prefill + urgency, location, notes, consent | `POST /emergency/requests` |
| Medical info (own) | MED-004 | title, category, notes (free text) | `POST /patients/me/medical-records` |
| Appointment | APP-003 | purpose, doctor/facility, date, time | `POST /appointments` |
| Donation | DON-003/004 | campaign, amount, method | `POST /donations` |
| Community post | COM-003 | text + optional image, publish consent | `POST /community/posts` |

Shared validation rules: no free-text phone without format hint (Tanzanian
+255), amount min basis, date-in-future for appointments, urgency enum, PHI
warning on medical free text retention.

---

## 32. State Management UX

- **Recommendation**: `flutter_riverpod` (recommended) with repositories; the
  scaffold has no state layer today — introducing Riverpod 2.0 is a deliberate
  choice balanced against "no new framework for popularity": it is selected for
  testability, subscription-friendly streams (chat/status), and automatic
  disposal. `Provider` is the acceptable lighter alternative (AD-MD-2).
- **Layers** per feature: `presentation/pages` · `presentation/widgets` ·
  `application/` (notifiers/controllers) · `domain/models` + `domain/repositories`
  (interfaces) · `data/` (api source, local source, impl).
- **One-way data flow**: screen reads provider state; actions call repo;
  repo → api → state update. Views never call API directly.
- **Async states** use the shared `AsyncValue` UI mapping (§28) so every screen
  inherits consistent loading/empty/error.
- Server state always authoritative: mutations rendered optimistically **only**
  where idempotent & non-sensitive (reactions, reach); medical/consent/payment
  mutations are pessimistic with server ack (G10).
- Same setup is reused by admin web (3.7) so patterns stay consistent.

---

## 33. API-to-UI Mapping

Full detailed matrix in `mobile-api-traceability.md`:
`Screen → User Role → Permission → API Endpoint → Database Resource → Security Rule`.
Summary of the heavy screens:

| AUI ID | Screen | API (3.5) | Permission/Condition |
|---|---|---|---|
| MAP-01 | Home summary | `GET /patients/me/dashboard` | own |
| MAP-02 | Health dashboard | `/patients/me/health-summary`, `/patients/me/timeline` | own |
| MAP-03 | Meds list/dose | `GET/POST /medications/*` | own |
| MAP-04 | Records | `/patients/me/medical-records/*` | own/C2/3 |
| MAP-05 | Consent | `GET /consents`, `POST /consents/{id}/revoke` | own (patient) |
| MAP-06 | Emergency | `POST /emergency/requests`, `GET /emergency/requests/{id}` | C14 own |
| MAP-07 | Blood request | `POST /blood/requests`, `GET /blood/requests/{id}/matches` | C8/C9 |
| MAP-08 | Donate/pay | `POST /donations`, `GET /payments/{id}`, webhook-confirmed | donor/campaign C11 |
| MAP-09 | Doctor patients | `GET /doctors/me/patients`, `GET /doctors/me/patients/{uid}/medical-records` | C2/3 |
| MAP-10 | Caregiver view | `GET /caregivers`, scoped `/patients/me/*` | C14; consent scope |
| MAP-11 | Messages | `GET/POST /chat/conversations/*` | C13/C13b |
| MAP-12 | Community | `GET/POST /community/*`, reports | `community.*` |
| MAP-13 | Education | `GET /education/*` | public (verified) |
| MAP-14 | Campaigns/donations | `GET /campaigns`, `GET /donations` | verified/public + C11 |

No screen depends on an API that does not exist; anything proposed that would
need a new endpoint is marked **FUTURE** in §40 rather than wired.

---

## 34. Role-to-Screen Matrix

`VISIBLE` / `CONDITIONAL` (role + permission/consent/context-gated) / `HIDDEN`
(admin on mobile → 3.7 web; non-relevant roles). Full matrix in
`mobile-navigation.md` §5. Summary kernel:

| Screen group | Patient | Doctor | Staff | Caregiver | Blood Donor | Fin.Donor |
|---|---|---|---|---|---|---|
| AUTH-* | —(login) | — | — | — | — | — |
| HOME-001 | VISIBLE | VISIBLE | VISIBLE | VISIBLE | VISIBLE | VISIBLE |
| PAT-*/HEALTH | VISIBLE (own) | HIDDEN | HIDDEN | CONDITIONAL | HIDDEN | HIDDEN |
| MED-*/CONS | VISIBLE (own) | CONDITIONAL | CONDITIONAL | CONDITIONAL | HIDDEN | HIDDEN |
| MEDT-* | VISIBLE | HIDDEN | HIDDEN | CONDITIONAL | HIDDEN | HIDDEN |
| APP-* | VISIBLE | VISIBLE | VISIBLE | CONDITIONAL | HIDDEN | HIDDEN |
| BLOOD-* | CONDITIONAL(req) | HIDDEN | CONDITIONAL(rec) | HIDDEN | VISIBLE(donor) | HIDDEN |
| EMG-* | VISIBLE | VISIBLE(responder) | VISIBLE | VISIBLE | VISIBLE | VISIBLE |
| DOC-* | HIDDEN | VISIBLE | CONDITIONAL | HIDDEN | HIDDEN | HIDDEN |
| CAR-* | VISIBLE(req) | HIDDEN | HIDDEN | VISIBLE | HIDDEN | HIDDEN |
| COM-* | VISIBLE | VISIBLE | VISIBLE | VISIBLE | VISIBLE | VISIBLE |
| CHAT-* | VISIBLE | VISIBLE(patient) | CONDITIONAL | VISIBLE | HIDDEN | HIDDEN |
| EDU-* | VISIBLE | VISIBLE | VISIBLE | VISIBLE | VISIBLE | VISIBLE |
| DON-* | VISIBLE(giving) | HIDDEN | HIDDEN | HIDDEN | VISIBLE | VISIBLE |
| NOT-* | VISIBLE | VISIBLE | VISIBLE | VISIBLE | VISIBLE | VISIBLE |
| PRO-* | VISIBLE | VISIBLE | VISIBLE | VISIBLE | VISIBLE | VISIBLE |
| ADMIN-* | HIDDEN | HIDDEN | HIDDEN | HIDDEN | HIDDEN | HIDDEN |

UI visibility is UX, not security — backend remains authoritative (§4).

---

## 35. Screen Inventory

Complete catalogue with per-screen: ID, name, purpose, role, entry point,
exit nav, API deps, permissions, sensitive data, components, states, validation,
a11y, error handling — in `mobile-screen-inventory.md`. Screen-ID scheme:
`AUTH-`, `HOME-`, `PAT-`, `MED-`, `MEDT-`, `APP-`, `BLOOD-`, `EMG-`, `DOC-`,
`CAR-`, `COM-`, `CHAT-`, `EDU-`, `DON-`, `NOT-`, `PRO-`, `SRCH-`, `CONS-`,
`ADMIN-` (hidden).

---

## 36. Flutter Architecture Mapping

Maps design → `apps/mobile` (current scaffold: presentation-only stubs; see
review for the gap assessment). Target structure per feature (feature-first,
aligned to 3.2 modules + existing `features/`):

```
lib/
├── core/
│   ├── config/        (env: baseUrl, features, provider list)
│   ├── constants/     (existing app_colors/app_strings → tokens, ARB keys)
│   ├── network/       (dio client, auth interceptor, retry, idempotency)
│   ├── security/      (secure_storage, biometric, FLAG_SECURE)
│   ├── storage/       (local cache, drafts, encryption)
│   ├── routing/       (go_router + guards)
│   ├── theme/         (tokens → AppTheme light/dark)
│   └── utils/
├── features/
│   ├── auth/          (AUTH-*)
│   ├── home/          (HOME-001)
│   ├── profile/       (PAT-002, PRO-*, CONS-*)
│   ├── medical/       (health dashboard, MED-*, MEDT-*, SYM)
│   ├── appointments/  (APP-*)
│   ├── blood/         (BLOOD-*)
│   ├── emergency/     (EMG-*)
│   ├── doctors/       (DOC-*)
│   ├── chat/          (CHAT-*)
│   ├── donations/     (DON-*)
│   ├── community/     (COM-*)
│   ├── education/     (EDU-*)
│   ├── notifications/ (NOT-*)
│   └── admin/         (HIDDEN → removed from mobile nav; moved to 3.7)
└── shared/
    ├── widgets/       (catalog components)
    ├── models/        (DTOs mirrored to API contracts)
    └── services/      (notifications, i18n, analytics)
```

- Existing structure is sound (feature-first, core/shared/features) **kept**.
- Missing layers to add in Stage 4: `core/network`, `core/security`,
  `core/storage`, `core/routing`, `data`+`domain` per feature, l10n.
- `core/constants/app_colors.dart` and `app_theme.dart` get **rebuilt as
  token-driven** (design system §6/§37); `app_strings.dart` becomes ARB l10n.
- Existing reusable widgets (`feature_card`, `app_icon`, placeholder) stay and
  are restyled, not deleted (design review: no deletion of existing work).

---

## 37. Design Tokens

Implemented in Stage 4 as typed constants (Dart `abstract final class`), feeding
Material themes. Values per §6 colors; the rest:

| Token group | Tokens | Default values |
|---|---|---|
| spacing | spX | 4, 8, 12, 16, 24, 32, 48 (multiples of 4) |
| radius | rX | 4 (small), 8 (default), 12 (cards), 16 (sheets), 24 (hero/dialog) |
| elevation | eX | 0 flat, 1 (1dp subtle), 2 (2dp cards), 3 (4dp sheets), 4 (8dp FAB/dialog) |
| icon size | icX | 16 sm, 20 md, 24 lg, 32 xl |
| component height | hX | 40 sm, 48 md (default tappable), 56 lg (inputs), 64 xl (buttons/hero) |
| animation | aX | 100ms micro, 200ms standard, 300ms emphasis, 500ms sheet |
| type | tsX | per §7 table |

Usage rules: radii/elevation conservative in medical context (low visual noise);
animations <300ms standard; reduced-motion override globally.

---

## 38. Internationalization

- **Langs**: English (`en`), Kiswahili (`sw`). Default = system, override in
  PRO-007 and stored locally.
- **All strings externalized**: `AppStrings` is removed in favor of generated
  ARB l10n (`flutter_localizations`); no user-facing literals in widgets.
- **Layout safety**: strings never clipped; Kiswahili expansions (~30% longer on
  buttons) handled by flexible layout + `TextScaler`; buttons ≥48 grow.
- Translation sets required UI-chrome + all accessibility labels + error
  messages; medical content translation is editorial (article-level), separate
  from chrome (tracked in EDU import).
- New strings require both locales before merge (CI gate).

---

## 39. Trust & Safety

Clear source-of-truth labels across every content surface:

| Content type | Badge/label | Never confused with |
|---|---|---|
| Official education | "Verified education · [Org]" | community post |
| Community post | "Community" + author handle | education/medical advice |
| Professional communication | "Private · Doctor [name] (verified)" | community discussion |
| Emergency request | distinct red "EMERGENCY REQUEST" | ordinary health feature |
| System notification | "System" icon | push from a person |
| Campaign | "Verified campaign" | unvetted fundraising (C11) |

- Emergency actions are visually and textually distinct (§10).
- No community/education content is presented as medical advice; a reusable
  "This is not medical advice" note on education & community.
- Doctors display verification status; unverified author contact is never
  presented as "Dr." unless verified (label reflects backend).

---

## 40. Innovation Layer

Evaluated innovations — each with problem/benefit/data/privacy/API/db/complexity.

| Innovation | Problem | Benefit | Data req. | Privacy | API impact | DB impact | Complexity | Class |
|---|---|---|---|---|---|---|---|---|
| Personalized health education | generic content, low engagement | topic-matched articles | own profile + edu history | PHI in match logic (consent) | reuse `GET /education/content` + local | none | Low | **CORE** |
| Blood match quick-respond | donors miss matches | one-tap respond | own donor profile | donor PII stays backend | reuse `/blood/*` | none | Low | **CORE** |
| Emergency readiness card | panicked users waste time | pre-filled draft request + contacts | own emergency profile | user-owned | reuse `/emergency/*` | none (local draft) | Low | **FUTURE** |
| Health timeline | scattered data | single chronological view | own records | own-only | reuse `/patients/me/timeline` | (3.4 `health_timeline`) | Med | **CORE** |
| Adherence insights (supportive) | motivation for routine | gentle trend, no shame | own medication events | own-only, non-clinical | reuse `/medications/stats` | none | Low | **FUTURE** |
| Caregiver coordination board | split effort | shared task view | consent scopes | consent-gated | reuse `/caregivers`, `/patients/me/*` | none | Med | **CORE** |
| Smart reminder batching | notification fatigue | context-aware med reminders | schedule + quiet-hours | local pref | reuse `/medications/*` notifications | none | Med | **FUTURE** |
| Crisis preparedness checklist | families unprepared | guided checklist + contacts | local | none | none (offline feature) | none | Low | **FUTURE** |
| Localized education (SW) | language barrier | SW articles | edu catalog | none | reuse `/education/*` | catalog data | Med | **CORE** |

Rules: `CORE` innovations may integrate in the screen inventory; `FUTURE` items
are documented, marked FUTURE, and do not affect the approved architecture or
add endpoints now. AI assistant (3.5 AD-2) remains **FUTURE** until decided.

---

## 41. Open Design Decisions

Deferred decisions for Stage 4 (mirror/inherit 3.5 AD-1..AD-11 where relevant):

| # | Decision | Recommended default |
|---|---|---|
| MD-1 | Navigation library | `go_router` (deep links + guards) — replaces static NamedRoutes |
| MD-2 | State management | `flutter_riverpod` (alt: `Provider` if team prefers minimal) |
| MD-3 | Primary destinations cap | 5 tabs max + Emergency FAB + notification bell |
| MD-4 | Emergency trigger | press-and-hold + explicit confirm sheet (accident-proof) |
| MD-5 | Biometric app lock default | OFF by default; opt-in for app + sensitive screens |
| MD-6 | Offline cache scope | Non-sensitive only; encrypted for tokens; drafts local |
| MD-7 | Font | System default (Roboto/SF); optional variable font FUTURE |
| MD-8 | Dark mode default | Follow system; overridable; tokens approved §6 |
| MD-9 | Medication reminders | Local scheduled notifications (primary) + FCM (fallback) |
| MD-10 | Chat transport | Polling v1 (3.5 AD-4) → websockets when needed |
| MD-11 | AI assistant | FUTURE (3.5 AD-2) — hidden until approved |
| MD-12 | Admin on mobile | HIDDEN — moved to admin web (3.7) |
| MD-13 | Donation provider list | 3.5 AD-5 set, config-driven |
| MD-14 | Verification UI for patient-created records | Show "unverified" tag (C16) — detail pending 3.5 AD-12 |

---

## 42. UI State Machines (extension)

UI must render only backend states (3.5 sections referenced). Badge mapping via
`StateBadge` (color+icon+label; red only where truly critical):

| Domain | States to render | UI badge semantics |
|---|---|---|
| Appointment | SCHEDULED · CONFIRMED · COMPLETED · NO_SHOW · MISSED · CANCELLED | pending(amber)/confirmed(blue)/done(teal)/missed(neutral-warn)/cancelled(gray) |
| Blood request | CREATED · VERIFIED · ACTIVE · FULFILLED · CLOSED · CANCELLED · REJECTED | progress timeline (`StatusTimeline`) |
| Blood match | from matrix: response accepted/declined | donor-side actions only when ACTIVE |
| Emergency | CREATED · VALIDATING · ACTIVE · RESPONDING · ESCALATED · RESOLVED · CANCELLED | step timeline; ESCALATED = warning not red-red critical |
| Consent | DRAFT · ACTIVE · REVOKED · EXPIRED | active(blue)/revoked(gray)/expired(amber) |
| Caregiver | PENDING · ACTIVE · DECLINED · REMOVED | active(blue)/pending(amber)/removed(gray) |
| Campaign | DRAFT · PENDING_VERIFICATION · VERIFIED · ACTIVE · CLOSED | verified badge; PENDING shows "under review" |
| Donation | INITIATED · CONFIRMED · FAILED · REFUNDED | initiated(amber)/confirmed(teal)/failed(red)/refunded(blue) |

Actions shown only when the current state permits (mirror 3.5 §13/§15).

## 43. Confirmation & Destructive Actions (extension)

Actions requiring explicit confirm dialog (with consequence text):

| Action | Dialog type | Consequence copy (mandated) |
|---|---|---|
| Revoke consent | Destructive | "Doctor A will no longer be able to view your records." |
| Cancel appointment | Destructive | "Your slot will be released. You can book again anytime." |
| Cancel emergency request | Destructive | "Responders will be told the request is cancelled." |
| Remove caregiver | Destructive | "They will lose access to [patient]'s information immediately." |
| Log out | Confirm | "You'll need to sign in again." |
| Deactivate account | Destructive (long-form) | "Your data stays per policy; reactivation requires support." |
| Delete post | Destructive | "This post will be removed from your profile." |
| Emergency arm | Confirm (E-step) | see §10 (arm+confirm, not accidental) |

Close affordances always present; destructive buttons red + icon; **no** double
NFC-style hidden toggling.

## 44. Figma-Ready Spec (extension)

Per major screen, `.spec` blocks are defined in the inventory
(`mobile-screen-inventory.md` §spec): layout hierarchy (tree), component
hierarchy (references catalog IDs), spacing (tokens), typography (tokens),
buttons/cards/icons/nav (catalog refs), interaction (gestures/transitions),
states (AsyncValue map). No pixel-perfect over-specification — measurements
are token-based and rationale-driven.

---

END OF STAGE 3.6 MAIN DESIGN DOCUMENT — gate decision in
`mobile-ui-ux-review.md`; companion files:
`mobile-navigation.md` · `mobile-screen-inventory.md` ·
`mobile-component-catalog.md` · `mobile-api-traceability.md`.