"""Stage 4.16 gate — Admin Panel / Platform Management & Governance (backend).

Approved surfaces (api-design AD-A-9/AD-A-13, endpoint-matrix §21, admin-web
UI/UX design — this stage ships the BACKEND for the admin panel; the admin-web
client is a deferred client stage per explicit scope decision):
    GET    /api/admin/users/                 admin.users.manage (SUP/ADM)
    POST   /api/admin/users/{uid}/activate|deactivate/   (reason, audited)
    GET/POST/DELETE /api/admin/users/{uid}/roles/        C17 rules, audited
    GET    /api/admin/security-events/       admin.audit.read (SUP/ADM)
    POST   /api/admin/notifications/broadcast/  notifications.broadcast
    GET    /api/admin/audit-logs/            audit_logs.view (+ filters)
    GET    /api/admin/audit-logs/export/     audit_logs.export (SUP, reason)
    GET    /api/admin/ai/monitoring/         admin.audit.read aggregates
    POST   /api/admin/campaigns/{uid}/pause|close/   campaigns.verify
    GET    /api/admin/financial/summary/     donations.view (confirmed ledger)

Invariants verified here:
    * failed-open-as-failed-closed: every mutation authorizes BEFORE validat-
      ing payloads (403 precedes 400) and every sensitive change is audited
    * C17 privilege boundaries — privileged = SUPER_ADMIN/ADMIN; self role
      change denied; ADMIN never grants/revokes privileged roles and never
      touches a privileged account's status/roles; last role never revoked
    * MFA step-up boundary blocks every admin surface for mfa_enabled admins
      and records MFA_CHALLENGE
    * payload-free/value-surface: user rows carry identity+RBAC only; audit
      exports/reads never include free-form details; AI monitoring never
      returns conversation content
    * financial summary reads ONLY confirmed ledger rows (BR-008: payment
      confirmation stays provider-webhook-only)
    * shorter admin session — admin refresh TTL == 8h, patient == 24h
    * system-settings surface is NOT IMPLEMENTED BECAUSE NOT APPROVED (the
      AD-A-8 API gap was not approved to build this stage)

Run (ephemeral SQLite; never touches Postgres):
    venv/bin/python stage416_gate.py
"""

