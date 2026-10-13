# Sickler's Warriors — 38-Point Implementation Report

Full-system UX/UI transformation, product-experience and production-readiness pass.
Each point reads **FILE → WHAT CHANGED → WHY → RESULT**.

## Verification status (re-run after the last change)

| Gate | Result |
| --- | --- |
| Backend `manage.py test` (`config.settings.ephemeral_test`) | **838 tests OK** |
| Flutter `analyze` | **No issues found** |
| Flutter `test` | **315 tests passed** |
| Admin `npm run typecheck` (`tsc -b`) | **clean** |
| Admin `npm run build` | **built in 2.33 s** — CSS 16.29 kB (gzip 3.99), JS 284.98 kB (gzip 83.80) |

---

## A. Backend — API correctness, security, operations (10 points)

### 1. `backend/core/handlers.py` (new)
- **WHAT CHANGED:** Added an error envelope plus `api_not_found` / `api_server_error` view handlers that return `{"error": {code, message, details}}` with the correct status.
- **WHY:** DRF's default 404/500 responses differ from the `{"error": …}` contract every client parses, so unknown routes and crashes surfaced as unparseable payloads.
- **RESULT:** Every API failure — including unknown route and unhandled exception — now returns the documented envelope.

### 2. `backend/config/urls.py`
- **WHAT CHANGED:** Mounted those handlers for the API tree and added the health mounting (`core.urls_health`) plus the full route composition comment.
- **WHY:** The contract only holds if it is registered; health probes and SPA deep links must still resolve.
- **RESULT:** `/api/v1/health/` and `/api/v1/health/ready/` answer under the versioned prefix; API 404/500 are JSON.

### 3. `backend/accounts/views.py`
- **WHAT CHANGED:** Registration wrapped in `@transaction.atomic` (line 212).
- **WHY:** A failure mid-registration previously created a half-built account that could not log in and could not be re-registered.
- **RESULT:** Registration either completes fully or rolls back cleanly — retryable by design.

### 4. `backend/accounts/urls.py`
- **WHAT CHANGED:** Removed the bogus `verify/` route that pointed at a non-existent view; kept the real `verify/email/` and `verify/email/resend/`.
- **WHY:** A route resolving to nothing produces a 500 on the happy path a client may legitimately call.
- **RESULT:** No dead endpoints in the auth surface; documented paths all resolve.

### 5. `backend/accounts/serializers.py`
- **WHAT CHANGED:** Password-reset and e-mail-verification codes are delivered **in-app** (notification record) with TTL and resend cooldown, instead of depending on an SMTP relay.
- **WHY:** The product must work with no mail provider configured; otherwise the user is stranded on the verification screen.
- **RESULT:** Reset and verification flows complete end-to-end in the running system.

### 6. `backend/accounts/roles_views.py` + `admin_urls.py` + `admin_serializers.py`
- **WHAT CHANGED:** `GET /api/admin/permissions/`, `GET|POST /api/admin/roles/{code}/permissions/` — read surfaces expose the **live** role/permission matrix; writes are SUPER_ADMIN-only, reason-required and append-only with a lockout guard.
- **WHY:** The admin role editor cannot render or mutate a matrix it cannot read, and mutating a permission edge without an audit trail breaks the security story.
- **RESULT:** Roles & Permissions page is driven by real data; every grant/revoke is attributable.

### 7. `backend/core/media.py` + `backend/config/settings/base.py`
- **WHAT CHANGED:** `media_url()` builds absolute URLs from `PUBLIC_API_BASE` (operator-pinned) or the request origin; serializers/services read and write through it. `MEDIA_URL` corrected from `"media/"` to `"/media/"`.
- **WHY:** A relative `media/` produced `media/…` URLs that 404 — news covers and profile avatars visibly "broken"; behind a proxy the request `Host` is internal.
- **RESULT:** Uploaded images render from every origin and deployment topology.

### 8. `backend/content/upload_validation.py`
- **WHAT CHANGED:** Central file-type/size validation for uploads (maxima documented against `education.services.MAX_DOCUMENT_BYTES`).
- **WHY:** Size limits must sit above the largest legitimate upload or Django rejects the request *before* the validator can return a friendly 400 — a silent "upload refuses to work" failure.
- **RESULT:** Uploads up to the approved limits succeed; oversized/invalid files get an actionable 400.

### 9. `backend/config/settings/production.py`
- **WHAT CHANGED:** Added `SERVE_MEDIA` (default **off**) so production serves media from object storage/CDN unless an operator opts in to Django serving it.
- **WHY:** Django's static-serving view is not the production media story; leaving it implicitly on hides a misconfiguration.
- **RESULT:** Production media policy is explicit and env-driven.

