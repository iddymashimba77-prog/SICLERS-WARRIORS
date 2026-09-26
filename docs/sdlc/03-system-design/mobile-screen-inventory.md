# 3.6 Mobile Screen Inventory & Specs

> Complete screen inventory for Stage 3.6. Every screen: **ID · name · purpose ·
> roles · entry point · exit/navigation · API dependencies (3.5 endpoint matrix code)
> · permissions (3.3 catalog/conditions) · sensitive data · components (catalog
> refs `mobile-component-catalog.md`) · states · validation · accessibility ·
> error handling**. Companion to `mobile-ui-ux-design.md`, `mobile-navigation.md`,
> `mobile-api-traceability.md`.
>
> State ladder = shared `AsyncView` states (loading → success | empty | error) +
> specific `sync/offline` states. `HIDDEN` = not on this platform (admin → 3.7 web).
>
> Endpoint codes: `EP1`-class shorthand — full rows in `mobile-api-traceability.md`.

Legend: **WP** = Write path (pessimistic, server-ack), **RO** = Read path.

---

## AUTH — Authentication (auth feature)

### AUTH-001 Splash
- Purpose: brand, session bootstrap check.
- Roles: all (pre-auth).
- Entry: app launch (deep-link safe). Exit: → AUTH-002 (no session) or → Main shell (valid session).
- API: `GET /users/me` (session probe; silent refresh). Permission: public/pending auth.
- Sensitive: none.
- Components: `AppIcon`, display text, `LoadingState`.
- States: loading → token ok (shell) | no token (welcome) | refresh fail (welcome).
- Validation: n/a. A11y: announce app name; no animations beyond 300ms.
- Error: silently continue to Welcome (no error to user at splash).

### AUTH-002 Welcome
- Purpose: onboarding intro, language shortcut, en → login/register.
- Roles: all pre-auth. Entry: AUTH-001. Exit: → AUTH-003 / AUTH-004.
- API: none. Permission: public.
- Sensitive: none.
- Components: `AppAppBar`-less hero, `AppPrimaryButton`, `AppTextButton`, language switcher.
- States: static. A11y: headings + alt on hero.
- Error: none.

### AUTH-003 Login
- Purpose: sign in (identifier + password / phone+OTP).
- Roles: all. Entry: AUTH-002. Exit: → verification if required → Main shell; → AUTH-007 reset.
- API: `POST /auth/login`, `POST /auth/refresh`. Permission: public (rate-limited 5/min).
- Sensitive: password (obscured, `FLAG_SECURE` off). Components: `AppTextField` x2, `AppPrimaryButton` (loading swap), `VerificationBadge` hint.
- States: idle → loading → success (shell) | error inline.
- Validation: email/phone format, password ≥8; error message plain ("Enter your email or phone"). Keyboard: email/phone + password (ASCII).
- A11y: labels + `autofillHints`; error read via live region.
- Error: slow network → friendly retry; `AUTH_*` wrong-creds → "Email, phone or password is incorrect."

### AUTH-004 Registration
- Purpose: create account, choose self-registerable role (patient/caregiver/blood donor/financial donor; doctor → docs flow).
- Roles: pre-auth. Entry: AUTH-002. Exit: → AUTH-005/006 verification → shell.
- API: `POST /auth/register`. Permission: public.
- Sensitive: password, phone. Components: form fields (§A), role picker (`SegmentedControl`), submit.
- States: idle → loading → success (verification) | error.
- Validation: required name/email/phone/password (≥8, letters+numbers), consent-check free-text none sensitive beyond phone; keyboard numeric for phone.
- A11y: grouped semantics, per-field error focus. Error: duplicate account → "An account with this email or phone already exists."

### AUTH-005 Email Verification
- Purpose: verify email via code (FR-AUTH-004).
- API: `POST /auth/verify/email`. Permission: public (token/code).
- Components: `OtpInput`, resend link. States: loading→success/error. A11y: OTP announce.

### AUTH-006 Phone Verification
- Purpose: verify phone (needed for emergency/blood-donor flows).
- API: `POST /auth/verify/phone`. Similar to AUTH-005.

### AUTH-007 Password Reset Request
- Purpose: request reset. API: `POST /auth/password-reset/request` (always 202).
- Design: always "If an account exists, a code was sent." (no account enumeration).

