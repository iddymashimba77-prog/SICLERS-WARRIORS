# Sickler's Warriors

A health-tech platform for the sickle cell warrior community — medical
management, medication reminders, blood donation, doctor network, community
support and emergency response.

## Repo Layout

```
sicklers-warriors/
├── apps/
│   ├── mobile/          # Flutter app (Android + iOS)
│   └── admin-web/       # Admin panel (web)
├── backend/             # Django REST API (domain modules)
├── database/            # Migrations & schema design
├── docs/                # Architecture & requirements
├── infrastructure/      # Deployment / CI-CD
├── scripts/             # Dev/setup helpers
└── storage/             # Shared artifacts
```

## Quick Start (Mobile)

```bash
cd apps/mobile
flutter pub get
flutter run
```

## Status

See `docs/` for requirements and architecture. See `backend/` for the Django
domain modules (accounts, patients, medical_records, medications, doctors,
blood_network, emergencies, donations, community, ai_assistant, ...).