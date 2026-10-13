"""Analytics & reporting tests (Stage 4.14).

Covers the approved surface end-to-end:
  * authorization — SUP/ADM/VO 200, every other role 403 (audited DENIED),
    anonymous 401, suspended 403
  * C6 scope — a VERIFICATION_OFFICER sees only the verification metric set
  * whitelist + validation — unknown metric / bad granularity / bad windows
    all 400; out-of-scope metric 403
  * aggregate idempotency — re-running a day upserts, never duplicates, and
    service/dashboard figures come from snapshots (no PHI in CSV)
  * export — C4 ``reason`` gate for ADMIN, free for SUPER_ADMIN, 403 for VO,
    every export audited with filters + row_count
  * rate limiting — 60/min per user (security-api-traceability)
"""

import uuid

from django.core.cache import cache
from django.test import TestCase
from django.utils import timezone
from rest_framework.test import APIClient
from rest_framework_simplejwt.tokens import RefreshToken

from accounts.models import Role, User, UserRole
from audit.models import AuditLog
from blood_network.models import BloodRequest

from . import services
from .models import AnalyticsSnapshot

_PASSWORD = "Str0ng!Pass9"


def _orm_user(role_code, account_status="ACTIVE", email=None, **extra):
    user = User.objects.create_user(
        email=email or f"an-{role_code.lower()}-{uuid.uuid4().hex[:10]}@example.com",
        password=_PASSWORD,
        first_name="Test",
        last_name=role_code.title(),
        account_status=account_status,
        **extra,
    )
    UserRole.objects.create(user=user, role=Role.objects.get(code=role_code))
    return user


def _client(user):
    client = APIClient()
    client.credentials(
        HTTP_AUTHORIZATION=f"Bearer {RefreshToken.for_user(user).access_token}",
    )
    return client


class AnalyticsAuthorizationTests(TestCase):
    def setUp(self):
        cache.clear()
        self.super_admin = _orm_user("SUPER_ADMIN")
        self.admin = _orm_user("ADMIN")
        self.vo = _orm_user("VERIFICATION_OFFICER")
        self.mod = _orm_user("MODERATOR")
        self.doctor = _orm_user("DOCTOR")
        self.patient = _orm_user("PATIENT")
        self.caregiver = _orm_user("CAREGIVER")
        self.suspended = _orm_user("ADMIN", account_status="SUSPENDED")
        self.superc = _client(self.super_admin)
        self.adminc = _client(self.admin)
        self.voc = _client(self.vo)
        self.modc = _client(self.mod)
        self.doctorc = _client(self.doctor)
        self.patientc = _client(self.patient)
        self.caregivc = _client(self.caregiver)
        self.suspended_c = _client(self.suspended)

    def test_anonymous_401(self):
        anon = APIClient()
        self.assertEqual(anon.get("/api/admin/dashboard/").status_code, 401)
        self.assertEqual(
            anon.get("/api/admin/analytics/?metric=users.total").status_code, 401,
        )

    def test_super_admin_and_admin_allowed(self):
        for c in (self.superc, self.adminc):
            dash = c.get("/api/admin/dashboard/")
            self.assertEqual(dash.status_code, 200)
            self.assertIn("kpis", dash.data)
            series = c.get("/api/admin/analytics/?metric=users.total")
            self.assertEqual(series.status_code, 200)
            self.assertEqual(series.data["metric"], "users.total")

    def test_verification_officer_allowed_with_vo_kernel(self):
        dash = self.voc.get("/api/admin/dashboard/")
        self.assertEqual(dash.status_code, 200)
        self.assertEqual(dash.data["role_kernel"], "VERIFICATION_OFFICER")
        series = self.voc.get("/api/admin/analytics/?metric=blood_requests.by_status")
        self.assertEqual(series.status_code, 200)

    def test_non_analytics_roles_403_and_audited_denied(self):
        begin = AuditLog.objects.filter(
            action_code="analytics.access_denied",
        ).count()
        for c in (self.modc, self.doctorc, self.patientc, self.caregivc):
            self.assertEqual(c.get("/api/admin/dashboard/").status_code, 403)
            self.assertEqual(
                c.get("/api/admin/analytics/?metric=users.total").status_code, 403,
            )
        denied = AuditLog.objects.filter(
            action_code="analytics.access_denied",
        )
        self.assertGreater(denied.count(), begin)
        self.assertEqual(
            set(denied.values_list("result", flat=True).distinct()),
            {"DENIED"},
        )

    def test_suspended_admin_403(self):
        self.assertEqual(self.suspended_c.get("/api/admin/dashboard/").status_code, 403)
        self.assertEqual(
            self.suspended_c.get("/api/admin/analytics/?metric=users.total").status_code, 403,
        )