### AUTH-008 Password Reset Confirm
- Purpose: set new password with code. API: `POST /auth/password-reset/confirm`; → login.

### AUTH-009 MFA Setup/Enable
- Purpose: enrol TOTP. API: `POST /auth/mfa/setup`, `POST /auth/mfa/enable`.
- Sensitive: secret; encrypted local. Components: QR, `OtpInput`, confirm.

### AUTH-010 Session Management
- Purpose: list/revoke sessions. API: `GET /auth/sessions`, `DELETE /auth/sessions/{id}`.
- Roles: all. Destructive: revoke → `DestructiveDialog`.

---

## HOME — Home (home feature)

### HOME-001 Home Dashboard
- Purpose: role-aware start screen (template §9 main doc; variants §17 doctor / §18 caregiver).
- Roles: all. Entry: shell. Exit: any destination via cards + tabs + Emergency FAB.
- API: `GET /patients/me/dashboard` (patient) / `GET /doctors/me` + `GET /doctors/me/appointments` (doctor) / `GET /blood/requests` eligible (donor).
- Permissions: own scope; `home.view` implicit.
- Sensitive: minimal summary only (counts; no diagnosis in headline).
- Components: `AppAppBar` (bell), `SummaryCard`, `FeatureCard`, `EmergencyFab`, `OfflineBanner`, `EmptyState`.
- States: loading skeleton → success | empty (no data yet → friendly onboarding prompt) | error (retry).
- Validation: n/a. A11y: semantic order = greeting→status→emergency→cards.
- Error: network → `ErrorState` + retry; partial failure → per-card "Couldn't load".

---

## PAT — Patient health (medical feature)

### PAT-001 Health Dashboard
- Purpose: health area root (patient).
- Roles: patient (own), caregiver (conditional). Entry: tab/rail.
- API: `GET /patients/me/health-summary`, `GET /patients/me/timeline`.
- Permissions: own / consent scope. Sensitive: PHI — privacy banner "Private".
- Components: `SummaryCard`, charts, `StatusCard` (meds/appts), education picks, `SensitiveLockState` (optional lock).

### PAT-002 Patient Profile
- Purpose: profile (name, DOB, blood group, genotype, emergency contact).
- API: `GET/PATCH /patients/me`, `GET/PATCH /patients/me/emergency-contact`; photo `PUT /patients/me/profile-photo`.
- Permissions: `patients.view/update_own`. Sensitive: PHI.
- Components: avatar edit, `AppTextField`s, `AppDropdown`s (blood group/urgency), save.

### PAT-003 Emergency Contacts
- Purpose: manage emergency contacts. API: `GET/PATCH /patients/me/emergency-contact`; serves EMG prefill.

### PAT-004 Health Summary Card (embedded in HOME/PAT-001)
- Purpose: 1-line non-clinical status. Data: counts (meds due, appts, unread).

### PAT-005 Health Timeline
- Purpose: chronological health_timeline view. API: `GET /patients/me/timeline`.
- Permissions: own / consent. Sensitive: PHI — timeline on private surface.

---

## MED — Medical records (medical feature)

### MED-001 Medical Record List
- Purpose: own records list, category chips.
- API: `GET /patients/me/medical-records`; clinician variant `GET /doctors/me/patients/{uid}/medical-records`.
- Permissions: own (O) / C2/3 (granted). Sensitive: high — "Medical Records · Private" + lock.
- Components: `RecordCard`, filter chips, FAB (add where permitted), `EmptyState`.
- States: loading | empty | error; sync states for offline (records not cached).

### MED-002 Medical Record Detail
- API: `GET /patients/me/medical-records/{id}` (own) / grantee variant.
- Sensitive: full PHI; `SensitiveScreenLock`; no screenshots affordance.
- Actions: add file (author scope), share/consent entry, edit/delete (own C16).

### MED-003 Document Viewer
- Purpose: view attached medical files via signed URL; no cache beyond session.
- API: `GET /patients/me/medical-records/{id}/files/{fid}` (signed download).
- Components: pager, zoom, "Private" overlay. A11y: zoom not required to read text alt.

### MED-004 Record Entry (own)
- Purpose: create self-entered record (C16). API: `POST /patients/me/medical-records`, file upload.
- Validation: title + optional body size limits; plain-language prompts; PHI warning note.

### MED-005 Record Access/Sharing (→ CONS)
- Purpose: entry point to who-can-see-this + consent actions. API: consents module.

