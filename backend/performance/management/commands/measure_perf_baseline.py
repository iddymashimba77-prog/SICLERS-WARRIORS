"""Repeatable performance baseline probe (Stage 4.18 — NFR-PERF-001..004).

Runs a representative endpoint matrix and reports wall-clock + DB-query counts
so the numbers quoted in the 4.18 reports are reproducible on demand.

SAFETY-GUARDED: this command only runs against an in-memory SQLite profile
(``config.settings.ephemeral_test``). It refuses to touch the Postgres-backed
default settings, and it migrates + seeds its own throwaway database, so it
can never disturb the real ``sickle_cell`` database.

Usage::

    venv/bin/python manage.py measure_perf_baseline \\
        --settings=config.settings.ephemeral_test
"""

import time
import uuid as _uuid
from datetime import timedelta

from django.conf import settings
from django.core.management import call_command
from django.core.management.base import BaseCommand, CommandError
from django.db import connection
from django.test.utils import CaptureQueriesContext
from django.utils import timezone
from rest_framework.test import APIClient
from rest_framework_simplejwt.tokens import RefreshToken

_PASSWORD = "Str0ng!Pass9"


class Command(BaseCommand):
    help = "Measure endpoint query counts + wall-clock under ephemeral SQLite."

    def handle(self, *args, **options):
        engine = settings.DATABASES["default"]["ENGINE"]
        if "sqlite" not in engine:
            raise CommandError(
                "measure_perf_baseline ONLY runs against an in-memory SQLite "
                "profile (config.settings.ephemeral_test). "
                f"Refusing to run on '{engine}'."
            )
        call_command("migrate", run_syncdb=True, verbosity=0)

        from accounts.models import Role, User, UserRole

        def _user(role_code):
            u = User.objects.create_user(
                email=f"{role_code.lower()}-{_uuid.uuid4().hex[:10]}@example.com",
                password=_PASSWORD,
                first_name="Baseline",
                last_name=role_code.title(),
            )
            UserRole.objects.create(user=u, role=Role.objects.get(code=role_code))
            return u

        super_user = _user("SUPER_ADMIN")
        patient = _user("PATIENT")
        doctor = _user("DOCTOR")

        # Minimal, non-sensitive seed data so the probes measure real work.
        from education.models import EducationCategory, EducationalContent

        EducationalContent.objects.create(
            title="Baseline article",
            body="<p>education body</p>",
            category=EducationCategory.objects.get(code="NUTRITION"),
            author=doctor,
            status="PUBLISHED",
            published_at=timezone.now(),
        )
        from medications.models import HealthTimelineEntry, Medication, MedicationEvent, MedicationSchedule

        med = Medication.objects.create(
            patient=patient, name="Hydroxyurea", frequency="daily",
            start_date=timezone.localdate() - timedelta(days=10),
            is_active=True,
        )
        sched = MedicationSchedule.objects.create(
            medication=med, time_of_day="08:00",
            days_of_week=["MON", "TUE", "WED", "THU", "FRI", "SAT", "SUN"],
        )
        MedicationEvent.objects.create(
            schedule=sched, patient=patient, status="TAKEN", taken_at=timezone.now(),
        )
        HealthTimelineEntry.objects.create(
            patient=patient, event_type="MED_STARTED", event_id=_uuid.uuid4(),
            occurred_at=timezone.now(), summary="started",
        )
        from notifications.models import Notification

        Notification.objects.create(
            recipient=patient, type="SYSTEM", title="Hola", body="In-app",
            channel="IN_APP", status="PENDING",
        )

        def _client(user):
            c = APIClient()
            c.credentials(HTTP_AUTHORIZATION=f"Bearer {RefreshToken.for_user(user).access_token}")
            return c

        probes = [
            ("health.ready", APIClient(), "get", "/api/v1/health/ready/", {}),
            ("edu.categories", APIClient(), "get", "/api/education/categories/", {}),
            ("edu.content", APIClient(), "get", "/api/education/content/", {}),
            ("community.feed", _client(patient), "get", "/api/community/posts/", {}),
            ("notifications.inbox", _client(patient), "get", "/api/notifications/", {}),
            ("dashboard.patient", _client(patient), "get", "/api/patients/me/dashboard/", {}),
            ("blood.donors", _client(super_user), "get", "/api/blood/donors/", {}),
            ("admin.dashboard", _client(super_user), "get", "/api/admin/dashboard/", {}),
            (
                "admin.analytics",
                _client(super_user), "get", "/api/admin/analytics/",
                {"data": {"metric": "users.active_patients", "granularity": "DAILY"}},
            ),
            ("admin.ai.monitoring", _client(super_user), "get", "/api/admin/ai/monitoring/", {}),
        ]

        rows = []
        for name, client, method, path, opts in probes:
            kwargs = dict(opts or {})
            with CaptureQueriesContext(connection) as ctx:
                start = time.perf_counter()
                resp = getattr(client, method)(path, **kwargs)
                elapsed_ms = (time.perf_counter() - start) * 1000.0
            rows.append((name, path, resp.status_code, len(ctx), round(elapsed_ms, 1)))

        self.stdout.write("PERF BASELINE (ephemeral SQLite, single warm-free process)")
        self.stdout.write(f"{'probe':<22}{'path':<44}{'status':>7}{'queries':>9}{'ms':>9}")
        for name, path, status, queries, ms in rows:
            self.stdout.write(
                f"{name:<22}{path:<44}{status:>7}{queries:>9}{ms:>9}"
            )
        total_queries = sum(r[3] for r in rows)
        total_ms = sum(r[4] for r in rows)
        self.stdout.write("---")
        self.stdout.write(
            f"TOTAL queries={total_queries} time_ms={round(total_ms, 1)} "
            f"probes={len(rows)}"
        )
        failed = [r[0] for r in rows if r[2] >= 400]
        if failed:
            self.stderr.write(f"WARNING: probes returned >=400: {', '.join(failed)}")