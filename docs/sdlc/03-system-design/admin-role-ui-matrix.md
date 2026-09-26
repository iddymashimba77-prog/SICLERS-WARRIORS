# 3.7 Admin Role ↔ UI Capability Matrix

> Sources of truth: `role-permission-matrix.md` / `role-permission-design.md`
> (3.3) and `api-endpoint-matrix.md` (3.5). Admin-panel roles are exactly the
> approved administrative roles: **SUPER_ADMIN, ADMIN, VERIFICATION_OFFICER,
> MODERATOR**. No new privileged roles are introduced by this document.
>
> Cell values: `A` Allow · `C<cond>` Conditional (see legend) · `D` Denied ·
> `—` not applicable. **UI visibility is not security** — backend authorization
> remains authoritative. `?` = needs an open design decision (never invented).

Legend (from 3.3): C4 audit/oversight only · C6 verification-scoped/unverified
identity scope · C7 facility context · C10 emergency override (bounded) ·
C11 verified campaign · C12 educational review · C13 chat participants ·
C17 SUP-only privileged assign.

---

## 1. Roles in scope

| Role | Code | Dashboard | Operational scope | Elevated-only |
|---|---|---|---|---|
| SUPER_ADMIN | SUP | Full platform KPIs | All admin modules + patient oversight (C4) | role/permission assignment, security center, system settings, analytics export, audit export |
| ADMIN | ADM | Full (ops) KPIs | User/verification/payment/emergency ops, education, moderation | **cannot assign privileged roles** (C17); refunds C4-gated |
| VERIFICATION_OFFICER | VO | Verification KPIs only | Doctor/blood/campaign verification queues + own-scope audit | approve/reject decisions (all audited) |
| MODERATOR | MOD | Moderation KPIs only | Community reports/moderations | content removal/report resolution |

HOSPITAL operations stay on the mobile/clinical surface; **not** in this panel
v1 (documented decision AD-A-13).

---

## 2. Module × Role × Action matrix