### CONS-001 Consent List ("Who can see my information")
- Purpose: patient overview of all grants. API: `GET /consents`, `GET /consents/active`.
- Roles: patient (owner). Sensitive: PHI + relationships.
- Components: consent cards (who/what/until/Revoke), `EmptyState`, `FAB` grant.
- States: loading | empty ("No one else can see your records yet") | error.

### CONS-002 Consent Detail
- Purpose: who → what (scopes) → why → since → until → [Revoke access].
- API: `GET /consents/{id}`, `POST /consents/{id}/revoke`, `renew`.
- Uses `DestructiveDialog` for revoke.

### CONS-003 Consent Grant
- Purpose: grant scopes to verified person (doctor/staff/caregiver).
- API: `POST /consents`. Validation: person + ≥1 scope + purpose + expiry (future).
- UI summary before confirm; immediate ack on success.

### MED-007 Access History
- Purpose: where-audit (where API provides). API: consents/audit (C4-exported only).

---

## MEDT — Medications (medical feature)

### MEDT-001 Medication List / Today
- Purpose: today's meds + dose logging. API: `GET /medications`, `GET /medications/stats`.
- Permissions: own; caregiver C16-authorized. Sensitive: meds PHI (moderate).
- Components: `MedicationCard` (name, dose, due), log button, add FAB.
- States: loading | empty ("No medications yet") | error; offline shows labels (cached names).

### MEDT-002 Medication Add/Edit
- API: `POST/PATCH /medications`. Validation: name, dose+unit, frequency, start ≤ today.

### MEDT-003 Schedule
- API: `GET/POST /medications/{id}/schedule`, `PATCH/DELETE /schedule/{sid}`.
- Components: time pickers, day multi-select.

### MEDT-004 Dose Log
- Purpose: log taken dose + undo. API: `POST /medications/{id}/log-dose` (idempotency key).
- `LoadingButton` with server-ack before success snackbar.

### MEDT-005 Adherence Summary
- API: `GET /medications/stats` (async). Non-clinical supportive wording (§13); `AdherenceRing`.

### MEDT-006 Missed Dose Support
- Purpose: handle missed safely. No red; reassuring copy; next-dose guidance.

---

## APP — Appointments (appointments feature)

### APP-001 Appointment List
- API: `GET /appointments`. Statuses shown via `StatusBadge` (SCHEDULED→CONFIRMED→COMPLETED/NO_SHOW/MISSED/CANCELLED).

### APP-002 Appointment Detail
- API: `GET /appointments/{id}`; action buttons per current state (§42 state machine).

### APP-003 Appointment Request
- API: `POST /appointments` (idempotency key). Validation: purpose, doctor/facility, future date/time.

### APP-004 Reschedule
- API: `POST /appointments/{id}/reschedule`. Shows current + candidate picker.

### APP-005 Cancel Appointment
- API: `POST /appointments/{id}/cancel`. `DestructiveDialog` before submit.

---

## BLOOD — Blood network (blood feature)

### BLOOD-001 Blood Hub
- Role-filtered landing (patient=request side / donor=donate side). API: model summaries.

### BLOOD-002 Create Blood Request
- API: `POST /blood/requests` (idempotency). Fields: group (prefilled from profile), facility (verified picker), units, urgency (segmented), caregiver contact, notes.
- Validation: units 1+, urgency enum, facility required. Sensitive: request info (internally visible).

### BLOOD-003 Request Detail / Status
- API: `GET /blood/requests/{id}`; status timeline (CREATED→VERIFIED→ACTIVE→FULFILLED→CLOSED / CANCELLED / REJECTED).
- Matches shown **only per backend** (C8/C9); no donor PII displayed.

### BLOOD-004 Donor Profile
- API: `GET/PATCH /blood/donors/me` (FR-BLD-001..004). Privacy: location shown as region/radius only.

### BLOOD-005 Eligible Requests (donor)
- API: `GET /blood/requests` (C8/C9 scope). No contact data visible.

### BLOOD-006 Respond to Match
- API: `POST /blood/matches/{id}/respond` (available / not now). Confirmation of what happens next.

### BLOOD-007 Donation History
- API: donation events + requests (immutable). Shared with facility-visible only.

---

## EMG — Emergency (emergency feature)

### EMG-001 Emergency Home/FAB
- Purpose: persistent access point (all shell screens). Red + icon + label "SOS".

