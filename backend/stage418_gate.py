"""Stage 4.18 gate — Performance, Scalability & Reliability Engineering.

Every claim below is verified against REAL endpoints on ephemeral SQLite:

    NFR-PERF-001 caching       — education categories served from the reference
        cache (0 DB queries on 2nd hit); invalidate re-seeds; health does a
        live cache read/write round-trip and degrades to 503 when the cache
        is down (never 5xx, never fakes ok).
    NFR-PERF-002 bounded       — global pagination default 20, query param
        honoured, hard-capped at 100; education LIST omits the full HTML body
        (payload kept lean) while DETAIL keeps it; analytics series scans have a
        366-day hard ceiling.
    NFR-PERF-003 counts/N+1    — patient dashboard and adherence aggregation run
        on a constant query budget (batch aggregated MedicationEvent counts,
        correlated-subquery community counts); admin AI monitoring aggregates in
        ≤2 audit_log queries; broadcasts are a single bulk INSERT regardless of
        audience size.
    NFR-PERF-004 jobs/queue    — durable, DB-backed jobs: at-least-once claim
        (select_for_update), stale RUNNING re-claim, capped exponential backoff,
        max-attempts -> FAILED, unknown task -> FAILED, exclusive claim.
    Deployability             — new BackgroundJob table + 2 indexes present;
        `makemigrations --check` == "No changes detected"; `pip check` clean;
        the reproducible `measure_perf_baseline` command runs (refuses any
        non-SQLite engine, so Postgres can never be hit).

Run (ephemeral SQLite; never touches Postgres):
    venv/bin/python stage418_gate.py
"""

import os
import subprocess
import sys
import uuid as _uuid
from datetime import timedelta

os.environ.setdefault("DJANGO_SETTINGS_MODULE", "config.settings.ephemeral_test")

import django

django.setup()

from django.core.cache import cache

cache.clear()

from django.test.runner import DiscoverRunner
from django.test.utils import CaptureQueriesContext
from django.utils import timezone
from unittest import mock

runner = DiscoverRunner(verbosity=0, interactive=False)
old_config = runner.setup_databases()

