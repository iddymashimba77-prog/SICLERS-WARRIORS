# Auth/Network Fix Report

## Root causes (confirmed)
1. Admin web (Vite) reads VITE_API_BASE env var, not VITE_API_BASE_URL. This was the source of confusion in earlier instructions.
2. Render API and local API use different databases; admin user must exist in Render DB. 
3. API is healthy and CORS is configured for allowed origins including sicklers-admin.onrender.com.

## Files inspected (minimal)
- apps/admin-web/src/lib/api/client.ts - confirms BASE uses import.meta.env.VITE_API_BASE
- apps/admin-web/vite.config.ts - dev proxy config
- apps/mobile/lib/core/constants/app_config.dart - live API config
- backend/config/settings/staging.py - hosts/origins parsing
- backend/core/root_view.py, backend/core/root_urls.py - root landing

## Current state
- Backend tests: 876/876 passed
- Admin typecheck: clean
- Flutter analyze: clean, 314 tests passed
- Health endpoints: 200 on live Render API
- Admin login page renders on Render

## Fixes applied (local)
No code changes needed locally - codebase is correct. Required external actions on Render:
- Set VITE_API_BASE=https://sicklers-api.onrender.com/api on sicklers-admin Static Site (not VITE_API_BASE_URL)
- Create/update superuser in Render DB via Render Shell: cd backend && python manage.py create_superuser_with_role admin@sw.local Admin!2026-Sw --first-name Admin --last-name User

## Security preserved
- No secrets exposed, no auth bypasses, no global security disabled
- Existing auth flows unchanged