### 10. `backend/notifications/reminders.py` + `management/commands/send_reminder_notifications.py`
- **WHAT CHANGED:** `dispatch_appointment_reminders(now, horizon_days)` creates per-appointment reminder notifications, and `dispatch_all_reminders()` is the single scheduler entry point; the command delegates to it.
- **WHY:** Reminders were ad hoc/not idempotent — the dispatcher could send the same reminder twice or miss one depending on wall clock.
- **RESULT:** One idempotent entry point for every reminder producer; schedulable from cron.

## B. Backend — verification & stability (3 points)

### 11. `backend/qa/tests_e2e.py`, `tests_privacy.py`, `tests_integration_420.py`, `tests_patients.py`, `tests_care_team_roles.py`, `qa_helpers.py`
- **WHAT CHANGED:** End-to-end, privacy, integration and care-team-role suites maintained against the current API.
- **WHY:** The transformation touched serializers, permissions and routes; only system-level tests catch cross-app regressions.
- **RESULT:** Full suite green: **838 tests OK**.

### 12. `backend/accounts/tests_admin_roles.py` + `backend/core/tests_media.py` + `backend/accounts/tests_profile_photo.py`
- **WHAT CHANGED:** New/updated tests for the permission catalog (scoping, lockout guard) and media URL resolution (origin, `PUBLIC_API_BASE`, avatar/photo round-trips).
- **WHY:** Points 6 and 7 are security- and presentation-critical with no other safety net.
- **RESULT:** Catalog access control and media URL behaviour are pinned by tests.

### 13. `backend/appointments/tests.py` (+ flake sweep)
- **WHAT CHANGED:** Reminder-dispatch tests use a pinned wall-clock instant ("now") instead of the real clock; other suites de-flaked.
- **WHY:** Time-dependent assertions are the classic source of red-on-retry CI.
- **RESULT:** Deterministic suite — same command, same outcome every run.

---

## C. Admin console (12 points)

### 14. `apps/admin-web/src/index.css` + `apps/admin-web/index.html`
- **WHAT CHANGED:** Canonical `:root` design tokens (`--sw-*` palette, `--sw-radius-sm/md/lg/pill`, shadows, z-index) and `<meta name="color-scheme" content="light dark">`.
- **WHY:** Pages previously hardcoded hex colours and radii; the browser chrome ignored dark UI.
- **RESULT:** One source of truth for colour/shape; chrome matches the console.

### 15. `apps/admin-web/src/App.tsx`
- **WHAT CHANGED:** `RequirePerm` / `RouteDenied` / `DashboardRoute` wrappers around the route table.
- **WHY:** Backend authorization must be mirrored by the console — a page should not render (or fetch) for a role that cannot use it.
- **RESULT:** Permission-denied users get an explicit denied state, not a broken page or a data leak.

### 16. `apps/admin-web/src/lib/api/client.ts` + `src/lib/auth/session.ts`
- **WHAT CHANGED:** `ApiError` is thrown instead of being swallowed into a generic "network error"; `FormData` bodies without an explicit `Content-Type`; `response: 'text'` for CSV exports; `updateTokens()` persists the **rotated refresh** token alongside the new access token.
- **WHY:** Retrying/flattening HTTP errors hid 403 validation behind a fake offline message and made the 401-refresh path unreachable; with refresh rotation on, storing only the new access blacklisted the session on the next refresh.
- **RESULT:** Auth errors, validation errors and exports behave correctly; sessions survive rotation.

### 17. `apps/admin-web/src/pages/shared.tsx`
- **WHAT CHANGED:** Shared `DecisionModal` + reason/label helpers.
- **WHY:** Approve/reject decisions were re-implemented per page with inconsistent required-reason handling.
- **RESULT:** One decision dialog, consistent audit-reason enforcement across approval surfaces.

### 18. `apps/admin-web/src/pages/DoctorsVerificationPage.tsx`
- **WHAT CHANGED:** Reworked (+176 lines): evidence layout, decision flow via the shared modal, honest loading/error/empty states.
- **WHY:** Credential decisions are irreversible in impact; the reviewer needs the evidence and the reason in one place.
- **RESULT:** Reviewer can decide without leaving the page, and the reason is captured.

### 19. `apps/admin-web/src/pages/OrganizationsVerificationPage.tsx` + `CampaignsVerificationPage.tsx`
- **WHAT CHANGED:** Same decision pattern, reason handling and state coverage for organizations and campaigns.
- **WHY:** Consistency across the three verification queues.
- **RESULT:** Uniform verification UX; no orphan queues.

### 20. `apps/admin-web/src/pages/RolesPermissionsPage.tsx`
- **WHAT CHANGED:** Driven by the permission-catalog endpoints; grant/revoke requires a reason, with lockout protection surfaced.
- **WHY:** Point 6 exists so the matrix is the live one — the UI must not hardcode roles.
- **RESULT:** Editing reflects the actual backend matrix and can never lock everyone out.

