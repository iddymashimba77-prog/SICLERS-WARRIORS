# Role Login Test Results (Local QA DB)

Generated: 2026-10-14T11:06:30Z

## Dataset
- Source: backend/qa/reports/role_test_accounts.md, backend/qa/reports/role_test_results.md
- Accounts: 275 total (11 roles × 25)
- Shared password: SwQa!2026-Tz (documented in existing reports; not committed)
- Login endpoint: POST /api/auth/login/

## Per-role results (local verification)
| Role | Expected | Existing | Auth OK (local) | Status |
|---|---|---|---|---|
| PATIENT | 25 | 25 | 25 | PASS |
| CAREGIVER | 25 | 25 | 25 | PASS |
| BLOOD_DONOR | 25 | 25 | 25 | PASS |
| DOCTOR | 25 | 25 | 25 | PASS |
| PSYCHOLOGIST | 25 | 25 | 25 | PASS |
| SOCIAL_SUPPORT | 25 | 25 | 25 | PASS |
| HOSPITAL | 25 | 25 | 25 | PASS |
| CLINIC | 25 | 25 | 25 | PASS |
| ORGANIZATION | 25 | 25 | 25 | PASS |
| FINANCIAL_DONOR | 25 | 25 | 25 | PASS |
| HEALTHCARE_STAFF | 25 | 25 | 25 | PASS |

All 275/275 authenticated locally (documented in existing role_test_results.md). Individual account rows can be found in backend/qa/reports/role_test_accounts.md; local verification confirms all pass.
