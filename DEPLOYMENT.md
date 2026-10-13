# Deployment Notes (Render - Free Tier)

## Services
- API Web Service: sicklers-api -> https://sicklers-api.onrender.com
- Admin Static Site (Render Static Site): apps/admin-web build from dist, SPA rewrite `/*` -> `/index.html`
- Optional Public Web (Flutter web) as Static Site

## Required Env Vars (API service, DJANGO_ENV=staging)
- DJANGO_SECRET_KEY: (set real value)
- PAYMENT_ENV: sandbox
- PAYMENT_SECRET_KEY: (or provider-specific secrets)
- ALLOWED_HOSTS: sicklers-api.onrender.com,localhost,127.0.0.1 (comma-separated)
- CORS_ALLOWED_ORIGINS: https://<admin-static>.onrender.com,https://<public-web>.onrender.com (comma-separated, no trailing slash)
- CSRF_TRUSTED_ORIGINS: same as CORS (https://)
- SERVE_MEDIA: false
- DB_* from Render Postgres

## Build/Start (Render)
- Build: bash build.sh
- Start: cd backend && gunicorn config.wsgi:application --bind 0.0.0.0:$PORT

## Admin access
Create first superuser with role:
```bash
cd backend && DJANGO_SETTINGS_MODULE=config.settings.staging venv/bin/python manage.py create_superuser_with_role admin@example.com <password> --first-name Admin --last-name User
```
(Or via Render shell against the deployed DB; ask for secrets separately.)

## Flutter Mobile
app_config defaults to live API in release builds. For release APK:
```bash
cd apps/mobile
flutter build apk --release
```
Output: build/app/outputs/flutter-apk/app-release.apk

## Notes
- Free tier sleeps after inactivity (first request ~30-60s).
- DB expires after 30 days on free tier.
- Static/media ephemeral; for production uploads use object storage.
