# Auth/Network Baseline Report

Generated: 2026-10-14T11:06:00Z

## Repository
- Root: /home/golden-eagle/sicklers-warriors
- Branch: main
- Git status: modified files (apps/mobile/analysis_options.yaml, apps/mobile/pubspec.lock) - local changes preserved
- Recent commits: e17879a Add Flutter web build for public site; d4a948e Add deployment notes; f4ea979 Default mobile API to live URL in release builds

## Components discovered
- Backend: Django (backend/)
- Mobile: Flutter (apps/mobile/)
- Admin: React + Vite + TypeScript (apps/admin-web/)
- Mobile API config: apps/mobile/lib/core/constants/app_config.dart (VITE_API_BASE_URL->live API mapping in release)
- Admin API client: apps/admin-web/src/lib/api/client.ts (uses VITE_API_BASE env var, not VITE_API_BASE_URL)

## Database
- Local dev uses PostgreSQL (sickle_cell) based on .env patterns in repo; Render staging uses managed Postgres
- Environment: currently local development environment analysis. Production Render DB is separate.
- QA dataset exists in backend/qa/reports/ with 275 users (11 roles × 25) seeded previously, all 275 authenticated in local QA runs.

## Backend endpoints
- Health: /api/v1/health/, /api/v1/health/ready/ → 200
- Root: / → 200 (landing JSON)
- Auth: /api/auth/login/, /api/auth/register/, /api/auth/refresh/, /api/auth/me/
- Admin: /admin/ → 302 to /admin/login/ (200)
- API prefixes: /api/, /api/v1/

## Current test status
- Backend: 876 tests passed (ephemeral_test) - OK
- Admin: tsc --noEmit passes (0 errors)
- Flutter: flutter analyze passes (0 issues)
- Flutter tests: 314 tests passed

## Known issues from prior work
- Admin web on Render needs correct env var (VITE_API_BASE = https://sicklers-api.onrender.com/api). Earlier confusion with VITE_API_BASE_URL was resolved by inspecting code.
- Render DB is separate from local DB; superuser must be created via Render Shell.
