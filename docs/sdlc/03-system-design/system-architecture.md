# 3.1 System Architecture

## Decision

Modular client-server architecture kwa Sickler's Warriors. Backend ni REST API (Django), databases ni PostgreSQL, na supporting infrastructure ni Redis, background workers, Firebase cloud messaging, secure file storage na payment provider interfaces.

```
                    SICKLER'S WARRIORS
                             │
        ┌────────────────────┴────────────────────┐
        │                                         │
        ▼                                         ▼
 Flutter Mobile App                        Admin Web App
  Android / iOS                             Desktop/Web
        │                                         │
        └────────────────────┬────────────────────┘
                             │
                             ▼
                      API / Backend
                             │
         ┌───────────────────┼───────────────────┐
         │                   │                   │
         ▼                   ▼                   ▼
    Application          Background          External
      Services             Jobs                Services
         │                   │                   │
         ▼                   ▼                   ▼
    PostgreSQL            Redis          Firebase / Payments
         │
         ▼
  Secure File Storage
```

## Kanuni ya msingi: NO direct DB from client

- Flutter app **hazungumzi moja kwa moja** na database.
- Data yote inapita kupitia API.

```
Flutter
   ↓
API
   ↓
Business Logic
   ↓
Database
```

**Kwa nini hiyo ni muhimu:**
- Inalinda database (access control centralized kwenye backend).
- Android, iOS na Admin Web zote hutumia backend moja (single source of truth).
- Testing na versioning ya API inawezekana.
- Security (auth/consent/permission) inafanyika kwenye moja ya maeneo backend na si kwenye clients.

## Components

### 1. Flutter Mobile App
- Android + iOS, feature-first modular architecture.
- Client-only logic: UI, local cache/state, navigation; **hakuna business-rule enforcing kwa data sensitive kwenye client**.

### 2. Admin Web App
- Desktop/web panel kwa admin: users, verification, moderation, reports, payments, system config.
- Hutumia API ile ile.

### 3. API / Backend (Django REST)
- Layer ya presentation ya backend: handles HTTP, auth, serialization, validation → services → data.

### 4. Background Jobs
- Asynchronous operations: email/push notifications, matching engine, reminders, report generation, payment hooks.
- Communication na main app kupitia queue (Redis/message broker).

### 5. PostgreSQL
- Primary relational database (users, records, donations, blood, audit, nk).

### 6. Redis
- Caching, rate limiting, notification queuing, temporary state (e.g. OTPs, lockouts).
- Inatumiwa na workers.

### 7. External Services
- **Firebase (FCM)** — push notifications.
- **Payment providers (M-Pesa, Airtel Money, Tigo Pesa, ClickPesa, Selcom)** — kupitia provider interface.
- **Secure file storage** — medical documents/uploads, encrypted/access-controlled.
- **AI provider/abstraction** — AI-assisted features kwa safety layer.

## Environments

```
Development:
 Developer Machine → Git → Development Environment

Staging:
 Mobile → Staging API → Staging DB  (+ Redis, workers)

Production:
 Users → HTTPS → Reverse Proxy → API
                                    ├── PostgreSQL
                                    ├── Redis
                                    ├── Worker
                                    ├── Secure Storage
                                    ├── Firebase
                                    └── Payment Providers
```

## Rationale (why this architecture)

- Hatutaki `Flutter → Database` — badala yake backend ndio guard.
- Modular client-server huruhusu mobile, admin web na testing kwenye backend moja.
- Architecture inaweza kukua: scalable kwa NFR-SCAL-001 bila fundamental redesign.

## Future extensibility

- Real-time (WebSockets) kwa chat/emergency bila kubadilisha core.
- Web izaidi (mobile naïve) bila kubadilisha backend.
- Multi-region / CDN kwa static content bila kubadilisha core business APIs.