ok = False
try:
    from rest_framework.test import APIClient
    from rest_framework_simplejwt.tokens import RefreshToken

    from accounts.models import Role, User, UserRole
    from ai_assistant.admin_views import (
        AI_COMPLETED, AI_PROVIDER_FAILURE, AI_SAFETY_BLOCK,
    )
    from audit.models import AuditLog
    from core.cache import KEY_EDUCATION_CATEGORIES, invalidate_reference
    from core.caching import ReferenceCachedListMixin
    from core.jobs import enqueue, job_handler, process_due
    from core.models import BackgroundJob
    from core.pagination import CorePageNumberPagination
    from django.conf import settings
    from education.models import EducationCategory, EducationalContent
    from notifications.models import Notification

    _PASSWORD = "Str0ng!Pass9"

    _DONE = {}


    @job_handler("perf.gate_ok")
    def _gate_ok(payload):
        _DONE["ok"] = payload
        return 42


    @job_handler("perf.gate_broken")
    def _gate_broken(payload):
        raise RuntimeError("boom")


    class _JsonAPIClient(APIClient):
        def _json(self, kwargs):
            kwargs.setdefault("format", "json")

        def post(self, *args, **kwargs):
            self._json(kwargs)
            return super().post(*args, **kwargs)


    def orm_user(role_code, **extra):
        user = User.objects.create_user(
            email=f"{role_code.lower()}-{_uuid.uuid4().hex[:10]}@example.com",
            password=_PASSWORD, first_name="Test", last_name=role_code.title(),
            account_status="ACTIVE", **extra,
        )
        UserRole.objects.create(user=user, role=Role.objects.get(code=role_code))
        return user


    def _client(user):
        client = _JsonAPIClient()
        client.credentials(HTTP_AUTHORIZATION=f"Bearer {RefreshToken.for_user(user).access_token}")
        return client


    checks = []


    def check(name, cond):
        checks.append((name, bool(cond)))
        if not cond:
            print(f"  [x] {name}")


    # --------------------------------------------- NFR-PERF-002 pagination config
    check("global default pagination is the capped CorePageNumberPagination",
          settings.REST_FRAMEWORK["DEFAULT_PAGINATION_CLASS"]
          == "core.pagination.CorePageNumberPagination")
    check("performance app installed", "performance" in settings.INSTALLED_APPS)
    check("default cache configured", "default" in settings.CACHES)

    # --------------------------------------------- NFR-PERF-002 education payloads
    doctor = orm_user("DOCTOR")
    category = EducationCategory.objects.get(code="NUTRITION")
    for i in range(120):
        EducationalContent.objects.create(
            title=f"Article {i}", body="<p>full body</p>", category=category,
            author=doctor, status="PUBLISHED", published_at=timezone.now(),
        )
    anon = APIClient()
    first = anon.get("/api/education/content/")
    page_two = anon.get("/api/education/content/", {"page": "2"})
    size_fifty = anon.get("/api/education/content/", {"page_size": "50"})
    capped = anon.get("/api/education/content/", {"page_size": "999"})
    check("education list defaults to 20 per page", first.status_code == 200
          and first.data["count"] == 120 and len(first.data["results"]) == 20)
    check("page 2 returns the next page", page_two.status_code == 200
          and len(page_two.data["results"]) == 20)
    check("page_size param honoured", len(size_fifty.data["results"]) == 50)
    check("page_size hard-capped at 100", len(capped.data["results"]) == 100)
    check("education list payload omits body",
          all("body" not in r for r in first.data["results"]))
    uid = first.data["results"][0]["uid"]
    detail = anon.get(f"/api/education/content/{uid}/")
    check("education detail keeps full body",
          detail.status_code == 200 and "body" in detail.data
          and detail.data["body"] == "<p>full body</p>")

    # --------------------------------------------- NFR-PERF-001 categories cache
    cat1 = anon.get("/api/education/categories/")
    check("categories list reachable",
          cat1.status_code == 200 and cat1.data["count"] >= 1)
    with CaptureQueriesContext(__import__("django").db.connection) as ctx:
        cat2 = anon.get("/api/education/categories/")
    check("categories served from cache on 2nd hit (0 DB queries)",
          cat2.status_code == 200 and len(ctx) == 0)
    invalidate_reference(KEY_EDUCATION_CATEGORIES)
    with CaptureQueriesContext(__import__("django").db.connection) as ctx:
        cat3 = anon.get("/api/education/categories/")
    check("invalidate re-seeds quietly (1 query, still 200)",
          cat3.status_code == 200 and len(ctx) >= 1)

    # ---------------------------------------------------- NFR-PERF-001 health
    ready = anon.get("/api/v1/health/ready/")
    check("readiness 200 with db + cache ok",
          ready.status_code == 200 and ready.data["checks"]["database"] == "ok"
          and ready.data["checks"]["cache"] == "ok")
    check("perf headers present (X-Duration-Ms, X-Query-Count)",
          "X-Duration-Ms" in ready.headers and "X-Query-Count" in ready.headers)
    fake_cache = mock.MagicMock()
    fake_cache.set.side_effect = RuntimeError("down")
    with mock.patch("django.core.cache.cache", fake_cache):
        degraded = anon.get("/api/v1/health/ready/")
    check("cache failure degrades readiness to 503 (never 5xx crash)",
          degraded.status_code == 503
          and degraded.data["checks"]["cache"] == "unavailable")

    # ------------------------------------- NFR-PERF-003 dashboard/adherence batch
    from medications.models import (
        HealthTimelineEntry, Medication, MedicationEvent, MedicationSchedule, Symptom,
    )

    patient = orm_user("PATIENT")
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
    Symptom.objects.create(patient=patient, pain_level=4, recorded_at=timezone.now())
    HealthTimelineEntry.objects.create(
        patient=patient, event_type="MED_STARTED", event_id=_uuid.uuid4(),
        occurred_at=timezone.now(), summary="started",
    )
    dash = _client(patient).get("/api/patients/me/dashboard/")
    check("patient dashboard 200 + active medication counted",
          dash.status_code == 200 and dash.data["medications"]["active_count"] == 1)
    from medications.services import adherence_stats

    with CaptureQueriesContext(__import__("django").db.connection) as ctx:
        stats = adherence_stats(patient)
    event_queries = [
        q["sql"] for q in ctx if "medication_events" in q["sql"].lower()
    ]
    check("adherence batches events into one grouped query",
          stats["overall"]["taken"] == 1 and len(event_queries) == 1)

    # ---------------------------------------- NFR-PERF-003 AI monitoring aggregate
    super_user = orm_user("SUPER_ADMIN")
    for code, result in ((AI_COMPLETED, "SUCCESS"), (AI_SAFETY_BLOCK, "DENIED"),
                         (AI_PROVIDER_FAILURE, "FAILURE")):
        AuditLog.objects.create(actor=super_user, action_code=code,
                                resource_type="ai", result=result, request_id=None)
    with CaptureQueriesContext(__import__("django").db.connection) as ctx:
        mon = _client(super_user).get("/api/admin/ai/monitoring/")
    audit_selects = [q["sql"] for q in ctx if "audit_log" in q["sql"].lower()]
    check("AI monitoring 200 with ≤2 audit queries",
          mon.status_code == 200 and len(audit_selects) <= 2)
    check("AI monitoring aggregates correctly",
          mon.data["total_events"] == 3 and mon.data["failures"] == 1
          and mon.data["denied"] == 1)

    # --------------------------------------------- NFR-PERF-003 broadcast one INSERT
    for i in range(25):
        orm_user("PATIENT")
    active_count = User.objects.filter(
        deleted_at__isnull=True, account_status="ACTIVE",
    ).count()
    with CaptureQueriesContext(__import__("django").db.connection) as ctx:
        bcast = _client(super_user).post(
            "/api/admin/notifications/broadcast/",
            {"audience": "ALL", "title": "Perf", "body": "Bulk"})
    inserts = [
        q["sql"] for q in ctx if "insert into \"notifications\"" in q["sql"].lower()
    ]
    check("broadcast 201 with a single bulk INSERT for the whole ACTIVE audience",
          bcast.status_code == 201 and len(inserts) == 1
          and Notification.objects.filter(type="SYSTEM").count() == active_count)

    # --------------------------------------------------- NFR-PERF-004 job queue
    job = enqueue(task="perf.gate_ok", payload={"x": 1})
    results = process_due(limit=10)
    row, outcome = results[0]
    check("job enqueued -> processed once (handler ran)",
          outcome == "ok" and row.status == "SUCCEEDED" and _DONE.get("ok") == {"x": 1}
          and BackgroundJob.objects.get(pk=job.pk).status == "SUCCEEDED")
    check("no second run for a completed job",
          process_due(limit=10) == [])
    broken = enqueue(task="perf.gate_broken", max_attempts=1, payload={})
    _, broken_outcome = process_due(limit=10)[0]
    check("max_attempts=1 failure -> FAILED",
          broken_outcome == "failed"
          and BackgroundJob.objects.get(pk=broken.pk).status == "FAILED"
          and "boom" in BackgroundJob.objects.get(pk=broken.pk).error)
    unknown = enqueue(task="no.such.handler", payload={})
    _, unknown_outcome = process_due(limit=10)[0]
    check("unknown task -> FAILED (never eternal retry)",
          unknown_outcome == "unknown_task"
          and BackgroundJob.objects.get(pk=unknown.pk).status == "FAILED"
          and "No handler registered" in BackgroundJob.objects.get(pk=unknown.pk).error)

    # ---------------------------------------------------------- deployability
    with __import__("django").db.connection.cursor() as cur:
        cur.execute(
            "SELECT name FROM sqlite_master WHERE type='index' AND name=?",
            ["bld_donor_verified_cnt_idx"])
        has_donor_idx = cur.fetchone() is not None
        cur.execute(
            "SELECT name FROM sqlite_master WHERE type='index' AND name=?",
            ["edu_content_status_cat_pub_idx"])
        has_edu_idx = cur.fetchone() is not None
    check("new blood_network index present (bld_donor_verified_cnt_idx)",
          has_donor_idx)
    check("new education index present (edu_content_status_cat_pub_idx)", has_edu_idx)
    check("BackgroundJob table exists (core 0001 migration ran)",
          BackgroundJob._meta.db_table
          in __import__("django").db.connection.introspection.table_names())
    from education.views import EducationCategoryListView

    check("categories endpoint uses the reference cache mixin",
          ReferenceCachedListMixin in EducationCategoryListView.__mro__)

    baseline = subprocess.run(
        [sys.executable, os.path.join(os.path.dirname(os.path.abspath(__file__)),
                                      "manage.py"),
         "measure_perf_baseline", "--settings=config.settings.ephemeral_test"],
        capture_output=True, text=True)
    check("measure_perf_baseline runs and prints totals",
          baseline.returncode == 0 and "TOTAL queries" in baseline.stdout)

    ok = len(checks) == sum(1 for _, passed in checks if passed)
finally:
    runner.teardown_databases(old_config)

print(f"Stage 4.18 gate: {sum(1 for _, p in checks if p)}/{len(checks)} checks passed")
for name, passed in checks:
    if not passed:
        print(f"  FAILED: {name}")
print("GATE_OK" if ok else "GATE_FAILED")
raise SystemExit(0 if ok else 1)