class VoC6ScopeTests(TestCase):
    def setUp(self):
        cache.clear()
        self.vo = _orm_user("VERIFICATION_OFFICER")
        self.voc = _client(self.vo)

    def test_scope_metric_allowed(self):
        for metric in (
            "blood_requests.by_status", "blood_requests.by_urgency",
            "campaigns.by_status", "verification_docs.by_status",
        ):
            self.assertEqual(
                self.voc.get(f"/api/admin/analytics/?metric={metric}").status_code,
                200, msg=metric,
            )
        allowed = services.allowed_metrics(self.vo)
        self.assertTrue(all(allowed))
        for blocked in ("users.total", "donations.confirmed_amount",
                        "emergency_requests.by_status", "community_posts.by_status"):
            self.assertNotIn(blocked, allowed)

    def test_out_of_scope_metric_403_and_audited(self):
        before = AuditLog.objects.filter(action_code="analytics.access_denied").count()
        r = self.voc.get("/api/admin/analytics/?metric=users.total")
        self.assertEqual(r.status_code, 403)
        row = AuditLog.objects.filter(
            action_code="analytics.access_denied",
            actor=self.vo,
        ).order_by("-id").first()
        self.assertIsNotNone(row)
        self.assertEqual(row.result, "DENIED")
        self.assertEqual(row.details.get("metric"), "users.total")
        self.assertGreater(
            AuditLog.objects.filter(action_code="analytics.access_denied").count(),
            before,
        )

    def test_vo_export_forbidden(self):
        r = self.voc.get(
            "/api/admin/analytics/?metric=blood_requests.by_status&export=csv",
        )
        self.assertEqual(r.status_code, 403)


