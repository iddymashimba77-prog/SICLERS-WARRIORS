# 3.8 Data Classification & Security Matrix

> Stage 3.8 — Security Design. Classifies every data class stored by
> Sickler's Warriors and states who may access it, its encryption, audit and
> retention (extension of 3.4 §25 data protection + 3.3 permissions). Design
> only; rows cross-reference `security-design.md`, `security-risk-register.md`
> and `security-api-traceability.md`.

Levels:
- **Public** — visible to anyone (unauthenticated/public endpoints).
- **Internal** — operational, staff/aggregate only.
- **Sensitive** — requires authentication + authorization (owner/consent/
  role), masked exposure.
- **Highly Sensitive** — strict gates: consent/C4, sealing, strict audit.

`Who can access` = authoritative per 3.3 matrix (roles/conditions C2–C17).
`Encryption` = transit (TLS for all) + at-rest (media) + field-sealing as noted.
`Retention` = hot/archive; legal-hold allowed.

---

## 1. Classification Matrix

| Data | Classification | Who can access | Encryption | Audit | Retention (design) |
| ---- | -------------- | -------------- | ---------- | ----- | ------------------ |
| account data (profile, contact, telemetry) | Sensitive | owner; SUP/ADM (`users.view` C6 masked); VO verify-scope (C6) | TLS + at-rest | login/change/suspend | active + 30 d post-deactivation, then anonymized |
| auth credentials (password_hash, mfa, recovery) | Highly Sensitive | never returned; backend only | TLS + **sealed column** | MFA/pwd changes (§42) | scheme-dependent; rotated |
| `mfa_secret_encrypted` | Highly Sensitive | backend service only; never API | AES-GCM sealed | setup/enable/disable | rotates on re-enroll |
| password reset tokens / OTP codes | Highly Sensitive | owner flow only | at rest (hashed/single-use) | issuance+use | purge after use/expiry |
| refresh tokens / denylist | Highly Sensitive | owner session + backend | at rest | revoke/logout | lifecycle bound to session |
| patient demographic data | Highly Sensitive | owner; clinical (consent C14); SUP/ADM C4 | TLS + at-rest | record view | legal min 7 y |
| medical records (history, notes, meds, symptoms) | Highly Sensitive | owner; consent grantee (BR-004); clinical (C7/C14); SUP/ADM C4 | TLS + at-rest (+file seal) | access_open/modify | legal min 7 y |
| treatment history / clinical encounter | Highly Sensitive | clinical author (C15/16); owner (C15); consent | TLS + at-rest | modify | 7 y |
| doctor credentials & license documents | Highly Sensitive | owner; VO/ADM/SUP (`doctors.verify` C6); reviewer | TLS + sealed media (signed URL) | upload/verify/decision | 7 y + archival |
| doctor profile (published directory) | Internal → Sensitive subset | public subset; full: staff/consented | TLS | profile edits | active |
| blood donor data (group, region, availability) | Sensitive | masked lists; VO verify C6/7; match scope C9 | TLS + at-rest | verify/match | 7 y |
| blood donor contact/exact location | Highly Sensitive | only at consent/match stage; never public (BR-006) | TLS + at-rest | disclose event | 7 y |
| blood requests | Sensitive→Highly Sensitive | requester (owner) + C6/7 VO/ADM/SUP; no donor PII | TLS + at-rest | verify/approve | 7 y |
| emergency requests & case data | Highly Sensitive | owner; C7 hospital; SUP/ADM C4; grant-based | TLS + at-rest | grant/open/resolve (§42) | 7 y |
| caregiver relationships | Sensitive | owner + caregiver (relationship + consent); SUP/ADM C4 | TLS + at-rest | grant/revoke/remove | active + archive |
| caregiver scope consent | Highly Sensitive | owner + grantee + SUP/ADM C4 | TLS + at-rest | grant/revoke | consent history retained |
| consents (record + consent-graph) | Highly Sensitive | owner + grantee + SUP/ADM C4 | TLS + at-rest | grant/revoke/modify | throughout + archive |
| appointments (schedule data) | Sensitive | owner + clinical (C7) + (admin AD-A-6 future) | TLS + at-rest | create/update | 7 y |
| private chat (doctor↔patient) | Highly Sensitive | participants (C13) only; admin never (3.7) | TLS + at-rest; **no E2E v1** (SD-19) | message create/report | 24 mo + archive (legal hold) |
| community posts/comments (public surface) | Public | all users (auth), masked to public; moderation metadata: staff | TLS + at-rest | moderate | active + archive |
| moderation/report data | Sensitive | SUP/ADM/MOD (`community.moderate`) | TLS | moderate | 7 y |
| education content (published) | Public | all users | TLS + at-rest | publish/review | active + archive |
| education drafts | Internal | owner (edu staff); SUP/ADM review | TLS | review/publish | until publish/archive |
| donation campaigns (public overview) | Public | all; verification docs: VO/ADM/SUP | TLS + at-rest | verify/approve | 7 y |
| donation amounts / donor payment info | Sensitive→Highly Sensitive | owner (receipts); SUP/ADM (payments.view masked) | TLS + at-rest | initiate/confirm/refund | 7 y |
| payment transactions / provider refs | Highly Sensitive | SUP/ADM (masked); finance | TLS + at-rest | webhook/refund/reconcile | 7 y (financial) |
| card data | **never stored** | none | N/A (provider tokenized) | N/A | N/A |
| notification templates | Internal | SUP/ADM (`notifications.broadcast`) | TLS | save | active + archive |
| notification delivery log | Sensitive | SUP/ADM | TLS | send/resend | 90 d + purge |
| push tokens (FCM/APNs) | Sensitive | backend service; never exposed | TLS + at-rest | register | lifecycle with device |
| audit logs (audit_logs) | Highly Sensitive | SUP/ADM (C6 VO own); append-only | TLS + at-rest (immutable) | n/a (log itself) | hot 90 d + archive 7 y |
| security events (auth telemetry) | Highly Sensitive | SUP/ADM (auth center) | TLS + at-rest | n/a | 90 d + purge |
| system settings (incl. secrets) | Highly Sensitive | SUP (ADM conditional AD-A-8); values masked | sealed storage | setting_change | config-retained |
| AI assistant data (chat ctx to assistant) | Highly Sensitive | owner (their conversation) + system | TLS + at-rest | assistant.use | 24 mo |
| API keys / webhook secrets (3rd-party) | Highly Sensitive | backend service only; sealed | **sealed storage** | rotation | rotate + purge-old |
| verification queues metadata | Internal | VO/ADM/SUP (verify scope) | TLS | decision | until resolved |