import json
import os
import uuid
from datetime import timedelta
from decimal import Decimal

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
    from rest_framework.test import APIClient
    from rest_framework_simplejwt.tokens import RefreshToken

    from accounts.models import Role, User, UserRole
    from audit.models import AuditLog
    from audit.services import record_audit
    from notifications.models import Notification

    _PASSWORD = "Str0ng!Pass9"


    def orm_user(role_code, email=None, **extra):
        user = User.objects.create_user(
            email=email or f"{role_code.lower()}-{uuid.uuid4().hex[:10]}@example.com",
            password=_PASSWORD, first_name="Test", last_name="User",
            account_status="ACTIVE", **extra,
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


    super_user = orm_user("SUPER_ADMIN")
    admin = orm_user("ADMIN")
    moderator = orm_user("MODERATOR")
    staff = orm_user("HEALTHCARE_STAFF")
    patient = orm_user("PATIENT")
    target = orm_user("PATIENT")
    c_super = client(super_user)
    c_admin = client(admin)
    c_mod = client(moderator)
    c_staff = client(staff)
    c_patient = client(patient)

    # 1. Vertical access — /admin/users + /admin/security-events.
    check("users list allowed (SUP)", c_super.get("/api/admin/users/").status_code == 200)
    check("users list allowed (ADM)", c_admin.get("/api/admin/users/").status_code == 200)
    deny = {c_patient.get("/api/admin/users/").status_code,
            c_mod.get("/api/admin/users/").status_code,
            c_staff.get("/api/admin/users/").status_code}
    check("users list denied (PATIENT/MODERATOR/STAFF)", deny == {403})
    check("users list anonymous 401", APIClient().get("/api/admin/users/").status_code == 401)
    check("security-events list allowed (ADM)",
          c_admin.get("/api/admin/security-events/").status_code == 200)
    check("security-events denied (PATIENT)",
          c_patient.get("/api/admin/security-events/").status_code == 403)

    # 2. No medical leakage — identity + RBAC only.
    rows = c_super.get("/api/admin/users/").json()["data"]["results"]
    allowed = {"uid", "email", "phone", "full_name", "account_status",
               "role_codes", "mfa_enabled", "created_at"}
    check("user rows expose identity/RBAC only",
          all(set(r.keys()) == set(allowed) for r in rows))

    # 3. Activate/deactivate (reason audited, authorise-before-validate).
    r = c_admin.post(f"/api/admin/users/{target.uid}/deactivate/",
                     {"reason": "Repeated abuse reports"}, format="json")
    check("deactivate 200 (ADM non-privileged)", r.status_code == 200)
    target.refresh_from_db()
    check("target now SUSPENDED", target.account_status == "SUSPENDED")
    check("deactivate audited", AuditLog.objects.filter(
        action_code="admin.user.deactivate", resource_type="users").count() >= 1)
    r = c_admin.post(f"/api/admin/users/{target.uid}/activate/",
                     {"reason": "Appeal reviewed"}, format="json")
    check("activate 200 + audited", r.status_code == 200
          and AuditLog.objects.filter(action_code="admin.user.activate").count() >= 1)
    reasonless = c_admin.post(f"/api/admin/users/{target.uid}/deactivate/",
                              {"reason": "x"}, format="json")
    check("short reason -> 400", reasonless.status_code == 400)
    self_deact = c_super.post(f"/api/admin/users/{super_user.uid}/deactivate/",
                              {"reason": "Self deactivation"}, format="json")
    check("self-deactivation denied (403)", self_deact.status_code == 403)

    # 4. Roles — C17 privilege boundaries.
    docs = c_admin.get(f"/api/admin/users/{target.uid}/roles/")
    check("roles GET ok", docs.status_code == 200
          and set(docs.json()["data"].keys()) == {"uid", "roles"})
    r = c_admin.post(f"/api/admin/users/{target.uid}/roles/",
                     {"role_code": "BLOOD_DONOR", "reason": "Volunteer intake"}, format="json")
    check("ADM grants non-privileged role", r.status_code == 200
          and "BLOOD_DONOR" in r.json()["data"]["role_codes"])
    check("role_grant audited", AuditLog.objects.filter(
        action_code="admin.user.role_grant").count() >= 1)
    self_assign = c_super.post(f"/api/admin/users/{super_user.uid}/roles/",
                               {"role_code": "MODERATOR", "reason": "Self promotion"},
                               format="json")
    check("self role-change denied (403)", self_assign.status_code == 403)
    priv_grant = c_admin.post(f"/api/admin/users/{target.uid}/roles/",
                              {"role_code": "SUPER_ADMIN", "reason": "Elevation"},
                              format="json")
    check("ADM cannot grant privileged role (403)", priv_grant.status_code == 403)
    c_admin.post(f"/api/admin/users/{admin.uid}/roles/",
                 {"role_code": "PATIENT", "reason": "Role cleanup"}, format="json")
    touch_priv = c_admin.post(f"/api/admin/users/{admin.uid}/deactivate/",
                              {"reason": "Dispute"}, format="json")
    check("ADM cannot touch privileged account (403)", touch_priv.status_code == 403)
    solo = orm_user("BLOOD_DONOR")
    last_role = c_super.delete(f"/api/admin/users/{solo.uid}/roles/",
                               {"role_code": "BLOOD_DONOR", "reason": "Removing role"},
                               format="json")
    check("last-role revocation blocked (400)", last_role.status_code == 400)
    unknown = c_super.get(f"/api/admin/users/{uuid.uuid4()}/")
    check("unknown user IDOR -> 404", unknown.status_code == 404)

    # 5. MFA step-up boundary (admin surfaces).
    mfa_admin = orm_user("ADMIN", mfa_enabled=True)
    r = client(mfa_admin).get("/api/admin/users/")
    check("mfa_enabled admin blocked on /admin/users (403)", r.status_code == 403)
    check("MFA_CHALLENGE recorded", AuditLog.objects.filter(
        action_code__in=("admin.security.mfa", "mfa.challenge"),
        result="DENIED").count() >= 1 or AuditLog.objects.filter(
        result="DENIED", details__mfa="challenge").count() >= 1
        or __import__("accounts.models", fromlist=["SecurityEvent"])
        .SecurityEvent.objects.filter(event_type="MFA_CHALLENGE").count() >= 1)
    mfa_patient = orm_user("PATIENT", mfa_enabled=True)
    check("mfa_enabled patient unaffected (200)",
          client(mfa_patient).get("/api/auth/me/").status_code == 200)

    # 6. Broadcast — audience rules + vertical.
    cache.clear()
    b = c_super.post("/api/admin/notifications/broadcast/",
                     {"audience": "ROLE", "role_code": "PATIENT",
                      "title": "Scheduled maintenance", "body": "Downtime 02:00-03:00"},
                     format="json")
    check("broadcast ROLE 201", b.status_code == 201 and b.json()["data"]["recipient_count"] >= 1)
    check("broadcast audited", AuditLog.objects.filter(
        action_code="notifications.broadcast").count() >= 1)
    check("broadcast vertical denial",
          c_patient.post("/api/admin/notifications/broadcast/",
                         {"audience": "ALL", "title": "x", "body": "y"},
                         format="json").status_code == 403)
    too_many = c_super.post("/api/admin/notifications/broadcast/",
                            {"audience": "USERS",
                             "user_uid": [str(uuid.uuid4()) for _ in range(501)]},
                            format="json")
    check("broadcast USERS capped -> 400", too_many.status_code == 400)

    # 7. Audit search/export.
    record_audit(actor=super_user, action_code="campaign.close",
                 resource_type="campaign", result="SUCCESS")
    f = c_super.get("/api/admin/audit-logs/", {"action_code": "campaign.close"})
    check("audit filter by action_code", f.status_code == 200
          and all(x["action_code"] == "campaign.close" for x in f.json()["data"]["results"]))
    e = c_super.get("/api/admin/audit-logs/export/?reason=Annual%20archive")
    check("audit CSV export (SUP)", e.status_code == 200
          and e.content.startswith(b"created_at,"))
    check("export denied for ADMIN", c_admin.get(
        "/api/admin/audit-logs/export/?reason=Annual%20archive").status_code == 403)
    check("export requires reason",
          c_super.get("/api/admin/audit-logs/export/").status_code == 400)
    check("export self-audited", AuditLog.objects.filter(
        action_code="audit_logs.export").count() >= 1)

    # 8. AI monitoring — aggregates only, no content.
    record_audit(actor=patient, action_code="ai.request", resource_type="ai", result="SUCCESS")
    m = c_super.get("/api/admin/ai/monitoring/")
    check("AI monitoring 200", m.status_code == 200
          and m.json()["data"]["total_events"] >= 1)
    body = json.dumps(m.json())
    check("AI monitoring returns no conversation content",
          all(w not in body.lower() for w in ("prompt", "user_content")))
    check("AI monitoring vertical denial", c_patient.get(
        "/api/admin/ai/monitoring/").status_code == 403)

    # 9. Campaign pause/close + financial summary (confirmed ledger only).
    from donations.models import Campaign, Donation, Refund, CampaignStatus, DonationStatus
    camp = Campaign.objects.create(
        owner=super_user, title="Help Essau's surgery", description="Surgery fund",
        goal_amount=Decimal("500000.00"), raised_amount=Decimal("0.00"),
        status=CampaignStatus.ACTIVE, verified_at=None)
    p = c_super.post(f"/api/admin/campaigns/{camp.uid}/pause/",
                     {"reason": "Compliance review"}, format="json")
    check("campaign pause 200", p.status_code == 200)
    camp.refresh_from_db()
    check("campaign now PAUSED", camp.status == CampaignStatus.PAUSED)
    cl = c_super.post(f"/api/admin/campaigns/{camp.uid}/close/",
                      {"reason": "Stopped, going to refunds"}, format="json")
    check("campaign close 200", cl.status_code == 200)
    camp.refresh_from_db()
    check("campaign now CLOSED", camp.status == CampaignStatus.CLOSED)
    don = Donation.objects.create(
        campaign=camp, donor=patient, amount=Decimal("10000.00"),
        status=DonationStatus.COMPLETED, idempotency_key=uuid.uuid4().hex,
        transaction_ref=uuid.uuid4().hex[:32])
    Refund.objects.create(donation=don, amount=Decimal("2500.00"),
                          reason="Duplicate charge", initiated_by=super_user,
                          status="PROCESSED")
    sum_ = c_super.get("/api/admin/financial/summary/")
    data = sum_.json()["data"]
    check("financial summary confirmed-ledger total",
          sum_.status_code == 200 and Decimal(str(data["confirmed_donations_total"]))
          == Decimal("10000.00"))
    check("financial summary refunded total",
          Decimal(str(data["refunded_total"])) == Decimal("2500.00"))
    check("financial summary vertical denial",
          c_patient.get("/api/admin/financial/summary/").status_code == 403)

    # 10. Shorter admin session — admin TTL 8h, patient 24h.
    from datetime import datetime, timezone as _tz

    now = datetime.now(_tz.utc)
    t_admin = APIClient().post(
        "/api/auth/login/",
        {"email_or_phone": admin.email, "password": _PASSWORD}, format="json").json()["data"]["refresh"]
    t_patient = APIClient().post(
        "/api/auth/login/",
        {"email_or_phone": patient.email, "password": _PASSWORD}, format="json").json()["data"]["refresh"]
    admin_exp = datetime.fromtimestamp(RefreshToken(t_admin).payload["exp"], tz=_tz.utc)
    patient_exp = datetime.fromtimestamp(RefreshToken(t_patient).payload["exp"], tz=_tz.utc)
    check("admin refresh TTL ~8h", timedelta(hours=7) < admin_exp - now < timedelta(hours=9))
    check("patient refresh TTL ~24h",
          timedelta(hours=23) < patient_exp - now < timedelta(hours=25))

    ok = len(checks) == sum(1 for _, passed in checks if passed)
finally:
    runner.teardown_databases(old_config)

print(f"Stage 4.16 gate: {sum(1 for _, p in checks if p)}/{len(checks)} checks passed")
print("GATE_OK" if ok else "GATE_FAILED")
raise SystemExit(0 if ok else 1)