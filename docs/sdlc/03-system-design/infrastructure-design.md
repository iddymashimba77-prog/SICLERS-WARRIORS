# 3.10 Infrastructure & Deployment Design

## 3.10.1 Environments

```
Development:
 Developer Machine → Git → Development Environment

Staging:
 Mobile → Staging API → Staging DB (+ Redis, workers)

Production:
 Users → HTTPS → Reverse Proxy → API
                                    ├── PostgreSQL
                                    ├── Redis
                                    ├── Worker
                                    ├── Secure Storage
                                    ├── Firebase
                                    └── Payment Providers
```

## 3.10.2 Development Environment

- **Local machine**: Kali Linux (current dev).
- **PostgreSQL**: System instance (port **5432**); application database `sickle_cell`
  created by `scripts/setup_system_pg.sh` (requires sudo for DB/role lifecycle).
  Retained dev cluster on port 5433 (`scripts/postgres.sh`, no sudo) — not used
  by the application, kept for reference.
- **Django backend**: venv + `manage.py runserver` for development.
- **Flutter mobile**: `flutter run` for device/emulator.
- **Git**: version control, `main` branch as default.

## 3.10.3 Staging Environment

- API + DB hosted on staging server (same as production but isolated data).
- Mobile app: staging build (flavor/env config).
- Purpose: testing, UAT, integration testing before production release.

## 3.10.4 Production Environment

```
                    ┌─────────────────┐
                    │   CDN / Cache   │
                    └────────┬────────┘
                             │
                    ┌────────▼────────┐
                    │  Reverse Proxy  │
                    │  (Nginx/Caddy)  │
                    └────────┬────────┘
                             │
                    ┌────────▼────────┐
                    │  API Server     │
                    │  (Django/Gunicorn)│
                    └────────┬────────┘
                             │
        ┌────────────────────┼────────────────────┐
        │                    │                    │
  ┌─────▼─────┐      ┌──────▼──────┐      ┌──────▼──────┐
  │ PostgreSQL │      │    Redis    │      │  Worker     │
  │  (Primary) │      │  (Cache/Queue) │   │  (Celery/RQ)│
  └───────────┘      └─────────────┘      └─────────────┘
```

## 3.10.5 Components

| Component | Purpose | Notes |
|---|---|---|
| Nginx/Caddy | Reverse proxy, SSL termination, static files | HTTPS enforced |
| Django/Gunicorn | API server | WSGI, behind proxy |
| PostgreSQL | Primary database | Single primary (future: read replicas) |
| Redis | Cache, rate limiting, job queue, temp state | For Celery/RQ |
| Worker (Celery/RQ) | Background jobs: notifications, matching, reminders | Async processing |
| Firebase (FCM) | Push notifications | Server-side SDK |
| Payment providers | M-Pesa, Airtel, Tigo, ClickPesa, Selcom | Via provider interface |
| Secure storage | Medical documents, uploads | Encrypted, access-controlled |

## 3.10.6 Deployment Process

```
Code Push (git push)
      ↓
CI/CD Pipeline (GitHub Actions / GitLab CI)
      ↓
  ┌───┼───┐
  ▼   ▼   ▼
Lint  Test  Build
  │   │   │
  └───┼───┘
      ↓
  Deploy to Staging
      ↓
  UAT / Integration Tests
      ↓
  Deploy to Production (manual approval)
```

## 3.10.7 Monitoring & Health

- **Application logs**: structured JSON logs, centralized.
- **Health endpoint**: `/api/v1/health` (DB connection, Redis, worker status).
- **Metrics**: response times, error rates, throughput (Prometheus/Grafana optional).
- **Alerts**: critical errors, high latency, service down.
- **Uptime target**: 99.5% (NFR-AVL-001).

## 3.10.8 Backup & Recovery

- **Database**: daily automated backups, 30-day retention.
- **Backups**: encrypted, stored offsite.
- **Recovery**: documented procedure, tested quarterly.
- **Audit logs**: append-only, never deleted.

## 3.10.9 Security in Production

- No `DEBUG=True` in production.
- `SECRET_KEY` from environment variable.
- CORS restricted to known origins.
- Rate limiting at proxy + application level.
- MFA for admin accounts.
- Regular security patches (Django, dependencies).

## 3.10.10 Traceability

- NFR-AVL-001/002 → High availability, health monitoring
- NFR-PERF-001 → Performance thresholds
- NFR-SCAL-001 → Architecture supports scaling
- NFR-MAIN-001/002 → Modular architecture, separation of concerns