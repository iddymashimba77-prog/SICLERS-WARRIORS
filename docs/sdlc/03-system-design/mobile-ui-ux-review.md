# 3.6 Mobile UI/UX Design — Review

> Stage 3.6 audit report. Produced after authoring `mobile-ui-ux-design.md`,
> `mobile-navigation.md`, `mobile-screen-inventory.md`,
> `mobile-component-catalog.md`, `mobile-api-traceability.md` against Stages
> 2/3.1/3.2/3.3/3.4/3.5 and inspection of the actual Flutter project in
> `apps/mobile`. **Design only — no screens implemented, no new state framework
> wired, no router installed.** Gate decision at the end.

---

## 1. Executive Summary

The mobile UI/UX design is complete, internally consistent, and aligned to the
approved requirements, role/permission model (3.3), database (3.4) and API
design (3.5). The existing Flutter scaffold is a **presentation-only skeleton**:
no network, no auth/session, no state management, no persistence, no routing
layer beyond a static named-route table, hard-coded English strings, and a
**red-based brand palette that conflicts with the Stage 3.6 brand directive**
(Dark Blue · Blue · Red · White with red reserved for emergency/danger).

The deliverables define the full target experience without touching code:
a token-driven design system (red relegated to emergency/danger), a complete
screen inventory (~86 screens/specs, each mapped to real 3.5 endpoints), a
role-aware navigation map (10 Mermaid flows), a reusable component catalog with
a form contract, and a UI→API traceability table. Every screen maps to an
endpoint that exists in the 3.5 matrix; nothing was invented.

**Verdict: solid design, implementation-critical corrections flagged (C1–C4)** —
all resolvable at Stage 4 without changing the design's architecture.

---

## 2. Existing Flutter Assessment

Inspected `apps/mobile` (path: `apps/mobile`):

| Area | State found | Assessment |
|---|---|---|
| Structure | Feature-first (`core/`, `features/`, `shared/`) — sound, matches 3.2 module split | Keep (do not re-architect) |
| Screens | 13 feature pages; most are `ModulePlaceholderPage` stubs; `HomePage`, `LoginPage`, `EmergencyPage` have minimal real UI | Reusable shells; each will be replaced by its inventory screen in Stage 4 |
| Widgets | `feature_card.dart`, `app_icon.dart`, `module_placeholder_page.dart` reusable | Keep + restyle to new tokens (no deletion) |
| Theme | `AppTheme.light/dark`, Material 3, seed `primary=AppColors.primary` | Rebuilt as token-driven (§6/§37); palette rewritten |
| Colors | `AppColors.primary = 0xFFB71C1C` (red) as brand primary; `secondary=pink`, `emergency=red` family | **Conflicts with 3.6 brand** (red reserved for emergency). Must re-tokenize → Dark Blue primary (C1) |
| Strings | `app_strings.dart` hard-coded EN | i18n gap — move to ARB (`en`, `sw`) (C2) |
| State mgmt | None | Choose Riverpod/Provider at Stage 4 (AD-MD-2) |
| API client | `core/network/` exists but **empty** | Greenfield: dio + auth interceptor + retry + idempotency (C3) |
| Auth handling | None; `LoginPage` navigates to Home without any auth | Build secure session + `go_router` guards (C3) |
| Routing | `MaterialApp.routes` NamedRoutes, `initialRoute: '/login'` | Replace/augment with guarded router (C3; keep compatibility) |
| Storage/models/services | None (no data/, domain/, repositories) | Add per-feature data+domain layers (C4) |
| Admin | `admin_panel_page.dart` placeholder exists in mobile nav | **Remove from mobile** — admin goes to 3.7 web (M2) |
| Tests | `widget_test.dart` renders LoginPage | Extend as screens land |

No data loss concern: nothing to preserve beyond stubs; but **no existing work
is deleted** — placeholders remain until replaced by real screens.

---

## 3. UX Assessment

- Ten UX goals (safety→reliability) established with measurable outcomes
  (G1–G10) sourced from NFR-USE-001..003 and FR modules — good trace.
- Information architecture re-groups content by *user task* (Health cluster,
  Blood hub, Community+Education) — low cognitive load (G7).
- Home prioritizes status → emergency → meds → appointments → community →
  education → giving; deliberately ≤5 quick cards (§9).
- Emergency is an explicit two-to-three-step workflow (FAB → confirm sheet →
  press-&-hold arm → request → tracking → resolution) that is both fast (G8)
  and accidental-trigger-resistant (G5), offline-safe (never silently queued).
- Medication UX isolates the semantics of supportiveness (no shame, non-clinical
  adherence) — meets FR-MED-004 and healthcare-safety intent.
- Consent translated to plain language with who/what/why/until/revoke — matches
  FR-MEDREC-005 and accessibility-to-non-technical-users goal.
