# Role test results — SWQA-TZ-2026

- Generated: 2026-10-13T06:24:56
- Login endpoint: `POST /api/auth/login/` (`email_or_phone`, `password`)
- Result: **275/275 accounts authenticated**

| Role | Accounts | Logged in |
| --- | --- | --- |
| `PATIENT` | 25 | 25 |
| `CAREGIVER` | 25 | 25 |
| `BLOOD_DONOR` | 25 | 25 |
| `DOCTOR` | 25 | 25 |
| `PSYCHOLOGIST` | 25 | 25 |
| `SOCIAL_SUPPORT` | 25 | 25 |
| `HOSPITAL` | 25 | 25 |
| `CLINIC` | 25 | 25 |
| `ORGANIZATION` | 25 | 25 |
| `FINANCIAL_DONOR` | 25 | 25 |
| `HEALTHCARE_STAFF` | 25 | 25 |

Failures: 0

## Workflow outcomes (persisted via the real admin APIs)

| Resource | State | Count |
| --- | --- | --- |
| Doctors | APPROVED | 65 |
| Doctors | REJECTED | 12 |
| Doctors | PENDING | 0 |
| Doctors | SUSPENDED | 0 |
| Facilities | verified | 57 |
| Facilities | unverified | 10 |
| Blood requests | PENDING_VERIFICATION | 0 |
| Blood requests | ACTIVE | 14 |
| Blood requests | REJECTED | 3 |
| Blood requests | MATCHED | 1 |
| Blood requests | FULFILLED | 1 |
| Campaigns | PENDING_VERIFICATION | 0 |
| Campaigns | ACTIVE | 35 |
| Campaigns | REJECTED | 16 |
| Campaigns | CLOSED | 16 |
| Education content | PUBLISHED | 12 |