### EMG-002 Emergency Confirmation
- Bottom sheet: explains the request, contacts linked contacts, **not a replacement for 112/EMS**, press-and-hold arm.

### EMG-003 Emergency Request
- API: `POST /emergency/requests` (idempotency, rate-limited). Prefilled from emergency profile (PAT-003/EMG ready card); editable urgency/location/notes; consent to share with responders.

### EMG-004 Status Tracking
- API: `GET /emergency/requests/{id}` (poll). `StatusTimeline`: CREATED→VALIDATING→ACTIVE→RESPONDING→ESCALATED→RESOLVED/CANCELLED. Cancel affordance.

### EMG-005 Resolution
- Success state + next steps + log entry; no residual red.

### EMG-006 Emergency Access Status (patient)
- Purpose: view bounded override grants (who opened access). API: `/emergency/access-grants`. Render "Professional access granted until …" — revocable.

---

## DOC — Doctor (doctors feature)

### DOC-001 Doctor Dashboard
- API: `GET /doctors/me/appointments`, `GET /doctors/me`; verification banner PENDING/VERIFIED/REJECTED.

### DOC-002 Verification Status + Upload
- API: `POST /doctors/me/verification`; `VerificationBadge`; doc upload.

### DOC-003 Authorized Patients
- API: `GET /doctors/me/patients`. Only linked+consented; empty state uninformative (no existence hints).

### DOC-004 Patient Records (doctor)
- API: `GET /doctors/me/patients/{uid}/medical-records` (C2/3). Read-only unless authored; consent badge.

### DOC-005 Doctor Appointments
- API: confirm/reschedule/complete/no-show per state (from /appointments).

### DOC-006 Clinical Note Entry
- API: `POST /patients/{uid}/medical-records` (C15). Text + files.

### DOC-007 Doctor Profile
- API: profile + education CE. Public subset shown to patients (name, specialty, verified).

---

## CAR — Caregiver (profile/caregiver flow)

### CAR-001 Caregiver Hub
- "Viewing: [Patient Name]" banner (C18) always; consent scope summary.

### CAR-002 Invitations (accept/decline)
- API: `POST /caregivers/{id}/accept|decline`. Explains scope + expiry before accept.

### CAR-003 Linked Patients
- API: `GET /caregivers`. Rows: name, scope chips, expiry countdown.

### CAR-004 Authorized Info View
- Scoped screen mirrors patient's MED/MEDT allowed by consent only; denied sections not listed.

### CAR-005 Permission/Consent Status
- "You can see: Medications… You cannot see: Personal notes." + "Ask patient to change."

### CAR-006 Remove Relationship
- API: `DELETE /caregivers/{id}` (patient side) — `DestructiveDialog`, immediate ack.

---

## COM — Community (community feature)

### COM-001 Feed
- API: `GET /community/posts`. Badges: verified/community; no medical content.
- States: loading | empty | error; infinite scroll; offline cached non-PHI.

### COM-002 Post Detail
- API: `GET /community/posts/{id}`, comments `GET/POST /community/posts/{id}/comments`, reactions toggle.

### COM-003 Create Post
- API: `POST /community/posts`. Text + optional image (private upload); consent checkbox; PHI warning.

### COM-005 Report
- API: `POST /community/reports`. Simple reason chips; thank-you state.

### COM-006 My Profile (community)
- My posts (moderated states reflected: PUBLISHED/HIDDEN), my reports status.

---

## CHAT — Messages (chat feature)

### CHAT-001 Conversation List
- API: `GET /chat/conversations`. Doctor threads labeled "Private · verified doctor"; no community mix.

### CHAT-002 Conversation Thread
- API: `GET /chat/conversations/{id}/messages`, `POST …/messages`, read marks `POST …/read`.
- Delivery ticks (sent/delivered/read); `FLAG_SECURE` where OS allows; no screenshot affordance in doctor chats.

### CHAT-003 Composer + Attachments
- Images/docs via signed upload (3.5 §32); size/type limits enforced client+server.

### CHAT-004 Leave/Add Participant
- `POST /chat/conversations/{id}/leave`; authorized adds (C13) server-gated.

---

## EDU — Education (community/education feature)

### EDU-001 Categories
- API: `GET /education/categories`. Topic cards.

### EDU-002 Library + Search
- API: `GET /education/content`, search `GET /education/content?q=`. Verified badge; language filter.

