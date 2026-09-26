# 3.7 Admin Component Catalog

> Reusable UI component catalog for the admin web panel. Each entry: purpose,
> variants, states, accessibility contract, token mapping, data rules, and
> audit hooks. Aligned with the design tokens in
> `admin-web-ui-ux-design.md` §31 and the mobile component naming (C-*) where
> applicable; admin components are desktop-first variants prefixed `AD-`.

---

## 1. Naming & Structure

| Prefix | Meaning |
|---|---|
| `AD-` | Admin component (web) |
| `C-*` | Shared tokenised primitive shared with mobile concept (restyled for desktop density) |
| `HOC` | wrapper (auth/guard/gate) |

Composition: pages compose from these; no page-specific one-off buttons.

---

## 2. Component Index

| # | Component | Variants | Priority | Category |
|---|---|---|---|---|
| 1 | AD-AppShell | light/windowed | core | layout |
| 2 | AD-Sidebar | collapsed/expanded/drawer | core | navigation |
| 3 | AD-TopBar | default/dense | core | navigation |
| 4 | AD-Breadcrumb | 2–3 level | core | navigation |
| 5 | AD-SearchBar | global / inline / filter | core | input |
| 6 | AD-FilterPanel | inline / dropdown / chips | core | input |
| 7 | AD-DataTable | sortable / bulk / card | core | data |
| 8 | AD-Pagination | default / compact | core | data |
| 9 | AD-StatusBadge | success/warn/error/info/neutral | core | data |
| 10 | AD-KpiStrip | 4/3/2 cards | core | dashboard |
| 11 | AD-DashboardCard | summary / widget | core | dashboard |
| 12 | AD-Chart | line/bar/pie | core | dashboard |
| 13 | AD-ApprovalPanel | approve/reject/correct | core | workflow |
| 14 | AD-ReasonInput | text/sel chips | core | workflow |
| 15 | AD-ConfirmationDialog | ok/typed/consolidated | core | dialogs |
| 16 | AD-ProtectedGate | reason / reauth | core | security |
| 17 | AD-DetailPanel | three-region | core | detail |
| 18 | AD-AuditTimeline | compact / full | core | audit |
| 19 | AD-AuditTable | explorer | core | audit |
| 20 | AD-FileViewer | image/pdf/inline | core | file |
| 21 | AD-NotificationPanel | bell/queue/broadcast | core | comms |
| 22 | AD-Composer | broadcast/template | core | comms |
| 23 | AD-ContentEditor | markdown/file | core | education |
| 24 | AD-Spoiler | report content | core | moderation |
| 25 | AD-EmptyState / AD-ErrorState / AD-LoadingState | resource-specific | core | states |
| 26 | AD-ForbiddenPanel / AD-NotFoundPanel | resource-specific | core | states |
| 27 | AD-TableDensity | tight/comfortable | future | table |
| 28 | AD-DataExport | CSV/Excel/PDF | future | export |

---

## 3. Core Components Detail

### AD-AppShell
- Left sidebar + top bar + breadcrumb + content outlet.
- Tokens: surface `#FFFFFF`, bg `#F6F9FC`, sidebar bg `#12202F`? — no: light-only
  shell v1; sidebar surface same light token, active item primary tint.
- Role-filtered sections (§5 nav). A11y: `role=navigation` landmarks each.

### AD-Sidebar
- Props: sections (filtered), activeKey, queueBadges.
- Expanded ≥1024; drawer ≤1024; focus trap on drawer; ESC.
- Token: item padding 10×12, radius 4, active bg primary-25, focus outline.

### AD-DataTable
- Server-driven: `data`, `columns`, `sortable`, `rowActions`, `selectable`.
- States: loading (skeleton), empty (EmptyState), error (ErrorState)
- Column visibility toggle; density toggle (tight default).
- A11y: `role=grid`, caption, `aria-sort` on sort headers; sticky header.
- Data rules: renders only fields authorized (permission-resolved columns).

