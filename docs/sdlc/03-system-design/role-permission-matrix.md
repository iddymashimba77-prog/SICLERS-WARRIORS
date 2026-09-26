# 3.3 Role — Permission Matrix

> Companion to `role-permission-design.md` (§7). This file is the authoritative
> permission catalog and role→permission matrix.
>
> Legend: **A** = ALLOW · **D** = DENY · **C** = CONDITIONAL (see condition
> notes below; cells may carry several, e.g. `C2/3` = conditions C2 **and** C3).
>
> Roles (columns): **SUP** SUPER_ADMIN · **ADM** ADMIN · **VO**
> VERIFICATION_OFFICER · **MOD** MODERATOR · **DOC** DOCTOR · **STA**
> HEALTHCARE_STAFF · **HOS** HOSPITAL · **PAT** PATIENT · **CAR** CAREGIVER ·
> **BLD** BLOOD_DONOR · **FIN** FINANCIAL_DONOR · **ORG** ORGANIZATION.

---

## 1. Matrix reading rules

1. Deny by default: `D` (or absence) means denied.
2. Sensitive medical operations prefer `CONDITIONAL`, never `ALLOW`
   (`medical_records.*`, `medications.*`, `symptoms.*`, `consents.*`).
3. Admin roles never get blanket medical access (`C4` audit/oversight only).
4. Only the PATIENT may grant/revoke patient consent.
5. MED/medical permissions never flow into BLD/FIN workflows (multi-role
   aggregation keeps permission boundaries intact — role-permission-design §22).
6. `ALLOW` still requires object-level authorization + account status
   (§17, §20 of the design); it is never a blank cheque.

---

## 2. Conditional note definitions

| Code | Condition |
|---|---|
| C2 | Active, unexpired **patient consent** required (scope + duration + purpose). BR-002/003/004 |
| C3 | Target object must be in caller's **authorized object set** (owned / linked / consent-granted) |
| C4 | **Audit/oversight only**: recorded reason required, always audited, no habitual/indiscriminate access |
| C5 | Requires **professional verification** (doctor APPROVED / facility verified) before activation |
| C6 | Only within **verification/approval workflow scope**; every decision carries a reason and is audited |
| C7 | Only within caller's **facility/clinical context**; donor contact info never publicly exposed (BR-006) |
| C8 | **Eligible donors only** (compatible blood group, location, availability); requester PHI limited to need |
| C9 | **Own** match/request only |
| C10 | **Time-bounded emergency override policy**: limited lifesaving subset, authorized, auto-expiry, full audit (§16) |
| C11 | Campaign is public **only after verification** (BR-007); creator submits draft for review |
| C12 | Content requires **approval/review** workflow before publication |
| C13 | **Participant-bound** (conversation membership) object-level check |
| C13b | Only with a **verified professional** (doctor) partner |
| C14 | Only for **self or an authorized (caregiver/consent) patient** |
| C15 | Requires **clinical relationship + consent** (authorized context); clinical entries attributed to the actor |
| C16 | **Self-entered entries only**, soft-delete, own scope |
| C17 | **ADMIN may assign only non-privileged roles**; privileged-role assignment is SUPER_ADMIN-only; self-assignment always denied; every change audited |

---

## 3. Permission catalog and matrix

### 3.1 Authentication (`auth`)

| Permission | SUP | ADM | VO | MOD | DOC | STA | HOS | PAT | CAR | BLD | FIN | ORG |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| `auth.login` | A | A | A | A | A | A | A | A | A | A | A | A |
| `auth.logout` | A | A | A | A | A | A | A | A | A | A | A | A |
| `auth.password_reset` | A | A | A | A | A | A | A | A | A | A | A | A |
| `auth.profile_view` | A | A | A | A | A | A | A | A | A | A | A | A |
| `auth.mfa_manage` | A | A | A | A | A | A | A | A | A | A | A | A |

### 3.2 Users (`users`) — account administration

| Permission | SUP | ADM | VO | MOD | DOC | STA | HOS | PAT | CAR | BLD | FIN | ORG |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| `users.view` | A | A | C6 | D | D | D | D | D | D | D | D | D |
| `users.create` | A | A | D | D | D | D | D | D | D | D | D | D |
| `users.update` | A | A | D | D | D | D | D | D | D | D | D | D |
| `users.deactivate` | A | A | D | D | D | D | D | D | D | D | D | D |
| `users.role_assign` | A | C17 | D | D | D | D | D | D | D | D | D | D |
| `users.verify` | A | A | A | D | D | D | D | D | D | D | D | D |

