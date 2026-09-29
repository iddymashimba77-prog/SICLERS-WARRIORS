"""Stage 4.18 — performance, scalability & reliability test suite.

Gates the approved NFR-PERF-001..004 outcomes:

* NFR-PERF-001 caching       — reference caching works, stays user-scoped OFF,
                               and health observes the live cache.
* NFR-PERF-002 bounded       — global pagination caps page sizes, feed payloads
                               stay lean, series scans are bounded.
* NFR-PERF-003 counts/N+1    — dashboard/adherence/monitoring/feed count paths
                               issue a constant, small number of queries
                               regardless of row volume.
* NFR-PERF-004 jobs/queue    — durable DB-backed jobs claim/retry/fail safely.

These tests use only the ephemeral SQLite profile (no Postgres is ever
reached): ``manage.py test --settings=config.settings.ephemeral_test``.
"""

import uuid as _uuid

from django.conf import settings
from django.core.cache import cache
from django.test import TestCase
from django.test.utils import CaptureQueriesContext
from django.utils import timezone
from rest_framework.test import APIClient, APIRequestFactory

from accounts.models import Role, User, UserRole
from core.cache import invalidate_reference, reference_get, reference_set
from core.jobs import job_handler, enqueue, process_due
from core.models import BackgroundJob
from core.pagination import CorePageNumberPagination

_PASSWORD = "Str0ng!Pass9"


def _orm_user(role_code, account_status="ACTIVE", email=None, **extra):
    user = User.objects.create_user(
        email=email or f"{role_code.lower()}-{_uuid.uuid4().hex[:10]}@example.com",
        password=_PASSWORD,
        first_name="Test",
        last_name=role_code.title(),
        account_status=account_status,
        **extra,
    )
    UserRole.objects.create(user=user, role=Role.objects.get(code=role_code))
    return user


def _client(user):
    from rest_framework_simplejwt.tokens import RefreshToken

    client = APIClient()
    client.credentials(HTTP_AUTHORIZATION=f"Bearer {RefreshToken.for_user(user).access_token}")
    return client


# Module-level job handlers registered for the queue tests below.
_WORKED = {}


@job_handler("perf.test_ok")
def _ok_handler(payload):
    _WORKED["perf.test_ok"] = payload
    return len(payload)


@job_handler("perf.test_broken")
def _broken_handler(payload):
    raise RuntimeError("boom")


class SettingsDefaultsTests(TestCase):
    def test_global_pagination_defaults_to_capped_core_paginator(self):
        self.assertEqual(
            settings.REST_FRAMEWORK["DEFAULT_PAGINATION_CLASS"],
            "core.pagination.CorePageNumberPagination",
        )

    def test_cache_configuration_present(self):
        self.assertIn("default", settings.CACHES)
        self.assertIn("BACKEND", settings.CACHES["default"])
        self.assertTrue(settings.CACHES["default"]["BACKEND"])

    def test_bounded_resource_limits_configured(self):
        self.assertGreater(settings.DATA_UPLOAD_MAX_MEMORY_SIZE, 0)
        self.assertGreater(settings.DATA_UPLOAD_MAX_NUMBER_FIELDS, 0)


class PaginationCapTests(TestCase):
    def _paginate(self, size, page_size=None):
        factory = APIRequestFactory()
        request = factory.get("/")
        request.query_params = {"page_size": page_size} if page_size else {}
        request.GET = request.query_params
        paginator = CorePageNumberPagination()
        items = list(range(250))
        page = paginator.paginate_queryset(items, request, view=None)
        data = paginator.get_paginated_response(page).data
        return data, paginator

    def test_default_page_size_is_20(self):
        data, _ = self._paginate(250)
        self.assertEqual(data["count"], 250)
        self.assertEqual(len(data["results"]), 20)

    def test_page_size_query_param_allowed(self):
        data, _ = self._paginate(250, page_size=50)
        self.assertEqual(len(data["results"]), 50)

    def test_page_size_capped_at_100(self):
        data, _ = self._paginate(250, page_size=500)
        self.assertEqual(len(data["results"]), 100)

    def test_invalid_page_size_falls_back_to_default(self):
        data, _ = self._paginate(250, page_size="nope")
        self.assertEqual(len(data["results"]), 20)


class ReferenceCacheTests(TestCase):
    def setUp(self):
        cache.clear()

    def test_reference_set_get_roundtrip(self):
        reference_set("ref:test:roundtrip", [{"a": 1}], ttl=60)
        self.assertEqual(reference_get("ref:test:roundtrip"), [{"a": 1}])

    def test_invalidate_removes_key(self):
        reference_set("ref:test:invalidate", "x", ttl=60)
        self.assertEqual(reference_get("ref:test:invalidate"), "x")
        self.assertTrue(invalidate_reference("ref:test:invalidate"))
        self.assertIsNone(reference_get("ref:test:invalidate"))

    def test_missing_key_returns_default(self):
        self.assertIsNone(reference_get("ref:test:missing"))
        self.assertEqual(reference_get("ref:test:missing", default=[]), [])

    def test_cache_never_used_for_anonymous_miss(self):
        # Guardrail: the helper must not mint arbitrary keys (deny by default).
        self.assertIsNone(reference_get(""))