### AD-StatusBadge
- `color + icon + text` — never colour-only (WCAG 1.4.1).
- Levels: success/teal, warn/amber, error/red, info/blue, neutral.
- Tooltip: description + state label.

### AD-ApprovalPanel
- Approve / Request correction / Reject with reason-lock.
- Shows reviewer, timestamp when decided; co-sign hint where configured.
- Submits content, resets on error; audit event on decide.

### AD-ReasonInput
- `<textarea>` + clarity hint; required before destructive path; write once
  and shared with audit.

### AD-ConfirmationDialog
- Modes: `ok` (standard), `typed` (type the object/resource name), 
  `consolidated` (typed + reason + rights acknowledgement) for C4/refund/
  security actions.
- Track: primary danger red reserved for destructive.
- A11y: modal, focus trap, `aria-describedby`, return focus, ESC.

### AD-ProtectedGate
- Shown before any C4 screen; reason options (audit/oversight/operational
  need) + justification free text; triggers `audit_logs.access_open`;
  auto-close on idle.

### AD-FileViewer
- Image/PDF inline render from signed URL; no raw path exposure; read-only;
  download button only when permission allows; streams server-side.

### AD-AuditTimeline
- Timeline of `action/actor/time/result` for a resource; link to audit
  explorer; never renders PHI body content.

### AD-Composer (broadcast)
- Target: role picker (never free-form user list), priority class
  (normal/urgent/emergency), schedule, **PrivacyPreview** — renders resolved
  message with any masked-out sections replaced by `[…]`, confirming no PHI
  leaks before send.

### AD-ContentEditor (education)
- Markdown (core) + file picker; draft saved via `draft` endpoint; `PUBLISH`
  disabled until review passes; keeps `publish` behind permission.

### AD-Spoiler
- Moderation content preview masked until user clicks; confusion avoided with
  explicit "reveal".

### State components
- `AD-EmptyState` : title/detail/CallToAction, token `#5C6B7A`, icon.
- `AD-ErrorState` : error + `Retry`.
- `AD-LoadingState` : skeleton.
- `AD-ForbiddenPanel` : «You do not have permission» (no implication content
  exists) + Home link.
- `AD-NotFoundPanel` : 404 + Home.

---

## 4. Tokens (§31 reuse)

| Token | Value | Used in |
|---|---|---|
| color-primary `#0D47A1` | action/active states | buttons, links, focus |
| color-secondary `#1976D2` | info accent | badges, charts |
| color-accent-red `#C62828` | **danger/emergency only** | destructive, emergency |
| color-success `#00897B` | success badges | approve, verified |
| color-warning `#F9A825` | warning badges | pending, review |
| bg surface/alt `#FFFFFF`/`#F6F9FC`, border `#DCE4EE` | shell, tables | all |
| text `#12202F`/`#5C6B7A` | primary/secondary | all |
| spacing base `4px`; radius `4/8/12`; height rows 44–48 | density | all |
| font body 14, table 14, H1 20, H2 16 | type scale | all |

---

## 5. Interaction & Accessibility Checklist (applies to all)

- 48×48 min targets anywhere hover/dropdown; focus visible everywhere.
- Status is never color-only.
- Table captions + sort aria.
- Dialogs: focus trap, restore focus, `aria-modal`, ESC.
- Reduced motion supported.
- Tooltips not the only information carrier.
- All actions keyboard reachable.

---

## 6. Data & Security Rules

- No component may render a field the API could refuse (permission-resolved
  column/fragment model).
- Page-level state never caches PHI beyond the route; on unmount clear local
  state; no localStorage of sensitive results.
- Every destructive action goes through ConfirmationDialog (typed mode for C4/
  refund/security) and writes audit.
- Signed URL values pass through FileViewer, not raw `src`.

---

END — next: `admin-screen-role-matrix.md`.