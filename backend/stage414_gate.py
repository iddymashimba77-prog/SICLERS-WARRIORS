"""Stage 4.14 gate — Analytics, Reporting & Health Insights.

Approved surface:
    GET /api/admin/dashboard/   SUP/ADM (KPI kernel), VO (C6 verification)
    GET /api/admin/analytics/   whitelisted metrics, granularity, CSV export (C4)

Run (ephemeral SQLite; never touches Postgres):
    venv/bin/python stage414_gate.py
"""

import os
import uuid

os.environ.setdefault("DJANGO_SETTINGS_MODULE", "config.settings.ephemeral_test")

import django

django.setup()

from django.core.cache import cache

cache.clear()

from django.test.runner import DiscoverRunner

runner = DiscoverRunner(verbosity=0, interactive=False)
old_config = runner.setup_databases()

ok = False
try:
    from django.utils import timezone
    from rest_framework.test import APIClient
    from rest_framework_simplejwt.tokens import RefreshToken

    from accounts.models import Role, User, UserRole
    from audit.models import AuditLog

    from analytics import services
    from analytics.models import AnalyticsSnapshot

    _PASSWORD = "Str0ng!Pass9"


    def orm_user(role_code):
        user = User.objects.create_user(
            email=f"{role_code.lower()}-{uuid.uuid4().hex[:10]}@example.com",
            password=_PASSWORD, first_name="Test", last_name="User",
            account_status="ACTIVE",
        )
        UserRole.objects.create(user=user, role=Role.objects.get(code=role_code))
        return user


    def client(user):
        c = APIClient()
        c.credentials(HTTP_AUTHORIZATION=f"Bearer {RefreshToken.for_user(user).access_token}")
        return c

    checks = []


    def check(name, cond):
        checks.append((name, bool(cond)))
        if not cond:
            print(f"  [x] {name}")


    su = orm_user("SUPER_ADMIN")
    admin = orm_user("ADMIN")
    vo = orm_user("VERIFICATION_OFFICER")
    mod = orm_user("MODERATOR")
    patient = orm_user("PATIENT")
    patient2 = orm_user("PATIENT")

    c_su = client(su)
    c_admin = client(admin)
    c_vo = client(vo)
    c_mod = client(mod)

    # 1. Idempotent aggregation.
    first = services.compute_daily(timezone.now())
    total_rows = AnalyticsSnapshot.objects.count()
    second = services.compute_daily(timezone.now())
    check("aggregation idempotent", second == first and AnalyticsSnapshot.objects.count() == total_rows)
    check("users.total aggregated", services.latest("users.total") == 6.0)
    check("users.active_patients aggregated", services.latest("users.active_patients") == 2.0)

    # 2. Authorization (SUP/ADM 200, MOD 403 audited, anon 401).
    check("admin dashboard 200", c_admin.get("/api/admin/dashboard/").status_code == 200)
    check("super admin analytics 200", c_su.get("/api/admin/analytics/?metric=users.total").status_code == 200)
    check("mod extinct access -> 403", c_mod.get("/api/admin/dashboard/").status_code == 403)
    check("mod 403 is audited DENIED", AuditLog.objects.filter(
        action_code="analytics.access_denied", actor=mod, result="DENIED").count() >= 1)
    check("anonymous -> 401", APIClient().get("/api/admin/dashboard/").status_code == 401)

    # 3. VO C6 scope.
    dash_vo = c_vo.get("/api/admin/dashboard/")
    check("VO dashboard 200 + VO kernel", dash_vo.status_code == 200 and dash_vo.data["role_kernel"] == "VERIFICATION_OFFICER")
    check("VO scope metric allowed", c_vo.get("/api/admin/analytics/?metric=blood_requests.by_status").status_code == 200)
    check("VO out-of-scope users.total -> 403", c_vo.get("/api/admin/analytics/?metric=users.total").status_code == 403)

    # 4. KPI kernel correctness from snapshots.
    dash = c_admin.get("/api/admin/dashboard/").data
    check("admin users_total KPI == 6", dash["kpis"].get("users_total") == 6.0)
    check("admin no verification keys in kernel", "blood_requests_pending_verification" not in dash["kpis"])
    check("admin trends populated", "users.total" in dash["trends"])

    # 5. Whitelist + validation.
    check("unknown metric -> 400", c_admin.get("/api/admin/analytics/?metric=nope.x").status_code == 400)
    check("bad granularity -> 400", c_admin.get("/api/admin/analytics/?metric=users.total&granularity=YEARLY").status_code == 400)
    check("avg-of-avg guard weekly -> 400", c_admin.get("/api/admin/analytics/?metric=symptoms.avg_pain&granularity=WEEKLY").status_code == 400)
    check("inverted date window -> 400", c_admin.get("/api/admin/analytics/?metric=users.total&date_from=2026-09-20&date_to=2026-09-01").status_code == 400)

    # 6. CSV export + C4 gate + audit.
    check("admin export without reason -> 400", c_admin.get("/api/admin/analytics/?metric=users.total&export=csv").status_code == 400)
    exported = c_admin.get("/api/admin/analytics/?metric=users.total&export=csv&reason=compliance")
    check("admin export with reason -> csv", exported.status_code == 200 and exported["Content-Type"] == "text/csv")
    check("csv header + aggregate row", b"metric_key" in exported.content and b"users.total" in exported.content)
    check("export audited with filters", AuditLog.objects.filter(
        action_code="analytics.export", actor=admin, result="SUCCESS",
        details__format="csv", details__metric="users.total").count() >= 1)
    check("super admin export no reason", c_su.get(
        "/api/admin/analytics/?metric=users.total&export=csv").status_code == 200)
    check("VO export denied", c_vo.get(
        "/api/admin/analytics/?metric=blood_requests.by_status&export=csv").status_code == 403)

    # 7. Rate limiting: 60/min/user.
    throttled = orm_user("ADMIN")
    c_thr = client(throttled)
    bursts = [c_thr.get("/api/admin/dashboard/").status_code for _ in range(60)]
    check("60 reads allowed", set(bursts) == {200})
    check("61st read throttled -> 429", c_thr.get("/api/admin/dashboard/").status_code == 429)

    ok = len(checks) == sum(1 for _, passed in checks if passed)
finally:
    runner.teardown_databases(old_config)

print(f"Stage 4.14 gate: {sum(1 for _, p in checks if p)}/{len(checks)} checks passed")
print("GATE_OK" if ok else "GATE_FAILED")
raise SystemExit(0 if ok else 1)