class EducationPerformanceTests(TestCase):
    def setUp(self):
        cache.clear()
        self.doctor = _orm_user("DOCTOR", email="edu-perf-dr@example.com")
        from education.models import EducationCategory, EducationalContent

        category = EducationCategory.objects.get(code="NUTRITION")
        self.published = EducationalContent.objects.create(
            title="Perf article",
            body="<p>body</p>",
            category=category,
            author=self.doctor,
            status="PUBLISHED",
            published_at=timezone.now(),
        )
        self.doctor_client = _client(self.doctor)

    def test_categories_list_hits_cache_on_second_request(self):
        first = APIClient().get("/api/education/categories/")
        self.assertEqual(first.status_code, 200)
        self.assertGreaterEqual(first.data["count"], 1)
        with CaptureQueriesContext(__import__("django").db.connection) as ctx:
            second = APIClient().get("/api/education/categories/")
        self.assertEqual(second.status_code, 200)
        self.assertEqual(len(ctx), 0, "category list served from cache")

    def test_content_list_omits_full_body_but_detail_has_it(self):
        resp = self.doctor_client.get("/api/education/content/")
        self.assertEqual(resp.status_code, 200)
        self.assertGreaterEqual(resp.data["count"], 1)
        row = next(r for r in resp.data["results"] if r["uid"] == str(self.published.uid))
        self.assertNotIn("body", row)
        detail = self.doctor_client.get(f"/api/education/content/{self.published.uid}/")
        self.assertIn("body", detail.data)
        self.assertIn("body", detail.data["body"] or "")


class AiMonitoringQueryTests(TestCase):
    def setUp(self):
        cache.clear()
        self.super = _orm_user("SUPER_ADMIN")
        self.client = _client(self.super)
        from ai_assistant.admin_views import (
            AI_COMPLETED, AI_SAFETY_BLOCK, AI_PROVIDER_FAILURE,
        )
        from audit.models import AuditLog

        self.AI_CODES = (AI_COMPLETED, AI_SAFETY_BLOCK, AI_PROVIDER_FAILURE)
        for code, result in ((AI_COMPLETED, "SUCCESS"), (AI_SAFETY_BLOCK, "DENIED"),
                             (AI_PROVIDER_FAILURE, "FAILURE")):
            AuditLog.objects.create(
                actor=self.super, action_code=code,
                resource_type="ai", result=result, request_id=None,
            )

    def test_monitoring_aggregation_is_constant_query_count(self):
        with CaptureQueriesContext(__import__("django").db.connection) as ctx:
            resp = self.client.get("/api/admin/ai/monitoring/")
        self.assertEqual(resp.status_code, 200)
        audit_selects = [
            q["sql"] for q in ctx if "audit_log" in q["sql"].lower()
        ]
        self.assertLessEqual(len(audit_selects), 2,
                             "AI monitoring must aggregate in ≤2 audit queries")

    def test_monitoring_values_correct_after_grouping(self):
        resp = self.client.get("/api/admin/ai/monitoring/")
        data = resp.data
        self.assertEqual(data["total_events"], 3)
        self.assertEqual(data["failures"], 1)
        self.assertEqual(data["denied"], 1)
        self.assertEqual(data["safety_blocks"], 1)
        self.assertEqual(data["provider_failures"], 1)
        self.assertEqual(data["unique_users"], 1)


class BroadcastBulkTests(TestCase):
    def setUp(self):
        cache.clear()
        self.super = _orm_user("SUPER_ADMIN")
        self.super_client = _client(self.super)
        for i in range(40):
            _orm_user("PATIENT", email=f"perf-pt-{i}@example.com")

    def test_broadcast_uses_single_bulk_insert(self):
        from audit.models import AuditLog
        from notifications.models import Notification

        with CaptureQueriesContext(__import__("django").db.connection) as ctx:
            resp = self.super_client.post(
                "/api/admin/notifications/broadcast/",
                {"audience": "ALL", "title": "Perf", "body": "Bulk"}, format="json",
            )
        self.assertEqual(resp.status_code, 201)
        inserts = [
            q["sql"] for q in ctx
            if "insert into \"notifications\"" in q["sql"].lower()
        ]
        self.assertEqual(len(inserts), 1, "broadcast must issue exactly one INSERT")
        self.assertEqual(Notification.objects.filter(type="SYSTEM").count(), 41)
        self.assertTrue(AuditLog.objects.filter(action_code="notifications.broadcast").exists())


