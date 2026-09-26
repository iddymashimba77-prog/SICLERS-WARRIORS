# 3.7 Admin Web UI/UX Review

> Self-review of the Stage 3.7 Admin Web UI/UX Design deliverables
> (`admin-web-ui-ux-design.md`, `admin-role-ui-matrix.md`, `admin-navigation.md`,
> `admin-screen-inventory.md`, `admin-component-catalog.md`,
> `admin-screen-role-matrix.md`, `admin-api-ui-traceability.md`).
> Reference gates: mobile UI/UX review (3.6), API review (3.5), data model
> (3.4), permissions (3.3).

---

## 1. Gate Decision

> `PASS WITH MINOR REVISIONS`

No blocking issue; three minor revisions (M-A1–M-A3) are non-blocking and
documented with the exact fix in Stage 4. No `BLOCKED` item remains.

---

## 2. Checklist Traceability (requirements → screen)

| Requirement | Covered in | Screen/Route |
|---|---|---|
| FR-ATH admin login/MFA | AUTH-A-01/03/05 | /auth/login, /auth/mfa-setup, /auth/reauth |
| Verification of doctors | `admin-navigation.md` §7.1; ADM-DOC-001/002 | /app/doctors/verification |
| Facility verification | ADM-FCL-002 | /app/facilities/:fid |
| Campaign approval | §7.2; ADM-DON-001/002 | /app/donations/campaigns/:cid/verification |
| Blood request workflow | §7.3; ADM-BLD-001/002/004 | /app/blood/* |
| Emergency monitoring | §7.4; ADM-EMG-001..3 | /app/emergency |
| Donation/payment ops | §7.5; ADM-DON-003/004 | /app/donations/transactions, /reconciliation |
| Community moderation | §7.6; ADM-COM-001/002 | /app/community/reports |
| Education CMS | ADM-EDU-001..3 | /app/education |
| Broadcast notifications | ADM-COM-MSG-1/NOT | /app/notifications/broadcast |
| Audit completeness | ADM-AUD-001 | /app/audit |
| Analytics/export | ADM-RPT-001/002 | /app/reports/analytics |
| Users/permissions | ADM-USR-001..5 | /app/users |
| Data privacy (data minimization) | ADM-PAT-001..4 (C4), §32 | /app/patients |
| Mobile relationship | §42 | — |

All 13 FR domains of the admin surface are covered; none invented.

---

## 3. Consistency Checks

| Check | Result |
|---|---|
| 38 mandated sections present in `admin-web-ui-ux-design.md` | ✓ (1–38) |
| Extensions (workflow, threat, traceability, mobile relationship, innovation) | ✓ (§39–43) |
| Screens in inventory match route map (§1 nav) | ✓ 52 rows == routes + states |
| Role matrix (3.7) consistent with 3.3 permission matrix | ✓ (SUP exclusivity C17, VO scoped, MOD community-only, ADM no privileged assign) |
| Screen-role matrix consistent with inventory roles column | ✓ (V/H map exact) |
| Trace table endpoints ⊆ 3.5 matrix (or marked GAP) | ✓ 18 GAP explicitly flagged; none invented |
| No sensitive chat endpoint referenced | ✓ |
| Red reserved for emergency/danger only | ✓ (tokens §31, StatusBadge, Confirmation danger) |
| Non-colour-only statuses | ✓ (badge = colour+icon+text) |
| PHI only behind C4 gate + reason | ✓ (COM-P-001) |
| Mermaid blocks present (≥6 mandated) | ✓ 6 workflows §7.1–7.6 |
| `admin-web-design.md` marked SUPERSEDED | ✓ (kept for history) |
| Apps/admin-web empty — greenfield honored (no fabricated scaffold) | ✓ |
| No fabricated secret/credential handling | ✓ (never render secrets; masked fields) |

---

## 4. Open Design Decisions

All 15 (AD-A-1..15) documented in §38 with defaults. No decision silently
invents security or architecture (framework React default AD-A-1 is a
build/deployment decision; logged, not a bypass).

---

## 5. Threats (Design Threat Review)

| # | Threat | Severity | Mitigation | Where |
|---|---|---|---|---|
| T-A1 | Privilege escalation via UI path | High | menu filters + backend authoritative 403; C17 exclusive; COM-P-001 | §33 §36; screen-role matrix |
| T-A2 | Accidental PHI exposure on list vs detail | High | list = PHI-free rows; detail behind C4 gate + reason; masked contacts | §7 §32; ADM-PAT-001..4 |
| T-A3 | Unauth patient access via deep-link | High | route guard + object-level check; 403 panel | §5 nav; §36 |
| T-A4 | Export PHI leak | Medium | aggregate-only; scope preview; export gate; audit | §20 §28; ADM-RPT-002 |
| T-A5 | Dangerous bulk actions | Medium | whitelist + typed confirmation; no bulk delete/refund/PHI export | §27 §38 |
| T-A6 | Signed-file viewing leakage | Medium | FileViewer streams signed URL; no raw path/cache | Components §20 |
| T-A7 | Session hijacking | High | short TTL + idle timeout + deny-list logout + reauth ops | §33 AD-A-2 |
| T-A8 | Unauthorized moderation | Low | `community.moderate` SUP/ADM/MOD; reason; hide-first; reversible | §16 |
| T-A9 | Unauthorized refund/campaign decision | Medium | policy-gated; co-sign thresholds co-sign via config | §13 AD-A-11 |
| T-A10 | Unauthorized emergency override | High | C10-bound, bounded; C4; actions confirmed+audited | §12 AD-A-9 |

Every threat mapped to at least one design/API guard. No threat unmitigated.

---

## 6. Minor Revisions (non-blocking)

- **M-A1** — `admin-web-ui-ux-design.md` §34 "typed client layer" should name
  the concrete HTTP client (`axios` or `fetch` wrapper) and refresh-interceptor
  in Stage 4 build notes (framework AD-A-1 default React). *Fix in Stage 4
  implementation planning.*
- **M-A2** — `ADM-RPT-002` export flow could specify exact column stripper
  rules per report type (aggregates) — move from generic to a per-report
  contract when exports get their API (currently gap). *Fix tied to the export
  endpoint resolution.*
- **M-A3** — `admin-screen-inventory.md` §16 "Gaps" for Education/Settings
  lists several gap rows; keep a single tracked GAP-register in 3.5
  `api-endpoint-matrix.md` (append admin rows) rather than duplicate counts.
  *Fix: sync endpoint matrix with 18 GAP rows for Stage 4.*

None block progression; each is a Stage 4 addendum. Full compliance:

- Mandated 38 sections: complete.
- Six mandated workflow diagrams (doctor, campaign, blood, emergency,
  donation, moderation): complete.
- Screen inventory COMPLETE (52 screens), role matrix EXACT, traceability
  COMPLETE with GAP policy, no invented endpoint/role/PHI.

**Stage 3.7 CLOSES PASS WITH MINOR REVISIONS.**

---

END OF STAGE 3.7 — awaiting owner approval to proceed to Stage 3.8 Security
Design.