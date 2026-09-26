# 3.6 Mobile App Design

> **SUPERSEDED** — superseded by `mobile-ui-ux-design.md` (full Stage 3.6 design,
> with `mobile-navigation.md`, `mobile-screen-inventory.md`,
> `mobile-component-catalog.md`, `mobile-api-traceability.md`,
> `mobile-ui-ux-review.md`). Kept for history; do not implement from this file.

## Platform
- Flutter, Android + iOS. Single codebase.

## Navigation

```
Home
 ├─ Health
 │   ├─ Medication
 │   ├─ Appointments
 │   ├─ Pain / Symptoms
 │   └─ Health Timeline
 ├─ Blood
 │   ├─ Request
 │   ├─ Donate
 │   └─ My donations/requests
 ├─ Community
 │   ├─ Posts
 │   ├─ Comments/Reactions
 │   └─ Education
 └─ Profile
     ├─ Medical profile
     ├─ Consent
     └─ Settings
Emergency — accessible haraka (floating/visible) bila accidental trigger (long-press/confirm).
```

## Structure (feature-first)

```
lib/
│
├── core/
│   ├── config/
│   ├── network/
│   ├── security/
│   ├── storage/
│   ├── routing/
│   ├── theme/
│   └── utilities/
│
├── features/
│   ├── auth/
│   ├── home/
│   ├── profile/
│   ├── medical/
│   ├── medication/
│   ├── appointments/
│   ├── pain/
│   ├── blood/
│   ├── emergency/
│   ├── doctors/
│   ├── chat/
│   ├── donations/
│   ├── community/
│   ├── education/
│   ├── notifications/
│   └── settings/
│
└── shared/
    ├── widgets/
    ├── models/
    └── services/
```

## Principles (NFR-USE)
- NFR-USE-001: low-friction interactions kwa digital literacy tofauti; simplified forms.
- NFR-USE-002: critical workflows minimal steps.
- NFR-USE-003: emergency UI prioritizes speed + clarity; confirm dialog kwa accidental trigger.

## Client responsibility
- Client = presentation + local cache/state + navigation.
- **Hakuna** business-rule enforcement ya sensitive data kwenye client pekee.
- Secure storage kwa tokens (flutter_secure_storage pattern).

## Traceability
- Feature folders ↔ Django modules (3.2.4) na API endpoints (3.5.3).