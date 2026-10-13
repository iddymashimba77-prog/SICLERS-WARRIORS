# Tanzania test dataset — SWQA-TZ-2026

## Shape
- Seeded by `python manage.py seed_tanzania_qa` (idempotent, single transaction).
- Every synthetic identity is tagged `SWQA-TZ-2026`; facility/org names carry a `(QA)` suffix and registration numbers are prefixed with the tag.
- Deterministic UUIDs (`uuid5`) and emails/phones make re-runs update in place rather than duplicate.
- Tanzanian names, regions/cities, TZS amounts; synthetic organisations only.

## Row counts (persisted)
| Entity | Count |
| --- | --- |
| Users (all tagged) | 275 |
| Facilities | 55 |
| Doctor/professional profiles | 77 |
| Patient profiles | 26 |
| Appointments | 61 |
| Clinical encounters | 37 |
| Medical records | 76 |
| Medications | 40 |
| Blood requests | 25 |
| Blood matches | 42 |
| Blood donations | 48 |
| Community posts | 50 |
| Comments | 83 |
| Reactions | 150 |
| Community reports | 14 |
| News articles | 9 |
| Ticker announcements | 5 |
| Education content | 16 |
| Campaigns | 100 |
| Donations (financial) | 512 |
| Payment transactions | 512 |
| Refunds | 34 |
| Emergency requests | 25 |
| Emergency responders | 50 |
| Emergency access grants | 6 |
| Notifications | 5333 |
| Notification preferences | 600 |
| Push devices | 20 |

## Safety
- No real SMS/email/payments are sent: notifications are rows, payment transactions carry synthetic redacted payloads.
- No destructive operation: a single `transaction.atomic()` writes and rolls back the whole run on failure; nothing truncates or deletes user data.
