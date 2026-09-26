# 3.6 Mobile Component Catalog

> Reusable component system. Every component: **ID · purpose · hierarchy ·
> tokens (spacing/radius/elevation/typography from `mobile-ui-ux-design.md` §6/§7/
> §37) · states (idle/loading/success/empty/error/disabled) · accessibility ·
> notes**. Features state the component model: `AsyncView` for screens,
> `StateBadge` for domain states, `FieldState` for forms.
>
> Current scaffold has `feature_card`, `app_icon`, `module_placeholder_page`
> (kept, restyled — no deletions; §36 main doc).

---

## A. Buttons

### C-BTN-001 AppPrimaryButton
- Filled, Dark Blue, 48+ h (h-48/56), radius r-8, label ts-label (16). Loading → `LoadingButton` (spinner swap, label preserved width).
- A11y: ≥48 hit, label + spinner via live region. States: idle/focused/disabled/pressed/loading.

### C-BTN-002 AppSecondaryButton
- Outlined/tonal, Blue family, same heights. Used for secondary actions, never primary on a screen.

### C-BTN-003 AppTextButton
- Text-only, secondary; used for "resend", "see all".

### C-BTN-004 IconButton (AppIconButton)
- Icon+tooltip always; `Semantics` label. 48×48.

### C-BTN-005 DangerButton
- Red (danger), icon+label; reserved for destructive *submits* (always paired with `DestructiveDialog`).

### C-BTN-006 EmergencyButton
- Red accent, `sos` icon (or `emergency`), label "SOS". Two variants: FAB (`EmergencyFab`) on shell; banner action on emergency screens. Press-and-hold arm (≥600ms) + confirm sheet — never instant fire.

### C-BTN-007 LoadingButton
- Wraps any button; spinner while `busy`; disables input; label frozen.

### C-BTN-008 ConcernDrawerButton
- Text button with underline/chevron used to reveal destructive or cautionary detail (e.g. "What happens if I cancel?").

## B. Cards

### C-CARD-001 FeatureCard
- Restyle of existing: 16dp, radius r-12, leading `CircleAvatar` (12% tint, icon color = semantic), title, subtitle, chevron. States: pressed (elevation), disabled (grey).

### C-CARD-002 StatusCard
- Single metric + label ("3 medications due today", "2 appointments this week") + tap target. Supports tint variants (info/success/warning; **red only for critical**).

### C-CARD-003 DataCard
- key/value rows, optional chart; used in health dashboards.

### C-CARD-004 RecordCard
- Medical record row: title, category chip, authored-by label, updated; lock indicator when private (icon+text).

### C-CARD-005 MedicationCard
- Name, dose, next-due, "Log dose" button + undo; status badge per dose.

### C-CARD-006 CampaignCard
- Verified badge, raised/target, days-left, urgency tier; "Donate" CTA.

### C-CARD-007 RequestCard
- Blood request row: group, hospital, units, urgency, status. Sensitive: no donor PII ever.

### C-CARD-008 ConversationTile
- Avatar/initials, name, last message preview (privacy-safe), ticks, unread badge; doctor threads show verified badge.

### C-CARD-009 EducationCard
- Thumbnail, type chip (article/video), reading time, verified-origin badge, bookmark toggle.

## C. Inputs

### C-IN-001 AppTextField
- Outlined, label, helper, error slot, prefix/suffix, obscure toggle; `textInputAction`, `autofillHints`; min height h-56; error ts-label red with message; `FieldState` enum (idle/invalid/disabled/filled).
- A11y: label+error semantic merge; focus ring (focus-ring token).

### C-IN-002 AppDropdown
- Single-select menu, shows label + value; validation like AppTextField.

### C-IN-003 AppSearchField
- Search input with clear button, debounce (400ms), loading/empty results slot.

### C-IN-004 AppDatePicker / AppTimePicker
- Wraps Material pickers; validates future/past per field contract (forms §31).

### C-IN-005 OtpInput
- N-digit segmented code (6), paste support, per-digit focus; auto-submit on complete; resend timer.

### C-IN-006 AmountInput
- TZS formatting, min/max, prefix "TZS", numeric keyboard; error on below-minimum.

### C-IN-007 AppChipInput (multi-select)
- Filter chips; returns selected codes; used in scopes/symptoms/categories.

## D. Selection & Status

### C-SEL-001 AppChip
- Selectable chip; selected state primary fill vs outline.

### C-SEL-002 SegmentedControl
- 2–4 options inline; used for urgency, response, gender, role pick (self-registerable).

### C-BADGE-001 StateBadge
- Maps domain state → semantic (color+icon+label; **red only where §42 critical**):
  - appt: SCHEDULED/REQUESTED(amber) · CONFIRMED(blue) · COMPLETED(teal) · NO_SHOW(warn) · MISSED(neutral) · CANCELLED(gray)
  - blood: CREATED(amber)→VERIFIED(blue)→ACTIVE(blue)→FULFILLED(teal)→CLOSED(gray), REJECTED/CANCELLED(gray)
  - emergency: CREATED(amber)→VALIDATING(amber)→ACTIVE(blue)→RESPONDING(blue)→ESCALATED(red-warn)→RESOLVED(teal)→CANCELLED(gray)
  - consent: DRAFT(amber) · ACTIVE(blue) · REVOKED(gray) · EXPIRED(amber)
  - caregiver: PENDING(amber) · ACTIVE(blue) · DECLINED(gray) · REMOVED(gray)
  - campaign: DRAFT/PENDING(amber) · VERIFIED(teal) · ACTIVE(blue) · CLOSED(gray)
  - donation: INITIATED(amber) · CONFIRMED(teal) · FAILED(red) · REFUNDED(blue)