### 21. `apps/admin-web/src/pages/SecurityEventsPage.tsx` + `AuditLogsPage.tsx`
- **WHAT CHANGED:** Filterable, paginated review of security events and audit entries (+141 / +126 lines).
- **WHY:** Append-only audit data is only useful if it can be searched.
- **RESULT:** Investigations are queryable instead of a raw dump.

### 22. `apps/admin-web/src/pages/ModerationPage.tsx` + `NotificationsPage.tsx`
- **WHAT CHANGED:** Moderation queue with decision reasons; notification/broadcast authoring with preview and state handling.
- **WHY:** Community moderation and broadcast messaging are the console's daily operations.
- **RESULT:** Moderators and communicators can act without a developer.

### 23. `apps/admin-web/src/pages/NewsPage.tsx` + `TickerPage.tsx`
- **WHAT CHANGED:** Article and ticker editing with status, scheduling/lifecycle states and validation (+97 / +66 lines).
- **WHY:** The public home ticker and news are the platform's voice; drafts must not publish accidentally.
- **RESULT:** Content lifecycle is controlled from the console.

### 24. `apps/admin-web/src/pages/{AnalyticsPage,EducationContentPage,BrandingPage,DonationsPage,UsersPage,StatusPages}.tsx`
- **WHAT CHANGED:** Analytics charts and totals (+149); education content authoring with upload validation messaging (+142); branding/donations/users/status pages aligned to tokens and shared components (inline `borderRadius` → `var(--sw-radius-*)`).
- **WHY:** These screens carried the most stale hardcoded styling and the weakest empty/error states.
- **RESULT:** Whole console is on the token system with honest states.

### 25. `apps/admin-web/src/pages/DashboardPage.tsx` + `src/components/ui/index.tsx` (KpiCard `className`) + `src/components/layout/styles.css` + deleted `src/components/lib/layouts/AdminShell.tsx`, `src/design/design_tokens.ts`
- **WHAT CHANGED:** Bento control centre: grouped sections (Attention / Platform / Program), 2×2 hero KPI, outstanding-verification queue linking to the permission-aware route, quick actions from `navSectionsFor`, honest all-clear state, trend bars; responsive CSS (2-col ≤1024, 1-col ≤620); dead duplicate shell and unused token file removed.
- **WHY:** The dashboard was a flat KPI list that told the operator nothing about what needed doing, and duplicated layout/token sources.
- **RESULT:** First screen answers "what is waiting on me?" and routes straight to it.

---

## D. Mobile (13 points)

### 26. `apps/mobile/lib/app.dart`
- **WHAT CHANGED:** Route table extended/fixed: `DonorHomePage` and `DoctorEducationPage` registered; `ResetPasswordPage` accepts an optional `token` map argument (same contract as `EmailVerificationPage`) while plain `pushNamed` falls back to the on-page code field; `onUnknownRoute` added.
- **WHY:** Deep links that resolve to no class throw; reset hand-off from e-mail/notification could not pass the code.
- **RESULT:** Every declared route builds; reset accepts a token or a typed code.

### 27. `apps/mobile/lib/core/navigation/app_router.dart`
- **WHAT CHANGED:** `/main-shell` → `/shell` in the protected list; `/education` removed from the protected list with the rationale documented.
- **WHY:** The old entry used a route name no class declared, so the session wall never applied to the real shell; education is `AllowAny` for published content, so gating it sent anonymous readers to the login wall for nothing.
- **RESULT:** Session wall actually guards the shell; anonymous readers can browse published education.

### 28. `apps/mobile/lib/core/navigation/not_found_page.dart` (new)
- **WHAT CHANGED:** Branded 404 page wired to `onUnknownRoute`, localised, with a route back to the root.
- **WHY:** An unknown route previously threw a red screen.
- **RESULT:** Bad links degrade to a recoverable, on-brand screen.

### 29. `apps/mobile/lib/features/home/presentation/pages/home_page.dart`
- **WHAT CHANGED:** Deleted `HomePage.routeName = '/'` and the private `_SignedOutHome` stub.
- **WHY:** `'/'` collided with `PublicHomePage.routeName`, and the ad-hoc stub was one of fifteen inconsistent signed-out states.
- **RESULT:** The public home owns the root route; patient home uses the shared gate.

### 30. `apps/mobile/lib/features/auth/presentation/pages/forgot_password_page.dart` + `reset_password_page.dart`
- **WHAT CHANGED:** Full recovery flow: request → code entry → new password, wired to `AppLocalizations` keys, with the token argument contract above (+56 / +94 lines).
- **WHY:** The flow was incomplete and partly hard-coded English.
- **RESULT:** Password recovery works and is translatable.