class QueryValidationTests(TestCase):
    def setUp(self):
        cache.clear()
        self.admin = _orm_user("ADMIN")
        self.c = _client(self.admin)

    def get(self, **params):
        pairs = [f"{k}={v}" for k, v in params.items()]
        return self.c.get("/api/admin/analytics/?" + "&".join(pairs))

    def test_unknown_metric_400(self):
        self.assertEqual(self.get(metric="not.a.metric").status_code, 400)

    def test_bad_granularity_400(self):
        self.assertEqual(
            self.get(metric="users.total", granularity="YEARLY").status_code, 400,
        )

    def test_avg_metric_weekly_400(self):
        # avg-of-averages guard: symptoms.avg_pain is DAILY-only.
        self.assertEqual(
            self.get(metric="symptoms.avg_pain", granularity="WEEKLY").status_code, 400,
        )

    def test_inverted_dates_400(self):
        self.assertEqual(
            self.get(
                metric="users.total",
                date_from="2026-09-20",
                date_to="2026-09-01",
            ).status_code, 400,
        )

    def test_window_too_large_400(self):
        self.assertEqual(
            self.get(
                metric="users.total",
                date_from="2024-01-01",
                date_to="2026-09-01",
            ).status_code, 400,
        )

    def test_malformed_date_400(self):
        self.assertEqual(
            self.get(metric="users.total", date_from="yesterday").status_code, 400,
        )

    def test_dashboard_reads_snapshots(self):
        for _ in range(3):
            _orm_user("PATIENT")
        _orm_user("PATIENT", account_status="SUSPENDED")
        services.compute_daily(timezone.now())
        dash = self.c.get("/api/admin/dashboard/").data
        self.assertEqual(dash["kpis"]["users_total"], 5.0)
        self.assertEqual(dash["kpis"]["users_active"], 4.0)
        self.assertEqual(dash["kpis"]["users_active_patients"], 3.0)

    def test_dashboard_is_live_without_any_snapshot_rows(self):
        """A missing/late aggregation job must not blank or stale the cards.

        The dashboard answers directly from the source tables, so it is correct
        even on a fresh database where the nightly job has never run.
        """
        AnalyticsSnapshot.objects.all().delete()
        _orm_user("PATIENT")
        _orm_user("DOCTOR")
        dash = self.c.get("/api/admin/dashboard/").data
        self.assertEqual(dash["kpis"]["users_total"], 3)  # admin + 2
        self.assertEqual(dash["kpis"]["users_patient"], 1)
        self.assertEqual(dash["kpis"]["users_doctor"], 1)

    def test_dashboard_counts_roles_from_the_source_tables(self):
        _orm_user("PATIENT")
        _orm_user("PATIENT")
        _orm_user("BLOOD_DONOR")
        _orm_user("FINANCIAL_DONOR")
        _orm_user("CAREGIVER")
        dash = self.c.get("/api/admin/dashboard/").data["kpis"]
        self.assertEqual(dash["users_patient"], 2)
        self.assertEqual(dash["users_blood_donor"], 1)
        self.assertEqual(dash["users_financial_donor"], 1)
        self.assertEqual(dash["users_caregiver"], 1)

    def test_dashboard_reports_pending_verifications_live(self):
        BloodRequest.objects.create(
            patient=_orm_user("PATIENT"), created_by=self.admin,
            blood_group_needed="O+", units=1, status="PENDING_VERIFICATION",
        )
        dash = self.c.get("/api/admin/dashboard/").data["kpis"]
        self.assertEqual(dash["blood_requests_pending_verification"], 1)
        self.assertEqual(dash["pending_verifications"], 1)

    def test_dashboard_labels_the_source_of_every_kpi(self):
        dash = self.c.get("/api/admin/dashboard/").data
        sources = dash["kpi_sources"]
        for key in dash["kpis"]:
            self.assertIn(key, sources)
        self.assertEqual(sources["users_total"], "live")

    def test_suspended_users_are_not_counted_as_active(self):
        _orm_user("ADMIN", account_status="SUSPENDED")
        _orm_user("ADMIN", account_status="PENDING_VERIFICATION")
        dash = self.c.get("/api/admin/dashboard/").data["kpis"]
        self.assertEqual(dash["users_suspended"], 1)
        self.assertEqual(dash["users_pending_verification"], 1)
        self.assertLess(dash["users_active"], dash["users_total"])

    def test_series_reflects_snapshots(self):
        _orm_user("PATIENT")
        _orm_user("PATIENT")
        services.compute_daily(timezone.now())
        r = self.c.get("/api/admin/analytics/?metric=users.total")
        self.assertEqual(r.status_code, 200)
        self.assertEqual(len(r.data["results"]), 1)
        self.assertEqual(r.data["results"][0]["value"], 3.0)