### EDU-003 Content Detail
- Article/video; summary → sections; reading progress local; bookmark.

### EDU-005 Bookmarks
- Local list + JIT fetch `GET /education/content/{id}`.

---

## DON — Financial donations (donations feature)

### DON-001 Campaign List
- API: `GET /campaigns` (verified only). Cards: raised/target, days-left, verified org badge.

### DON-002 Campaign Detail
- API: `GET /campaigns/{id}`. Story + progress + "Donate now".

### DON-003 Donate
- API: `POST /donations` (idempotency key). Amount TZS inputs (preset+custom, min).

### DON-004 Payment Method
- Provider list (3.5 AD-5), number/key cleaner. Consent to share reference.

### DON-005 Donation Confirmation
- Explicit INITIATED vs CONFIRMED (webhook-verified) — never client-claimed success.

### DON-006 Donation Status
- `StatusBadge`: INITIATED(amber)/CONFIRMED(teal)/FAILED(red)/REFUNDED(blue); retry only PENDING/FAILED.

### DON-007 Donation History
- API: `GET /donations`, `GET /payments`.

### DON-008 Receipt
- API: `GET /donations/{id}/receipt` (confirmed only). Printable/shareable (non-PHI meta only).

---

## NOT — Notifications (notifications feature)

### NOT-001 Notification Center
- API: `GET /notifications`, `/notifications/{id}/read`, `/notifications/read-all`.
- Grouped, unread/read, privacy-safe previews (§23).

### NOT-002 Preferences
- API: `GET/PATCH /notifications/preferences` + device tokens `POST/DELETE /notifications/devices`.
- Emergency category non-disableable (note explains why).

---

## PRO — Profile & settings (profile feature)

### PRO-001 Profile
- API: `GET /users/me`, `/patients/me`. Role badges; blood group (patient).

### PRO-002 Account
- API: `/users/me` contacts + verification status.

### PRO-003 Security
- API: `/auth/password/change`, `/auth/mfa/*`, AUTH-010 sessions, biometric (local).

### PRO-004 Privacy
- Entry → CONS-001; sensitive-screen lock toggles; "export my data".

### PRO-006 Notification Settings → NOT-002

### PRO-007 Language
- EN/SW; local pref + system default.

### PRO-008 Help
- FAQ; contacts; emergency numbers card.

### PRO-009 Logout
- API: `POST /auth/logout`. Confirm → revoke refresh (denylist) → AUTH-002.

### PRO-010 Deactivate Account
- `DestructiveDialog` (long-form) with consequences; server-gated.

---

## SRCH — Search (global)

### SRCH-001 Global Search
- Purpose: search approved resources (education, blood requests, doctors, community, appointments). **Never patient search.**
- API: returns via scoped endpoints; result scopes honor auth (no private discovery).
- States: idle → typing (debounced) → results | empty | error.

---

## ADMIN (HIDDEN on mobile — moved to 3.7 web)

- `ADMIN-*` screens from the old scaffold (`admin_panel_page.dart`) are **not** exposed on mobile; admin functions belong to the admin web UI (3.7). Mobile admin role sees user-level screens only.

---

## Screen count & coverage

| Group | Count | Notes |
|---|---|---|
| AUTH | 10 | AUTH-001..010 |
| HOME | 1 | HOME-001 (+embedded summary) |
| PAT | 5 | PAT-001..005 |
| MED/CONS | 8 | MED-001..005, MED-007, CONS-001..003 |
| MEDT | 6 | MEDT-001..006 |
| APP | 5 | APP-001..005 |
| BLOOD | 7 | BLOOD-001..007 |
| EMG | 6 | EMG-001..006 |
| DOC | 7 | DOC-001..007 |
| CAR | 6 | CAR-001..006 |
| COM | 5 | COM-001,002,003,005,006 |
| CHAT | 4 | CHAT-001..004 |
| EDU | 4 | EDU-001,002,003,005 |
| DON | 8 | DON-001..008 |
| NOT | 2 | NOT-001,002 |
| PRO | 8 | PRO-001..010 (subset listed) |
| SRCH | 1 | SRCH-001 |

Approx. **86 screens/specs** (incl. embedded). All map to 3.5 endpoints —
none depend on an undefined API (verified in `mobile-api-traceability.md`).

---

END OF SCREEN INVENTORY