- A11y: never colour alone — icon + text always.

### C-BADGE-002 VerificationBadge
- ✓ Verified doctor/campaign/facility (teal check + "Verified") or "Under review" (amber clock).

### C-STATUS-001 StatusTimeline
- Stepped progress (created→…→resolved); current step highlight; past steps ✓; failed/removed branch dashed. A11y: step label + position read.

### C-CHART-001 SimpleLineSpark
- Lightweight line chart (symptoms/pain/adherence trend); accessible summary text ("Last 7 days: stable").

### C-CHART-002 AdherenceRing
- Supportive ring + % with non-clinical label "Your routine"; never a grade.

## E. Surface & Feedback

### C-SURF-001 AppAppBar
- Default: Dark Blue bg, white fg, centered title, bell action for notifications; emergency context variant keeps same shell (red confined to Emergency elements).

### C-SURF-002 EmergencyBanner
- Red tint bg `#FBE7E7` + border, icon, text ("Emergency request pending — status below"). Placed atop emergency screens.

### C-SURF-003 OfflineBanner
- Amber, wifi-off icon, "You're offline — showing saved information." Above shell content; dismissible; auto-removes on reconnect.

### C-SURF-004 ConfirmDialog
- Title + consequence copy + Cancel/Confirm (primary). Ensures informed actions (§43 main doc).

### C-SURF-005 DestructiveDialog
- Red header icon, explicit consequence, Cancel + red Confirm (typed where risky). Used: revoke consent, cancel appt, cancel EMS, remove caregiver, deactivate, delete post.

### C-SURF-006 NoticeBottomSheet
- Sheet with explainer (emergency confirm, consent grant summary, payment method); scroll-safe for long text.

### C-SURF-007 Snackbar
- Teal (success), red (error, icon+text), blue (info); ≥4s; action button where applicable.

### C-SURF-008 SensitiveLockState
- Full-screen lock for private content when device locked / biometric off; "Unlock to view" – clears after successful auth (proxy for `FLAG_SECURE`).

## F. Navigation

### C-NAV-001 BottomNavBar
- ≤5 items, role-filtered (nav doc §2), active indicator primary; always 48+ items; tablet >600dp renders `NavigationRail` instead.

### C-NAV-002 NavigationRail
- ≥600dp, vertical items, extended labels on expanded.

### C-NAV-003 EmergencyFab
- Floating action, red, fixed above bottom nav (elevated e-4); always present except auth screens.

### C-NAV-004 ProfileDrawer (More menu)
- Opens PRO-001/003/004/007/008/009; includes role label.

## G. Screen States

### C-ST-001 LoadingState
- Skeleton (lists) or centered spinner (actions); non-blocking where possible; never dismiss input already entered.

### C-ST-002 ErrorState
- Friendly message (§28 map) + Retry button; no raw codes.

### C-ST-003 EmptyState
- Icon, title, CTA ("Start your first record", "Request blood"), never implies hidden data.

### C-ST-004 SuccessState
- Teal check + confirm text; server-ack-driven (§27).

### C-ST-005 AccessDeniedState
- "You don't have access to this." + Go Home; no existence hints.

### C-ST-006 NeedsUpdate chip / UnsavedDraftBar
- "Pending sync" / "Draft saved on this device" chips on offline writes (§27).

---

## Appendix A — Form field contract (§31 main doc)

Per field: `id · label(en/sw) · type [text/phone/email/num/date/time/dropdown/chip/otp] · required · validation rule · error copy · keyboard · sensitive · backend field`. Applied to every listed form (auth, profile, doctor, caregiver, blood, donor, emergency, medical info, appointment, donation, post). Example:

| Field | Type | Req | Validation | Error copy | Keyboard | Sensitive | Backend |
|---|---|---|---|---|---|---|---|
| auth.email/phone | String | ✅ | email-or-+2559… | "Enter a valid email or phone" | email/phone | PII | `email`/`phone_number` |
| auth.password | PW | ✅ | ≥8, 1 letter+1 number | "Use 8+ characters with a number" | default | 🔒 | `password` |
| blood.units | int | ✅ | 1..10 | "Units must be 1–10" | number | internal | `units_required` |
| emergency.consent | bool | ✅ | must accept | "Confirm to share with responders" | — | 🔒 | `share_consent` |
| donation.amount | num | ✅ | ≥ min | "Minimum is TZS x" | number | — | `amount` |
| med.free_text | text | optional | ≤2000 | "Keep it under 2000 letters" | text | 🔒 | `notes` |
| community.text | text | ✅ | ≤2000 + no PHI prompt | "Add a message (2000 max)" | text | — | `content` |

---

END OF COMPONENT CATALOG