---

## 2. Access Rules by Role (summary)

| Role | Sensitive | Highly Sensitive |
|---|---|---|
| PAT | own data + consented grants | own records + consents given |
| CAR | only granted scope (consent) | same (scope-bound) |
| DOC | consent-gated patients (BR-004) + own | consent-gated records only |
| HOS/STA/BLD/FIN/ORG | per matrix (C7/operational) | per-matrix scoped |
| VO | verification queues (C6) | verify docs only |
| MOD | community reports | none (no medical) |
| ADM | operational (masked) | C4 reason-locked only |
| SUP | full operational | C4 reason-locked (audited) |

---

## 3. Field Masking Rules

- Donor list: phone/address masked → region + blood group only (BR-006).
- Users list (admin): contact masked (3.7 ADM-USR-001).
- Payment payloads: number redacted, token only.
- Notification previews: PHI stripped (G4), placeholders `[…]`.
- Emergency list: case-minimal only.
- MFA seed / API keys: never displayed beyond one-time setup.

---

## 4. Cross-Cut Rules

1. TLS on every transmission; no HTTP for any production data.
2. PHI never stored in `audit_logs.details` or `security_events` bodies.
3. Sensitive/Highly Sensitive files: encrypted media + signed short-TTL URLs.
4. Every Legal minimum applies on erase request (legal hold override path).
5. Data Subject Rights (SD design §43) apply to owner-scoped data only;
   audit refs stay anonymized.

---

END — feeds `security-control-matrix.md`, `security-database-traceability.md`.