### 3.3 Patients (`patients`)

| Permission | SUP | ADM | VO | MOD | DOC | STA | HOS | PAT | CAR | BLD | FIN | ORG |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| `patients.view` | C4 | C4 | D | D | C2/3 | C2/3/7 | C2/3/7 | A | C2/3 | D | D | D |
| `patients.update` | A | A | D | D | D | D | D | D | D | D | D | D |
| `patients.update_own` | D | D | D | D | D | D | D | A | D | D | D | D |
| `patients.manage_caregivers` | D | D | D | D | D | D | D | A | D | D | D | D |

> PAT `patients.view` is `A` but always resolves to **own** profile (owner
> scope, design §8). `patients.update` is an admin *operational* edit, distinct
> from the patient's `update_own`.

### 3.4 Medical records (`medical_records`)

| Permission | SUP | ADM | VO | MOD | DOC | STA | HOS | PAT | CAR | BLD | FIN | ORG |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| `medical_records.view` | C4 | C4 | D | D | C2/3 | C2/3/7 | C2/3/7 | A | C2/3 | D | D | D |
| `medical_records.create` | D | D | D | D | C15 | C15/7 | C15/7 | C16 | D | D | D | D |
| `medical_records.update` | D | D | D | D | C15 | C15/7 | C15/7 | C16 | D | D | D | D |
| `medical_records.download` | C4 | C4 | D | D | C2/3 | C2/3/7 | C2/3/7 | A | C2/3 | D | D | D |
| `medical_records.upload` | D | D | D | D | C15 | C15/7 | C15/7 | A | D | D | D | D |
| `medical_records.delete` | C4 | C4 | D | D | D | D | D | C16 | D | D | D | D |

> `medical_records` values are the hard-case exemplar: no non-owner role carries
> a plain `ALLOW`. Download requires a consent scope that includes it and is
> always logged.

### 3.5 Medications (`medications`)

| Permission | SUP | ADM | VO | MOD | DOC | STA | HOS | PAT | CAR | BLD | FIN | ORG |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| `medications.view` | D | D | D | D | C2/3 | C2/3/7 | C2/3/7 | A | C2/3 | D | D | D |
| `medications.create` | D | D | D | D | C2/3 | C2/3/7 | C2/3/7 | A | C2/3 | D | D | D |
| `medications.update` | D | D | D | D | C2/3 | D | D | A | C2/3 | D | D | D |
| `medications.delete` | D | D | D | D | C2/3 | D | D | A | C2/3 | D | D | D |

### 3.6 Appointments (`appointments`)

| Permission | SUP | ADM | VO | MOD | DOC | STA | HOS | PAT | CAR | BLD | FIN | ORG |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| `appointments.view` | D | D | D | D | C2/3 | C7 | C7 | A | C2/3 | D | D | D |
| `appointments.create` | D | D | D | D | C2/3 | C7 | C7 | A | C2/3 | D | D | D |
| `appointments.update` | D | D | D | D | C2/3 | C7 | C7 | A | D | D | D | D |
| `appointments.cancel` | D | D | D | D | C2/3 | C7 | C7 | A | D | D | D | D |

### 3.7 Symptoms / pain (`symptoms`)

| Permission | SUP | ADM | VO | MOD | DOC | STA | HOS | PAT | CAR | BLD | FIN | ORG |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| `symptoms.view` | D | D | D | D | C2/3 | C2/3/7 | C2/3/7 | A | C2/3 | D | D | D |
| `symptoms.create` | D | D | D | D | D | C7 | D | A | D | D | D | D |
| `symptoms.analyze` | D | D | D | D | C2/3 | D | D | A | C2/3 | D | D | D |

### 3.8 Blood network (`blood_donors`, `blood_requests`, `blood_matches`)

| Permission | SUP | ADM | VO | MOD | DOC | STA | HOS | PAT | CAR | BLD | FIN | ORG |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| `blood_donors.self_manage` | D | D | D | D | D | D | D | D | D | A | D | D |
| `blood_donors.view` | A | A | C6/7 | D | D | A | C7 | D | D | D | D | D |
| `blood_requests.create` | A | A | D | D | C15/3 | C7 | C7 | A | C14 | D | D | D |
| `blood_requests.view` | A | A | C6/7 | D | C3 | C7 | C7 | A | C2 | C8 | D | D |
| `blood_requests.verify` | A | A | A | D | D | D | D | D | D | D | D | D |
| `blood_requests.respond` | D | D | D | D | D | D | D | D | D | A | D | D |
| `blood_matches.view` | A | A | C6/7 | D | D | C7 | C7 | C9 | D | C9 | D | D |
| `blood_matches.run` | A | A | A | D | D | D | D | D | D | D | D | D |

