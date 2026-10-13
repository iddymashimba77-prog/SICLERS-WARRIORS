# Role test accounts — SWQA-TZ-2026

Synthetic, self-contained accounts created only in the local development database for QA. Emails follow `swqa-tz-2026-<role>-<NN>@qa-demo.example.com`.

**Shared password for every seeded account:** `SwQa!2026-Tz`
(override with `--password` or `QA_SEED_PASSWORD`; documented here only — never commit it to application config).

| Group | Role code | Sign-in | Self-registerable | Accounts |
| --- | --- | --- | --- | --- |
| Patients | `PATIENT` | `/api/auth/login/` | yes | 25 |
| Caregivers | `CAREGIVER` | `/api/auth/login/` | yes | 25 |
| Blood donors | `BLOOD_DONOR` | `/api/auth/login/` | yes | 25 |
| Doctors | `DOCTOR` | `/api/auth/login/` | yes | 25 |
| Psychologists | `PSYCHOLOGIST` | `/api/auth/login/` | yes | 25 |
| Social support | `SOCIAL_SUPPORT` | `/api/auth/login/` | yes | 25 |
| Hospitals | `HOSPITAL` | `/api/auth/login/` | yes | 25 |
| Clinics | `CLINIC` | `/api/auth/login/` | yes | 25 |
| Organizations | `ORGANIZATION` | `/api/auth/login/` | yes | 25 |
| Financial donors | `FINANCIAL_DONOR` | `/api/auth/login/` | admin-granted | 25 |
| Healthcare staff | `HEALTHCARE_STAFF` | `/api/auth/login/` | admin-granted | 25 |

The 9 self-registerable roles use the normal sign-up path; `FINANCIAL_DONOR` and `HEALTHCARE_STAFF` are created as standalone accounts because they are granted by an admin but can still sign in (this is the documented 11-role counting decision: 11 × 25 = 275 accounts).