| Module | Role | View | Create | Edit | Delete | Approve | Reject | Export | Sensitive Data |
|---|---|---|---|---|---|---|---|---|---|
| Dashboard | SUP | A | — | — | — | — | — | — | aggregate KPIs (no PHI) |
| Dashboard | ADM | A | — | — | — | — | — | — | aggregate KPIs (no PHI) |
| Dashboard | VO | A (verification) | — | — | — | — | — | — | queue counts only |
| Dashboard | MOD | A (moderation) | — | — | — | — | — | — | report counts only |
| Users | SUP | A | A | A | A (deactivate/suspend) | A (verify) | C17-restricted | C17 charter | no medical data on user page |
| Users | ADM | A | A | A | A (deactivate/suspend) | A (verify) | D | D | no medical data on user page |
| Users | VO | C6 (verification ctx) | D | D | D | A (verify) | D | D | identity docs (scoped) |
| Users | MOD | D | D | D | D | D | D | D | — |
| Patients | SUP | C4 (oversight) | D | A (operational edit) | D | — | — | D | PHI — C4 only, audited, reason-locked |
| Patients | ADM | C4 | D | A (operational edit) | D | — | — | D | PHI — C4 only, audited, reason-locked |
| Patients | VO | D | D | D | D | D | D | D | — |
| Patients | MOD | D | D | D | D | D | D | D | — |
| Doctors (registry) | SUP | A | — | A | suspend (A) | A (`doctors.verify`) | A | A | licenses/documents (scoped) |
| Doctors (registry) | ADM | A | — | A | suspend (A) | A | A | A | licenses/documents (scoped) |
| Doctors (registry) | VO | A (verify scope) | — | D | D | A | A | D | licenses/documents (verify only) |
| Doctors (registry) | MOD | A (directory) | D | D | D | D | D | D | public subset only |
| Facilities | SUP | A | A | A | D | A (`/admin/facilities/{uid}/verify`) | A | A | contacts, staff list (operational) |
| Facilities | ADM | A | A | A | D | A | A | A | contacts, staff list (operational) |
| Facilities | VO | A (verify scope) | D | D | D | A | A | D | verify docs only |
| Facilities | MOD | D | D | D | D | D | D | D | — |
| Caregivers | SUP | C4 | D | D | A (remove) | — | — | D | relationship/scope — C4 |
| Caregivers | ADM | C4 | D | D | A (remove) | — | — | D | relationship/scope — C4 |
| Caregivers | VO | D | D | D | D | D | D | D | — |
| Caregivers | MOD | D | D | D | D | D | D | D | — |
| Blood requests | SUP | A | A | A | D (immutable) | A | A | A | no donor PII; needs/units |
| Blood requests | ADM | A | A | A | D | A | A | A | no donor PII; needs/units |
| Blood requests | VO | C6/7 (queue) | D | D | D | A | A | D | verify scope only |
| Blood requests | MOD | D | D | D | D | D | D | D | — |
| Blood donors | SUP | A | — | A | D | — | — | A | masked (region/group only) |
| Blood donors | ADM | A | — | A | D | — | — | A | masked (region/group only) |
| Blood donors | VO | C6/7 | — | D | D | A (verify) | A | D | masked; verify docs |
| Blood matches | SUP | A | run (A) | — | — | — | — | — | matched pairs (C9) |
| Blood matches | ADM | A | run (A) | — | — | — | — | — | matched pairs (C9) |
| Blood matches | VO | C6/7 | run (A) | — | — | D | D | D | matched pairs (C9) |
| Emergency | SUP | A (C4 monitor) | A | A | D | — | — | — | operational info; PHI minimal (C4) |
| Emergency | ADM | A (C4 monitor) | A | A | D | — | — | — | operational info; PHI minimal (C4) |
| Emergency | VO | D | D | D | D | D | D | D | — |
| Emergency | MOD | D | D | D | D | D | D | D | — |
| Donations/payments | SUP | A | — | — | D | refund (A) | — | A | amounts, payer refs (redacted value) |
| Donations/payments | ADM | A | — | — | D | refund (A, C4) | — | A (C4) | amounts, payer refs (redacted value) |
| Donations/payments | VO | D | D | D | D | D | D | D | — |
| Donations/payments | MOD | D | D | D | D | D | D | D | — |
| Campaigns | SUP | A | A | A | suspend (A) | A | A | A | beneficiary info (verified docs) |
| Campaigns | ADM | A | A | A | suspend (A) | A | A | A | beneficiary info (verified docs) |
| Campaigns | VO | A (verify scope) | D | D | D | A | A | D | verify docs only |
| Campaigns | MOD | A (public view) | D | D | D | D | D | D | public subset |
| Appointments | SUP | `?` (AD-A-6) | D | D | D | D | D | D | schedule data only |
| Appointments | ADM | `?` (AD-A-6) | D | D | D | D | D | D | schedule data only |
| Appointments (admin v1) | VO / MOD | D | D | D | D | D | D | D | — |
| Community moderation | SUP | A | A | — | A (remove/hide) | — | — | A | reported content, reporter (masked) |
| Community moderation | ADM | A | A | — | A (remove/hide) | — | — | A | reported content, reporter (masked) |
| Community moderation | MOD | A | A | — | A (remove/hide) | — | — | D | reported content, reporter (masked) |
| Community moderation | VO | D | D | D | D | D | D | D | — |
| Education | SUP | A | A | A | A (archive) | A (`education.review`) | A | A | drafts (unpublished locked) |
| Education | ADM | A | A | A | A (archive) | A | A | A | drafts (unpublished locked) |
| Education | VO | D | D | D | D | D | D | D | — |
| Education | MOD | D | D | D | D | D | D | D | — |
| Notifications | SUP | A | A (broadcast) | A | D | — | — | A | previews sanitised (no PHI) |
| Notifications | ADM | A | A (broadcast) | A | D | — | — | A | previews sanitised (no PHI) |
| Notifications | VO / MOD | A (own) | D | D | D | D | D | D | own prefs only |
| Reports & analytics | SUP | A | — | — | — | — | — | A | aggregates only (AD-7/3.5) |
| Reports & analytics | ADM | A | — | — | — | — | — | C4 | aggregates only |
| Reports & analytics | VO | C6 (scope) | — | — | — | — | — | D | verification metrics |
| Reports & analytics | MOD | D | D | D | D | D | D | D | — |
| Audit logs | SUP | A | — | — | D (append-only) | — | — | A | actor/action/object; no PHI body |
| Audit logs | ADM | A | — | — | D | — | — | C4 | actor/action/object; no PHI body |
| Audit logs | VO | C6 (own actions) | — | — | D | — | — | D | own decisions only |
| Audit logs | MOD | D | D | D | D | D | D | D | — |
| Security center | SUP | A | — | A | D | — | — | A | no credentials/secrets ever |
| Security center | ADM | C4 ? (AD-A-7) | — | D | D | — | — | C4 ? | no credentials/secrets |
| Security center | VO / MOD | D | D | D | D | D | D | D | — |
| System settings | SUP | A | — | A | D | — | — | — | secret-configs elevated (MFA+reauth) |
| System settings | ADM | C4 ? (AD-A-8) | — | C4 ? | D | — | — | — | secret-configs elevated |
| System settings | VO / MOD | D | D | D | D | D | D | D | — |

---

## 3. Role capability summary

| Capability | SUP | ADM | VO | MOD |
|---|---|---|---|---|
| Users CRUD + roles | Full (C17 assign) | Full ops (no privileged assign) | verify context | — |
| Verification queues (doctor/blood/campaign/facility) | Full | Full | Full | — |
| Patient PHI access | C4 only (reason) | C4 only (reason) | — | — |
| Medical records | C4 download scope only | C4 download scope only | — | — |
| Payments/refunds | Full (policy-gated) | Full (policy+co-sign) | — | — |
| Emergency ops | Full (C4 monitor) | Full (C4 monitor) | — | — |
| Community moderation | Full | Full | — | Full |
| Education publish/review | Full | Full | — | — |
| Broadcast notifications | Full | Full | — | — |
| Analytics + export | Full | Full (C4 export) | scoped view | — |
| Audit logs + export | Full | Full (C4 export) | own scope | — |
| Role/permission assignment | **Exclusive** (C17) | — | — | — |
| System settings/security center | **Exclusive** | conditional (AD-A-7/8) | — | — |

**Least-privilege invariants (enforced at backend, reflected in UI):**
1. MOD sees nothing medical/operational — community only.
2. VO sees verification queues + its own audit, nothing financial/medical.
3. ADMIN cannot assign privileged roles or export PHI-groups freely (C4/C17).
4. SUP's medical access is audit-reasoned C4 — the panel requires a stated
   reason before any protected-resource open, always logged (AD-A-9).
5. No administrative role ever reaches private doctor↔patient chats
   (`chat.*` = D for all admin roles).

---

END — exact per-screen mirror in `admin-screen-role-matrix.md`.