> BR-005: only verified blood requests become publicly active. BR-006: donor
> contact information is never exposed publicly — reflected in `C7/C8`.

### 3.9 Emergency (`emergency_requests`)

| Permission | SUP | ADM | VO | MOD | DOC | STA | HOS | PAT | CAR | BLD | FIN | ORG |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| `emergency_requests.create` | A | A | D | D | A | A | A | A | C14 | D | D | D |
| `emergency_requests.view` | A | A | D | D | A | A | A | A | A | D | D | D |
| `emergency_requests.manage` | A | A | D | D | C | C | A | C | C | D | D | D |
| `emergency_requests.resolve` | A | A | D | D | C | C | A | C | C | D | D | D |
| `emergency_requests.override_access` | A | C10 | D | D | C10 | C10 | C10 | C10 | C10 | D | D | D |

> `emergency_requests` manage/resolve for DOC/STA/PAT/CAR are always scoped to
> requests they are part of (responder/owner). No `EMERGENCY = BYPASS ALL`
> rule (§16 badge).

### 3.10 Campaigns (`campaigns`)

| Permission | SUP | ADM | VO | MOD | DOC | STA | HOS | PAT | CAR | BLD | FIN | ORG |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| `campaigns.create` | A | A | D | D | D | D | D | C11 | D | D | D | C11 |
| `campaigns.view` | A | A | A | A | A | A | A | A | A | A | A | A |
| `campaigns.verify` | A | A | A | D | D | D | D | D | D | D | D | D |

### 3.11 Donations & payments (`donations`, `payments`)

| Permission | SUP | ADM | VO | MOD | DOC | STA | HOS | PAT | CAR | BLD | FIN | ORG |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| `donations.create` | A | A | A | A | A | A | A | A | A | A | A | A |
| `donations.view` | A | A | D | D | D | D | D | D | D | D | A | A |
| `donations.refund` | A | A | D | D | D | D | D | D | D | D | D | D |
| `payments.view` | A | A | D | D | D | D | D | D | D | D | A | A |
| `payments.refund` | A | A | D | D | D | D | D | D | D | D | D | D |
| `payments.verify` | D | D | D | D | D | D | D | D | D | D | D | D |

> `payments.verify` is service-internal (provider callback + signature
> verification, BR-008); no human role holds it. Any authenticated user may
> donate (`donations.create` = A), but only to **verified** campaigns (C11
> enforced at the campaign, not via this row).

### 3.12 Community (`community`)

| Permission | SUP | ADM | VO | MOD | DOC | STA | HOS | PAT | CAR | BLD | FIN | ORG |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| `community.create_post` | A | A | A | A | A | A | A | A | A | A | A | A |
| `community.comment` | A | A | A | A | A | A | A | A | A | A | A | A |
| `community.report` | A | A | A | A | A | A | A | A | A | A | A | A |
| `community.moderate` | A | A | D | A | D | D | D | D | D | D | D | D |

### 3.13 Consents (`consents`)

| Permission | SUP | ADM | VO | MOD | DOC | STA | HOS | PAT | CAR | BLD | FIN | ORG |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| `consents.grant` | D | D | D | D | D | D | D | A | D | D | D | D |
| `consents.revoke` | D | D | D | D | D | D | D | A | D | D | D | D |
| `consents.view` | C4 | C4 | C6 | D | C3 | D | D | A | C3 | D | D | D |

> Only the patient grants/revokes. `consents.view` for a grantee exposes only
> the grant in which they are the named authorized user.

### 3.14 Doctors (`doctors`)

| Permission | SUP | ADM | VO | MOD | DOC | STA | HOS | PAT | CAR | BLD | FIN | ORG |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| `doctors.view` | A | A | A | A | A | A | A | A | A | A | A | A |
| `doctors.self_manage` | D | D | D | D | A | D | D | D | D | D | D | D |
| `doctors.verify` | A | A | A | D | D | D | D | D | D | D | D | D |

### 3.15 Caregivers (`caregivers`)

| Permission | SUP | ADM | VO | MOD | DOC | STA | HOS | PAT | CAR | BLD | FIN | ORG |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| `caregivers.invite` | D | D | D | D | D | D | D | A | D | D | D | D |
| `caregivers.view` | C4 | C4 | D | D | D | D | D | A | C3 | D | D | D |
| `caregivers.modify` | D | D | D | D | D | D | D | A | D | D | D | D |
| `caregivers.remove` | D | D | D | D | D | D | D | A | D | D | D | D |

