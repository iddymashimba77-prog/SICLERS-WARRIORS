# 3.4 ERD — Index

> Mermaid ER diagrams split per domain. Source of truth for columns remains
> `../database-design.md`.

| File | Scope |
|---|---|
| [`overall-erd.md`](overall-erd.md) | High-level overview (all domains) |
| [`identity-access-erd.md`](identity-access-erd.md) | Identity, roles, permissions, verification, tokens, security |
| [`patient-medical-erd.md`](patient-medical-erd.md) | Patient, caregivers, records, medications, symptoms, consents, appointments |
| [`blood-emergency-erd.md`](blood-emergency-erd.md) | Donors, requests, matches, donation events, emergencies, override grants |
| [`donations-payments-erd.md`](donations-payments-erd.md) | Campaigns, donations, payment transactions, refunds, organizations |
| [`community-communication-erd.md`](community-communication-erd.md) | Posts/comments/reactions/reports, chat, education |
| [`notifications-audit-erd.md`](notifications-audit-erd.md) | Notifications, preferences, audit logs, analytics snapshots |

Rendering: Mermaid renderer (GitHub / VS Code / mkdocs).