class SnapshotIdempotencyTests(TestCase):
    def setUp(self):
        cache.clear()
        self.day = timezone.now()

    def test_daily_aggregation_is_idempotent(self):
        self.patient_a = _orm_user("PATIENT")
        self.patient_b = _orm_user("PATIENT")
        self.admin = _orm_user("ADMIN")
        BloodRequest.objects.create(
            patient=self.patient_a, created_by=self.admin,
            blood_group_needed="O+", units=1, status="PENDING_VERIFICATION",
        )
        first = services.compute_daily(self.day)
        total = AnalyticsSnapshot.objects.count()
        second = services.compute_daily(self.day)
        self.assertEqual(AnalyticsSnapshot.objects.count(), total)
        self.assertEqual(second, first)
        self.assertGreaterEqual(first, 1)
        self.assertEqual(services.latest("users.total"), 3.0)
        self.assertEqual(
            services.latest("users.active_patients"), 2.0,
        )
        self.assertEqual(
            services.latest(
                "blood_requests.by_status", {"status": "PENDING_VERIFICATION"},
            ),
            1.0,
        )

    def test_build_snapshot_upserts_unique_row(self):
        a = services.build_snapshot(
            "users.total", 5, measured_at=self.day,
        )
        b = services.build_snapshot(
            "users.total", 7, measured_at=self.day,
        )
        self.assertEqual(a.pk, b.pk)
        self.assertEqual(
            AnalyticsSnapshot.objects.filter(metric_key="users.total").count(), 1,
        )
        self.assertEqual(services.latest("users.total"), 7.0)

    def test_different_dimensions_are_distinct_rows(self):
        services.build_snapshot(
            "blood_requests.by_status", 1,
            dimensions={"status": "ACTIVE"}, measured_at=self.day,
        )
        services.build_snapshot(
            "blood_requests.by_status", 2,
            dimensions={"status": "MATCHED"}, measured_at=self.day,
        )
        self.assertEqual(
            AnalyticsSnapshot.objects.filter(metric_key="blood_requests.by_status").count(),
            2,
        )
        self.assertEqual(
            services.latest("blood_requests.by_status", {"status": "ACTIVE"}), 1.0,
        )
        self.assertEqual(
            services.latest("blood_requests.by_status", {"status": "MATCHED"}), 2.0,
        )

    def test_weekly_rollup_sums(self):
        import datetime
        from django.utils import timezone as tz
        # Seed two days INSIDE the current ISO week (the Monday of this week),
        # otherwise the seeded days straddle the %W boundary when the run lands
        # on a Monday and the weekly buckets split across two periods.
        monday = (
            tz.now() - datetime.timedelta(days=tz.now().weekday())
        ).replace(hour=0, minute=0, second=0, microsecond=0)
        for i, offset in enumerate((0, 1)):
            services.build_snapshot(
                "users.total", i + 1, measured_at=monday + datetime.timedelta(days=offset),
            )
        svc = services.AnalyticsService()
        weekly = svc.series(self._admin(), "users.total", granularity="WEEKLY")
        self.assertTrue(weekly)
        self.assertEqual(weekly[0]["value"], 3.0)

    def _admin(self):
        return _orm_user("ADMIN")


class ExportTests(TestCase):
    def setUp(self):
        cache.clear()
        self.admin = _orm_user("ADMIN")
        self.super_admin = _orm_user("SUPER_ADMIN")
        _orm_user("PATIENT")
        services.compute_daily(timezone.now())
        self.adminc = _client(self.admin)
        self.superc = _client(self.super_admin)
        self.base = "/api/admin/analytics/?metric=users.total&export=csv"

    def test_admin_export_requires_reason(self):
        r = self.adminc.get(self.base)
        self.assertEqual(r.status_code, 400)

    def test_admin_export_with_reason_ok_and_audited(self):
        r = self.adminc.get(self.base + "&reason=compliance-review")
        self.assertEqual(r.status_code, 200)
        self.assertEqual(r["Content-Type"], "text/csv")
        body = r.content.decode()
        self.assertIn("users.total", body)
        self.assertIn("metric_key", body)
        row = AuditLog.objects.filter(
            action_code="analytics.export", actor=self.admin, result="SUCCESS",
        ).order_by("-id").first()
        self.assertIsNotNone(row)
        self.assertEqual(row.details["format"], "csv")
        self.assertEqual(row.details["metric"], "users.total")
        self.assertEqual(row.details["reason"], "compliance-review")
        self.assertGreaterEqual(row.details["row_count"], 1)

    def test_super_admin_export_no_reason_ok(self):
        r = self.superc.get(self.base)
        self.assertEqual(r.status_code, 200)
        self.assertEqual(r["Content-Type"], "text/csv")

    def test_export_never_leaks_phi(self):
        r = self.superc.get(self.base)
        lowered = r.content.decode().lower()
        for forbidden in ("email", "first_name", "password", "notes", "phone",
                          "patient_uid", "details"):
            self.assertNotIn(forbidden, lowered)

    def test_json_export_switch_is_ignored(self):
        r = self.adminc.get("/api/admin/analytics/?metric=users.total&export=json")
        self.assertEqual(r.status_code, 200)


class AnalyticsThrottleTests(TestCase):
    def setUp(self):
        cache.clear()
        self.admin = _orm_user("ADMIN")
        self.c = _client(self.admin)

    def test_read_throttle_60_per_minute(self):
        statuses = [
            self.c.get("/api/admin/dashboard/").status_code
            for _ in range(60)
        ]
        self.assertEqual(set(statuses), {200})
        over = self.c.get("/api/admin/dashboard/")
        self.assertEqual(over.status_code, 429)