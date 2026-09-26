# 3.2 Application & Module Architecture

## 3.2.1 Application Architecture (Layered)

Tugawanye system katika layers:

```
┌──────────────────────────────┐
│ Presentation Layer           │  Flutter / Admin Web
├──────────────────────────────┤
│ API Layer                    │  REST API (endpoints, serializers)
├──────────────────────────────┤
│ Application Layer            │  Use Cases / Services
├──────────────────────────────┤
│ Domain Layer                 │  Business Rules
├──────────────────────────────┤
│ Data Access Layer            │  Repositories / ORM
├──────────────────────────────┤
│ Infrastructure               │  PostgreSQL / Redis / Storage
└──────────────────────────────┘
```

**Kwanini:**
- Tukibadilisha technology moja (e.g. DB, notification provider, payment provider) hatuharibu skip nyingine zima.
- Business rules (domain) zinatengwa na presentation.
- Kila layer inaweza kutestwa kwa kujitegemea.

## 3.2.2 Module Architecture (moyo wa system)

```
Sickler's Warriors
│
├── Identity & Access          (register, login, tokens, roles, password reset)
├── Patient Management         (profiles, medical profile, emergency contacts)
├── Caregiver Management       (links, permissions)
├── Doctor Management          (verification, specialties)
├── Medical Records            (records, access control, consent-scoped)
├── Medication Management      (schedules, reminders, adherence)
├── Appointment Management     (clinic visits, reminders, history)
├── Pain & Symptom Tracking    (records, trends, health timeline events)
├── Health Timeline            (aggregated patient history timeline)
├── Blood Donation Network     (donors, requests, matching, fulfillment)
├── Emergency Response         (SOS, severity, responders, tracking, audit)
├── Financial Donations        (campaigns, donations)
├── Payment Management         (provider interface, transactions, receipts)
├── Community                  (posts, comments, reports, moderation)
├── Doctor Communication       (chat / secure messaging)
├── Health Education           (categories, content, review)
├── Notifications              (push, in-app, preferences)
├── Consent & Privacy          (grants, scopes, expiration, revocation)
├── Analytics                  (reports, usage, metrics)
├── AI / Intelligence          (assistant, risk engine, safety layer)
├── Administration             (users, verification, config, moderation)
└── Audit & Security           (audit logs, monitoring)
```

## 3.2.3 Backend module mapping (Django apps)

Feature modules kwenye backend zita-hesabiwa na Django apps (miaka ya awali):

| Design module | Django app |
|---|---|
| Identity & Access | `accounts` (extended) |
| Patient Management | `patients` |
| Caregiver Management | `patients` (caregiver links) |
| Doctor Management | `doctors` |
| Medical Records | `medical_records` |
| Medication Management | `medications` |
| Appointment Management | `appointments` |
| Pain & Symptom Tracking | `patients` (symptoms) / `medical_records` |
| Health Timeline | `medical_records` / `analytics` (aggregation) |
| Blood Donation Network | `blood_network` |
| Emergency Response | `emergencies` |
| Financial Donations | `donations` |
| Payment Management | `donations` (payment service) |
| Community | `community` |
| Doctor Communication | `doctors` (chat) |
| Health Education | `medical_records` / `community` (education content) |
| Notifications | `notifications` |
| Consent & Privacy | `medical_records` (consent) / shared service |
| Analytics | `analytics` |
| AI / Intelligence | `ai_assistant` |
| Administration | `accounts` admin / `config` |
| Audit & Security | `audit` |

## 3.2.4 Mobile module mapping (Flutter)

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

Navigation: `Home → Health / Blood / Community / Profile`; Emergency accessible haraka bila accidental trigger.

## Traceability (snippet)

- FR-AUTH → Identity & Access → `accounts` → `features/auth` (mobile)
- FR-MED → Medication Management → `medications` → `features/medication`
- FR-BLD → Blood Donation Network → `blood_network` → `features/blood`
- FR-EMG → Emergency Response → `emergencies` → `features/emergency`