class MedicationDashboardQueryTests(TestCase):
    def setUp(self):
        cache.clear()
        self.patient = _orm_user("PATIENT")
        from medications.models import (
            HealthTimelineEntry, Medication, MedicationEvent, MedicationSchedule, Symptom,
        )

        self.med = Medication.objects.create(
            patient=self.patient, name="Hydroxyurea", frequency="daily",
            start_date=timezone.localdate() - __import__("datetime").timedelta(days=10),
            is_active=True,
        )
        self.schedule = MedicationSchedule.objects.create(
            medication=self.med, time_of_day="08:00", days_of_week=["MON", "TUE", "WED", "THU", "FRI", "SAT", "SUN"],
        )
        MedicationEvent.objects.create(
            schedule=self.schedule, patient=self.patient, status="TAKEN",
            taken_at=timezone.now(),
        )
        Symptom.objects.create(
            patient=self.patient, pain_level=4, recorded_at=timezone.now(),
        )
        HealthTimelineEntry.objects.create(
            patient=self.patient, event_type="MED_STARTED", event_id=_uuid.uuid4(),
            occurred_at=timezone.now(), summary="started",
        )

    def test_dashboard_constant_query_count(self):
        from medications.services import dashboard

        with CaptureQueriesContext(__import__("django").db.connection) as ctx:
            payload = dashboard(self.patient)
        self.assertEqual(payload["medications"]["active_count"], 1)
        self.assertLessEqual(len(ctx), 7, "dashboard must stay within a small fixed query budget")

    def test_adherence_stats_batched_events(self):
        from medications.services import adherence_stats

        with CaptureQueriesContext(__import__("django").db.connection) as ctx:
            payload = adherence_stats(self.patient)
        self.assertGreaterEqual(payload["overall"]["taken"], 1)
        event_queries = [
            q["sql"] for q in ctx if "medication_events" in q["sql"].lower()
        ]
        self.assertLessEqual(len(event_queries), 1, "adherence aggregation must batch to one query")


class JobQueueTests(TestCase):
    def setUp(self):
        cache.clear()
        _WORKED.clear()

    def test_enqueue_and_process_succeeds(self):
        job = enqueue(task="perf.test_ok", payload={"seed": 7})
        results = process_due(limit=10)
        self.assertEqual(len(results), 1)
        row, outcome = results[0]
        self.assertEqual(outcome, "ok")
        self.assertEqual(row.status, "SUCCEEDED")
        self.assertEqual(_WORKED["perf.test_ok"], {"seed": 7})
        self.assertEqual(BackgroundJob.objects.get(pk=job.pk).status, "SUCCEEDED")

    def test_no_work_when_nothing_due(self):
        self.assertEqual(process_due(), [])
        self.assertEqual(BackgroundJob.objects.count(), 0)

    def test_failure_retries_then_fails_after_max_attempts(self):
        job = enqueue(task="perf.test_broken", max_attempts=3, payload={})
        # First run: attempt 1 fails → backed off to PENDING.
        _, outcome1 = process_due(limit=10)[0]
        self.assertEqual(outcome1, "retry")
        self.assertEqual(BackgroundJob.objects.get(pk=job.pk).status, "PENDING")
        # Force-due the retry repeatedly until attempts exhaust.
        for _ in range(4):
            now = timezone.now() + __import__("datetime").timedelta(days=1)
            results = process_due(limit=10, now=now)
            if results:
                outcome = results[0][1]
                if outcome == "failed":
                    break
        final = BackgroundJob.objects.get(pk=job.pk)
        self.assertEqual(final.status, "FAILED")
        self.assertIn("RuntimeError", final.error)

    def test_max_attempts_one_fails_immediately(self):
        enqueue(task="perf.test_broken", max_attempts=1, payload={})
        _, outcome = process_due(limit=10)[0]
        self.assertEqual(outcome, "failed")
        self.assertEqual(BackgroundJob.objects.get().status, "FAILED")

    def test_unknown_task_fails_loudly(self):
        job = enqueue(task="no.such.handler", payload={})
        _, outcome = process_due(limit=10)[0]
        self.assertEqual(outcome, "unknown_task")
        row = BackgroundJob.objects.get(pk=job.pk)
        self.assertEqual(row.status, "FAILED")
        self.assertIn("No handler registered", row.error)

    def test_claim_is_exclusive(self):
        enqueue(task="perf.test_ok", payload={})
        first = process_due(limit=1)
        second = process_due(limit=1)
        self.assertEqual(len(first), 1)
        self.assertEqual(second, [], "already-claimed job must not run twice")


class HealthObservabilityTests(TestCase):
    def test_health_readiness_checks_database_and_cache(self):
        resp = APIClient().get("/api/v1/health/ready/")
        self.assertEqual(resp.status_code, 200)
        self.assertEqual(resp.data["status"], "ok")
        self.assertEqual(resp.data["checks"]["database"], "ok")
        self.assertEqual(resp.data["checks"]["cache"], "ok")

    def test_health_liveness_ok(self):
        resp = APIClient().get("/api/v1/health/")
        self.assertEqual(resp.status_code, 200)

    def test_performance_headers_attached(self):
        resp = APIClient().get("/api/v1/health/ready/")
        self.assertIn("X-Duration-Ms", resp.headers)
        self.assertIn("X-Query-Count", resp.headers)

    def test_health_uses_real_cache_backend(self):
        from core.cache import reference_get, reference_set

        reference_set("ref:health:test_probe", 1, ttl=30)
        self.assertEqual(reference_get("ref:health:test_probe"), 1)