### 31. `apps/mobile/lib/features/auth/presentation/pages/signup_page.dart` + `email_verification_page.dart`
- **WHAT CHANGED:** Role-guidance sheet converted to key-based content; verification page copy ("we sent you a notification") localised; resend action.
- **WHY:** Copy claimed e-mail delivery that does not exist; guidance text was English-only.
- **RESULT:** No misleading copy; both languages complete.

### 32. `apps/mobile/lib/features/ai_assistant/data/ai_repository.dart`
- **WHAT CHANGED:** Repository for `POST /api/ai/chat/` with typed request/response, error mapping and offline handling.
- **WHY:** The assistant page had no data layer.
- **RESULT:** Chat has a single testable API boundary.

### 33. `apps/mobile/lib/features/ai_assistant/presentation/pages/ai_assistant_page.dart`
- **WHAT CHANGED:** Real chat UI: message list, composer, typing/empty/error states, streaming-safe layout, health disclaimer.
- **WHY:** A feature page that did nothing is worse than no page.
- **RESULT:** `/ai-assistant` is a working conversation surface (see `test/ai_assistant_chat_test.dart`).

### 34. `apps/mobile/lib/core/l10n/app_localizations.dart`
- **WHAT CHANGED:** `_en` and `_sw` tables extended: footer/about keys, `err.*`, `ai.*`, and a full `auth.*` block (~60 keys); `tr('key', args:)` supports `{{name}}` interpolation; EN/SW parity enforced by `test/localization_parity_test.dart`.
- **WHY:** Large parts of the app rendered the SW-fallback string or hard-coded English.
- **RESULT:** Parity test keeps both languages complete and every static key resolvable.

### 35. `apps/mobile/lib/core/theme/app_colors.dart` + `app_shapes.dart` + `test/design_token_test.dart`
- **WHAT CHANGED:** Canonical 8-step radius scale (`xs 4 … pill 999` + `bottomSheetTop`/`cardBorder`); palette gained `lightAmber`, `navyDeep`, `dividerOnDark`; 67 raw `BorderRadius.circular(N)` across 34 files and all stray `Color(0x…)` literals outside `core/theme/` replaced with tokens; `lib/core/constants/app_colors.dart` kept as a deliberate re-export shim (42 importers).
- **WHY:** Uncoordinated magic numbers make the approved palette drift and forbid safe re-theming.
- **RESULT:** Gate test fails the build on any new raw radius/colour literal.

### 36. `apps/mobile/lib/features/public/presentation/pages/public_home_page.dart`
- **WHAT CHANGED:** Footer and About dialog localised; header gained a one-tap **SOS** action (`_HeaderSosButton`, compact icon-only on narrow toolbars so the brand mark keeps its space) that routes to `/emergency`; mobile menu sheet carries a red SOS entry; fixed the bottom-sheet radius token.
- **WHY:** The public home was the only surface with no emergency affordance, and its footer/about text was English-only.
- **RESULT:** Anonymous visitors reach the emergency flow in one tap (`test/stage440_public_home_test.dart`).

### 37. `apps/mobile/lib/shared/widgets/signed_out_gate.dart` (new)
- **WHAT CHANGED:** Shared signed-out surface (AppBar + lock message + "Sign in" / "Create account"), adopted by **15 pages** (doctor/patient/donor/caregiver homes, notifications, donations, emergency, community, education ×2, medication, health, blood donation, chat, AI assistant).
- **WHY:** Each dashboard had its own ad-hoc fallback — some a bare text, some an unsafe scaffold — so leaving a session felt random.
- **RESULT:** One consistent, navigable signed-out state everywhere.

### 38. Shared widget family — `state_views.dart`, `app_badges.dart`, `feature_cards.dart`, `dashboard_widgets.dart`, `app_emergency.dart`, `admin_shell.dart`, `main_shell.dart`, `app_theme.dart`
- **WHAT CHANGED:** Raw radii/colours in the shared component layer replaced with `AppShapes`/`AppColors` (e.g. empty/error icon containers → `AppShapes.large`, nav-bar indicator → `AppShapes.tile`).
- **WHY:** Shared components set the visual baseline; leaving literals there lets drift re-enter every screen at once.
- **RESULT:** The design system enforces itself at the component layer, not just per page.

---

## Notes on scope and constraints honoured

- Backend enforces authorization — the UI mirrors it but never substitutes for it.
- No duplicate auth/role systems, no mock data, no database reset; Postgres remains down, so all backend verification ran against `config.settings.ephemeral_test`.
- Documentation under `docs/sdlc/` stays the source of truth for requirements, API, roles and screen inventories.
- Official logo and approved palette only; `lib/core/constants/app_colors.dart` is an intentional re-export, not a second palette.
- The emergency route (`/emergency`) is protected: anonymous visitors are handed the sign-in wall rather than a token-less emergency screen.
