# Sickler's Warriors — System Architecture

## Overview

Sickler's Warriors is a full-stack platform supporting the sickle cell
warrior community across life-saving and community functions:

- **Mobile App** (Flutter) — Android + iOS
- **Admin Web Panel** — user / content / donation management
- **Backend** (Django REST) — domain modules under `backend/`
- **Database** — to be defined (PostgreSQL target)

## Backend Modules (Django apps)

| App | Purpose |
|-----|---------|
| `accounts` | Authentication, profiles, roles |
| `patients` | Patient records & medical profile |
| `medical_records` | Digital health records |
| `medications` | Medication tracking & reminders |
| `appointments` | Clinic calendar / visits |
| `doctors` | Verified doctor network & chat |
| `blood_network` | Blood donation requests & donors |
| `donations` | Financial donations |
| `emergencies` | Emergency support / SOS |
| `facilities` | Clinics & health facilities |
| `community` | Community posts & support groups |
| `notifications` | Push/in-app notifications |
| `ai_assistant` | AI / intelligence layer |
| `analytics` | Platform analytics |
| `audit` | Security / audit trail |

## Mobile App Architecture (`apps/mobile`)

Feature-first modular structure:

```
lib/
├── core/       # constants, theme, router, network, utils
├── features/   # one folder per vertical
├── shared/     # reusable widgets
└── app.dart    # root widget + route table
```

Each feature follows presentation/domain separation so it can grow
independently (pages → state → data → API).

## Future Work

- Wire mobile → backend REST API
- Real-time emergency/chat (WebSockets)
- Push notifications (FCM)
- AI symptom guidance layer
- Payment integration for donations
- Admin panel (web)