- Donation UX emphasises INITIATED vs CONFIRMED (webhook) — correct financial
  honesty; matches FR-PAY-003..005.
- Verdict: strong UX, no gaps against the ten goals. Minor: role variants (staff)
  are described but could be deepened in implementation specs (M1).

---

## 4. Navigation Assessment

- Two stacks (auth/main), ≤5 role-filtered tabs, Emergency FAB outside nav,
  tablet rail — conforms G7/G8 + 3.3 permission derivation.
- Guards: auth (silent refresh) → role → state → consent; deep links mirror API
  relative routes; unauthorized-screens use an existence-safe denied state
  (AD-6-consistent).
- 10 Mermaid diagrams (auth, patient, doctor, caregiver, donor, emergency,
  blood request, record access, consent, donation/payment) cover required maps.
- Ninja gap: role-to-screen matrix shows `VISIBLE/CONDITIONAL/HIDDEN`; admin
  correctly HIDDEN. No un-gated route to sensitive screens.
- Verdict: complete. Note: `go_router` adoption is a Stage-4 decision (AD-MD-1);
  the NamedRoutes today are insufficient for guards (C3).

---

## 5. Accessibility Assessment

- Targets ≥48dp, AA contrast everywhere incl. dark theme tokens (values chosen
  so `#EF5350` on `#152131` passes), reduced-motion honoured, no colour-only
  semantics (StateBadge = icon+text), semantic labels on every icon, live
  regions for confirmations, text-scaling to 200%, keyboard/switch-support
  focus rings, seizure-safe emergency (no flashing; press-&-hold only).
- Kiswahili/English publishing gate for chrome strings.
- Verdict: exceeds WCAG-AA intent for a low-literacy audience; no critical gaps.

---

## 6. Privacy Assessment

- Privacy markers on medical/consent/messages; no PHI in push previews (generic
  "You have a new health update."), URLs (UUIDs), recents (FLAG_SECURE), or
  community defaults; donation/emergency consent explicit and default-off;
  blood donor PII never surfaced; consent immediate-revoke UI matches API.
- Caregiver viewing banner prevents cross-patient confusion (C18).
- Verdict: strong; encryption of medical file attachments/message attachments is a Stage-4 storage/API
  dependency inherited from 3.4/3.5 and must be honoured.

---

## 7. Security UX

- Aligned to 3.5: JWT + silent refresh, session list/revoke, MFA TOTP flows,
  password reset no-enumeration, biometric app-lock optional (never sole auth),
  logout denylist, destructive confirmations. UI never bypasses backend.
- Sensitive screen lock + no screenshot affordance on records/donor/doctor-chat.
- Verdict: complete, consistent with backend (no contradiction to Stage 3.5).

---

## 8. API/UI Alignment

- `mobile-api-traceability.md` maps every inventory screen → role → permission
  code (3.3) → endpoint (3.5) → DB entity (3.4) → security rule.
- Write paths reuse idempotency exactly where 3.5 specifies; UI retries safe.
- Webhooks correctly server-only; UI consumes verified state via `GET /payments`.
- AI assistant endpoints (`/ai/chat`, `/ai/trends`) remain FUTURE (3.5 AD-2) —
  not wired into screens; nothing depends on a non-existent endpoint.
- Verdict: fully aligned.

---

## 9. Role/UI Alignment

- Matrix (§34) derived from 3.3, not from the prompt examples verbatim: doctor
  has no Health tab; caregivers banner-scoped; donor sees eligible-only blood;
  financial donor gets Donations; empty-permission safe default (Home + bell +
  profile).
- Admin HIDDEN on mobile (proper offload to 3.7 web).
- UI visibility documented as UX-only; backend remains the enforcement boundary
  (repeated in guards). Verdict: correct.

---

## 10. Requirements Traceability

| Source | Coverage |
|---|---|
| FR-AUTH-001..006 | AUTH-001..010 (+MFA), login/register/reset flows ✓ |
| FR-PAT-001..004 | PAT-001..005, POS ✓ |
| FR-MEDREC-001..006 | MED-*, CONS-*, MED-007 access history ✓ |
| FR-MED-001..006 | MEDT-001..006 (supportive language) ✓ |
| FR-SYM-001..005 | embedded in PAT-001/health dashboard + charts ✓ |
| FR-APP-001..004 | APP-001..005 + reminders ✓ |
| FR-BLD-001..010 | BLOOD-001..007 (incl. matching link, no PII) ✓ |
| FR-EMG-001..006 | EMG-001..006 (bounded override visibility) ✓ |
| FR-DOC-001..005 | DOC-001..007 (verification gating) ✓ |
| FR-CAM-001..006 / FR-PAY-001..005 | DON-001..008 (initial/final clear) ✓ |
| FR-COM-001..005 | COM-001..006 (report/moderate) ✓ |
| FR-EDU-001..004 | EDU-001..005 ✓ |
| FR-NOT-001..006 | NOT-001/002 (preview privacy) ✓ |
| BR-001..012 | state machines §42, guards, consent, no-shaming ✓ |
| NFR-USE-001..003 | goals G1–G10, design rules ✓ |
| NFR-SEC-002/004, privacy reqs | §6/§16/§23/§29/§30 ✓ |
| NFR-AVL/PERF | offline/error/draft UX §27/§28 ✓ |