### 3.16 Education (`education`)

| Permission | SUP | ADM | VO | MOD | DOC | STA | HOS | PAT | CAR | BLD | FIN | ORG |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| `education.view` | A | A | A | A | A | A | A | A | A | A | A | A |
| `education.publish` | A | A | D | D | C12 | D | D | D | D | D | D | C12 |
| `education.review` | A | A | D | D | D | D | D | D | D | D | D | D |

### 3.17 Chat (`chat`)

| Permission | SUP | ADM | VO | MOD | DOC | STA | HOS | PAT | CAR | BLD | FIN | ORG |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| `chat.start` | D | D | D | D | A | A | D | C13b | D | D | D | D |
| `chat.send` | D | D | D | D | C13 | C13 | D | C13 | D | D | D | D |

### 3.18 Notifications (`notifications`)

| Permission | SUP | ADM | VO | MOD | DOC | STA | HOS | PAT | CAR | BLD | FIN | ORG |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| `notifications.view` | A | A | A | A | A | A | A | A | A | A | A | A |
| `notifications.manage_prefs` | A | A | A | A | A | A | A | A | A | A | A | A |
| `notifications.broadcast` | A | A | D | D | D | D | D | D | D | D | D | D |

### 3.19 Analytics (`analytics`)

| Permission | SUP | ADM | VO | MOD | DOC | STA | HOS | PAT | CAR | BLD | FIN | ORG |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| `analytics.view` | A | A | C6 | D | D | D | D | D | D | D | D | D |
| `analytics.health_trends` | C4 | C4 | D | D | C2/3 | D | D | A | C2/3 | D | D | D |
| `analytics.export` | A | C4 | D | D | D | D | D | D | D | D | D | D |

### 3.20 Audit (`audit_logs`)

| Permission | SUP | ADM | VO | MOD | DOC | STA | HOS | PAT | CAR | BLD | FIN | ORG |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| `audit_logs.view` | A | A | C6 | D | D | D | D | D | D | D | D | D |
| `audit_logs.export` | A | C4 | D | D | D | D | D | D | D | D | D | D |

### 3.21 AI assistant (`ai`)

| Permission | SUP | ADM | VO | MOD | DOC | STA | HOS | PAT | CAR | BLD | FIN | ORG |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| `ai.use` | A | A | A | A | A | A | A | A | A | A | A | A |

> All roles may use the AI assistant; it operates under the safety layer
> (non-diagnostic, BR-010/011, FR-AI-006) and never bypasses medical-record
> access controls (special-systems §3.9.5).

---

## 4. Summary by role (privilege profile)

| Role | Medical access | Admin/ops | Verification | Money | δ-sensitive |
|---|---|---|---|---|---|
| SUPER_ADMIN | C4 only | Full | Full | Full | role/permission admin; override authority |
| ADMIN | C4 only | Full (ops) | Full | Refund/view | cannot assign privileged roles |
| VERIFICATION_OFFICER | none | verification scope | Full | none | approve/reject decisions |
| MODERATOR | none | community only | none | none | content removal |
| DOCTOR | C (consent) | none | self | donate only | record access/download |
| HEALTHCARE_STAFF | C (facility+consent) | workflow | none | donate only | clinical entries |
| HOSPITAL | C (facility+consent) | facility | facility | donate only | patient-data touches |
| PATIENT | own + grants | own | none | donate | consent management |
| CAREGIVER | C (patient-granted) | none | none | donate | shared-data reads |
| BLOOD_DONOR | none | donor self | donor | donate | match responses |
| FINANCIAL_DONOR | none | donor self | none | donate/view own | payment history |
| ORGANIZATION | none | campaign self | campaign | donate/view own org | public fundraising |

---

## 5. Traceability (matrix → requirements)

- Condition notes C2/C3/C4/C10/C11/C15 → BR-002, BR-003, BR-004, BR-007,
  FR-MEDREC-002..006, NFR-SEC-003/004, security-architecture §3.8.3/7.
- `blood_requests.verify` / `campaigns.verify` → BR-005, BR-007, FR-BLD-005..008,
  FR-CAM-001/002.
- `medical_records.download` / `medical_records.delete` → FR-MEDREC-005/006.
- `users.role_assign` (C17) → privilege-escalation protection (design §21).
- `emergency_requests.override_access` (C10) → FR-EMG-001..006, BR-009.
- `payments.*` rows → FR-PAY-001..005, BR-008.
- `community.moderate` → FR-COM-004/005.