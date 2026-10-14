# QA Credentials (Secure Reference)

## Local/Synthetic QA Accounts
- Admin: admin@sw.local (SUPER_ADMIN) - password documented in existing reports; use create_superuser_with_role on Render to set
- Full dataset: backend/qa/reports/role_test_accounts.md contains all 275 accounts (11 roles × 25)
- Shared QA password: SwQa!2026-Tz (never commit to code; stored in existing untracked credential files if present)

## Important
- Render uses separate DB from local - superuser must be created in Render DB via Render Shell.
- Admin web on Render needs VITE_API_BASE=https://sicklers-api.onrender.com/api (not VITE_API_BASE_URL).