All 86 screen specs trace; none require a missing endpoint.

---

## 11. Innovation Assessment

Nine innovations evaluated with problem/benefit/data/privacy/API/db/complexity;
six marked CORE (personalized education, blood match quick-respond, health
timeline, caregiver coordination, localized education — plus read helpers),
three FUTURE (emergency readiness card, supportive adherence insights, smart
reminder batching, crisis checklist) and AI assistant deferred (3.5 AD-2).
No CORE innovation changes backend or adds endpoints; FUTURE items are inert.

---

## 12. Critical Issues (for implementation)

| # | Issue | Recommendation |
|---|---|---|
| C1 | **Brand colour conflict:** scaffold uses red as primary brand (`0xFFB71C1C`), violating "red reserved for emergency" | Re-tokenize to Dark Blue/Blue primary per §6; red exits via `AppColors.emergency`/`danger` only |
| C2 | **i18n gap:** all strings hard-coded in `app_strings.dart` | Introduce `flutter_localizations` + ARB (en, sw) before any screen authoring |
| C3 | **No auth/network/routing layers exist** (empty `core/network`, `core/router`; static routes, no session) | Build `dio` client + auth interceptor + secure storage + guarded router (AD-MD-1/2) first — everything else depends on it |
| C4 | **No data/domain layers** (no repositories/models/services) | Add per-feature `data + domain` (repository pattern) so screens never call API directly; keep feature-first layout |

Stage-4 sequencing: C3 → C4 → C1/C2 → screens (see §15).

---

## 13. Minor Issues

| # | Issue | Recommendation |
|---|---|---|
| M1 | Healthcare-Staff UX is a lighter clone of Doctor; its facility-scope specifics are thin | Deepen in implementation specs via C7 facility-context rows |
| M2 | `admin_panel_page.dart` placeholder remains in mobile nav | Remove route/nav widget (hidden); do not delete file — it moves to 3.7 web |
| M3 | `go_router` vs named-routes migration may touch `widget_test.dart` | Keep test green by pumping `App()` with a test router |
| M4 | Reminder strategy (local scheduled vs FCM) unsettled (AD-MD-9) | Decide before medication feature implementation |
| M5 | Personal data export (PRO-004) has no dedicated 3.5 endpoint yet | Scaffold with fetch-only of own profile + note to 3.5 (future / confirm) — do not add API in this stage |

## 14. Open Design Decisions

Carried from §41 of the design doc: MD-1..MD-14 (router, state mgmt, tab cap,
emergency trigger interaction, biometric default, offline cache scope, font,
dark-mode default, reminders transport, chat transport, AI assistant, admin
removal, provider list, verification-UI depth) + inherited 3.5 AD-1..AD-11 and
3.4 OQ-1..7. None block Stage 3.6; each must be locked at Stage-4 kickoff.

## 15. Recommended Implementation Strategy (for Stage 4)

1. Layer 0 (C3): network client + secure token storage + guarded router; silent
   refresh; app shell with role-aware bottom nav + Emergency FAB.
2. Layer 1 (C4): design tokens + theme rebuild (C1), ARB l10n (C2), component
   catalog widgets, shared state (AD-MD-2).
3. Layer 2: Auth flow end-to-end (AUTH-*), then Home shell per role.
4. Layer 3: patient journey (Health cluster, MED/MEDT/APP/CONS) with consent
   guards; then blood; then emergency; then doctor/caregiver; then community/
   education/chat/donations; notifications; profile/settings.
5. QA: golden tests per screen state class (loading/empty/error/success), widget
   tests for guards, i18n completeness CI, accessibility audit, device matrix
   (5"/6.1"/6.7", SE/14, iPad, Android tablet).
6. Defer: FUTURE innovations, AI (AD-2), admin (3.7).

## 16. SDLC Gate Decision

# **PASS WITH MINOR REVISIONS**

The Stage 3.6 design is complete and consistent with Stages 2/3.1/3.2/3.3/3.4/3.5.
Sixteen findings (4 critical-for-implementation, 5 minor, 14 open decisions)
are all implementation-time items; none blocks the design or architecture.
The existing scaffold is compatible and no existing work is discarded.

> STOP — no further stage started. `3.7 Admin Web UI/UX Design` begins only
> after project owner approval. **No Flutter screens are built** in this stage;
> implementation is Stage 4.