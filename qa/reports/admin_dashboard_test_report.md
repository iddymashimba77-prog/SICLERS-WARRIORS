# Admin Dashboard Test Report

## Admin account (local)
- Identifier: admin@sw.local (existing)
- Role: SUPER_ADMIN (confirmed locally)
- Auth endpoint: POST /api/auth/login/
- Local password verification: OK

## Render environment (live)
- API: https://sicklers-api.onrender.com/ (health 200)
- Admin login page: https://sicklers-api.onrender.com/admin/login/ renders
- Admin static site: https://sicklers-admin.onrender.com/ 
- Known issue: needs VITE_API_BASE env set correctly on Render Static Site; also superuser must exist in Render DB

## Recommended actions (external)
1. Set VITE_API_BASE=https://sicklers-api.onrender.com/api on sicklers-admin (Render Static Site)
2. Run via Render Shell (sicklers-api): cd backend && python manage.py create_superuser_with_role admin@sw.local Admin!2026-Sw --first-name Admin --last-name User
3. Login at https://sicklers-admin.onrender.com/ with admin@sw.local / Admin!2026-Sw

## Local verification
- Backend auth logic intact; admin user exists locally with SUPER_ADMIN role
- Admin web builds/typechecks clean
- No security bypasses introduced
