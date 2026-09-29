"""Stage 4.17 gate — Security, Privacy, Compliance & Data Protection Hardening.

Hardening applied this stage (each verified here against REAL endpoints):

    §20 session lifecycle  — logout denylists refresh; rotation denylists the
        presented refresh; password change + password reset revoke EVERY
        outstanding session (denylist + rev-claim); account suspension flips
        ``is_active`` too so the live session and refresh rotation stop.
    §25 password policy    — Django AUTH_PASSWORD_VALIDATORS now run at
        register, password-reset-confirm and password-change (weak rejected).
    §26 reset hardening    — unknown accounts get the same uniform 202/200
        (never a 500); per-account cooldown caps reset-token issuance;
        hostile correlation ids are replaced server-side (log-injection
        defence).
    §27 provider fail-closed — in a ``production`` payment env the shared/dev
        webhook secret is refused; a per-provider live secret is required;
        settings refuse to import without an operator-supplied SECRET_KEY.
    §28 privileges         — refund access (money movement) honours the MFA
        step-up boundary like every other admin mutation.
    §15 community          — moderation_reason is moderation-only; comment
        threads of HIDDEN posts are invisible to members; reaction types
        whitelisted.
    §16 blood              — donor-facing request LIST now uses the public
        subset (no requester contact / rejection internals); COMPLETED
        donation events require an ACCEPTED/FULFILLED match (chain of custody).
    §18 emergencies        — clients can no longer self-assert phone_verified.
    §33 schema/docs        — OpenAPI schema + Swagger UI are admin-only outside
        DEBUG (silent 404); open when DEBUG.

Run (ephemeral SQLite; never touches Postgres):
    venv/bin/python stage417_gate.py
"""

import json
import os
import re
import subprocess
import sys
import uuid

os.environ.setdefault("DJANGO_SETTINGS_MODULE", "config.settings.ephemeral_test")

import django

django.setup()

from django.core.cache import cache

cache.clear()

from django.test import override_settings
from django.test.runner import DiscoverRunner

runner = DiscoverRunner(verbosity=0, interactive=False)
old_config = runner.setup_databases()

ok = False
try:
    from rest_framework.test import APIClient
    from rest_framework_simplejwt.tokens import RefreshToken

    from accounts.models import OneTimeToken, Role, SecurityEvent, User, UserRole
    from blood_network.models import BloodDonor, BloodMatch, BloodRequest
    from community.models import Comment, CommunityPost
    from donations import providers
    from facilities.models import Facility
    from notifications.models import Notification

    _PASSWORD = "Str0ng!Pass9"
    _NEW_PASSWORD = "An0ther!Str0ng9"
    _WEAK_COMMON = "password"
    _WEAK_NUMERIC = "12345678"


    class _JsonAPIClient(APIClient):
        def _json(self, kwargs):
            kwargs.setdefault("format", "json")

        def post(self, *args, **kwargs):
            self._json(kwargs)
            return super().post(*args, **kwargs)

        def patch(self, *args, **kwargs):
            self._json(kwargs)
            return super().patch(*args, **kwargs)


    def orm_user(role_code, account_status="ACTIVE", **extra):
        user = User.objects.create_user(
            email=f"{role_code.lower()}-{uuid.uuid4().hex[:10]}@example.com",
            password=_PASSWORD, first_name="Test", last_name=role_code.title(),
            account_status=account_status, **extra,
        )
        UserRole.objects.create(user=user, role=Role.objects.get(code=role_code))
        return user


    def _client(user):
        client = _JsonAPIClient()
        client.credentials(HTTP_AUTHORIZATION=f"Bearer {RefreshToken.for_user(user).access_token}")
        return client


    def login(user, password=_PASSWORD):
        client = _JsonAPIClient()
        resp = client.post("/api/auth/login/",
                           {"email_or_phone": user.email, "password": password})
        assert resp.status_code == 200, resp.data
        client.credentials(HTTP_AUTHORIZATION=f"Bearer {resp.data['access']}")
        return client, resp.data


    def reset_code(user):
        note = Notification.objects.filter(
            recipient=user, type="SYSTEM", title="Password reset code"
        ).order_by("-created_at").first()
        assert note is not None
        return re.search(r"Your password reset code is ([^\s]+)", note.body).group(1)


    checks = []


    def check(name, cond):
        checks.append((name, bool(cond)))
        if not cond:
            print(f"  [x] {name}")


    # ---------------------------------------------------------------- §20 sessions
    patient = orm_user("PATIENT")
    c_patient, sess = login(patient)

    check("token_blacklist app installed",
          "rest_framework_simplejwt.token_blacklist" in
          __import__("django.conf", fromlist=["settings"]).settings.INSTALLED_APPS)

    out = c_patient.post("/api/auth/logout/", {"refresh": sess["refresh"]})
    check("logout 205 for a valid session", out.status_code == 205)
    check("logged-out refresh is dead",
          _JsonAPIClient().post("/api/auth/refresh/",
                                {"refresh": sess["refresh"]}).status_code == 401)

    _, sess2 = login(patient)
    rotated = _JsonAPIClient().post("/api/auth/refresh/", {"refresh": sess2["refresh"]})
    check("rotation issues a new pair", rotated.status_code == 200
          and "refresh" in rotated.data)
    check("rotated-away refresh is dead",
          _JsonAPIClient().post("/api/auth/refresh/",
                                {"refresh": sess2["refresh"]}).status_code == 401)

    _, sess3 = login(patient)
    changed = c_patient.post("/api/auth/password/change/",
                             {"current_password": _PASSWORD,
                              "new_password": _NEW_PASSWORD})
    check("password change 200", changed.status_code == 200)
    stale_access = _JsonAPIClient()
    stale_access.credentials(HTTP_AUTHORIZATION=f"Bearer {sess3['access']}")
    check("password change kills old access (rev-claim)",
          stale_access.get("/api/auth/me/").status_code == 401)
    check("password change kills old refresh (denylist)",
          _JsonAPIClient().post("/api/auth/refresh/",
                                {"refresh": sess3["refresh"]}).status_code == 401)
    check("new password signs in",
          _JsonAPIClient().post(
              "/api/auth/login/", {"email_or_phone": patient.email,
                                   "password": _NEW_PASSWORD}).status_code == 200)

    _, sess4 = login(patient, _NEW_PASSWORD)  # change + reset both set _NEW_PASSWORD
    _JsonAPIClient().post("/api/auth/password-reset/request/",
                          {"email_or_phone": patient.email})
    confirm = _JsonAPIClient().post("/api/auth/password-reset/confirm/",
                                    {"token": reset_code(patient),
                                     "new_password": _NEW_PASSWORD})
    check("password reset 200", confirm.status_code == 200)
    check("reset kills old refresh",
          _JsonAPIClient().post("/api/auth/refresh/",
                                {"refresh": sess4["refresh"]}).status_code == 401)
    check("reset restores new-password login",
          _JsonAPIClient().post(
              "/api/auth/login/", {"email_or_phone": patient.email,
                                   "password": _NEW_PASSWORD}).status_code == 200)

    target = orm_user("PATIENT")
    c_super = _client(orm_user("SUPER_ADMIN"))
    _, t_sess = login(target)
    susp = c_super.post(f"/api/admin/users/{target.uid}/deactivate/",
                        {"reason": "Abuse"})
    target.refresh_from_db()
    check("deactivate 200 + SUSPENDED + is_active=False",
          susp.status_code == 200 and target.account_status == "SUSPENDED"
          and target.is_active is False)
    t_stale = _JsonAPIClient()
    t_stale.credentials(HTTP_AUTHORIZATION=f"Bearer {t_sess['access']}")
    check("suspended user's access is dead",
          t_stale.get("/api/auth/me/").status_code == 401)
    check("suspended user's refresh is dead",
          _JsonAPIClient().post("/api/auth/refresh/",
                                {"refresh": t_sess["refresh"]}).status_code == 401)

    # ---------------------------------------------------------------- §25 policy
    weak_register = _JsonAPIClient().post(
        "/api/auth/register/",
        {"email": f"weak-{uuid.uuid4().hex[:8]}@example.com", "password": _WEAK_COMMON,
         "first_name": "T", "last_name": "T", "role_code": "PATIENT"})
    check("register rejects common password", weak_register.status_code == 400)
    num_register = _JsonAPIClient().post(
        "/api/auth/register/",
        {"email": f"num-{uuid.uuid4().hex[:8]}@example.com", "password": _WEAK_NUMERIC,
         "first_name": "T", "last_name": "T", "role_code": "PATIENT"})
    check("register rejects numeric password", num_register.status_code == 400)
    _JsonAPIClient().post("/api/auth/password-reset/request/",
                          {"email_or_phone": patient.email})
    weak_confirm = _JsonAPIClient().post(
        "/api/auth/password-reset/confirm/",
        {"token": reset_code(patient), "new_password": _WEAK_NUMERIC})
    check("reset-confirm rejects weak password", weak_confirm.status_code == 400)
    c_patient2, _ = login(patient, _NEW_PASSWORD)
    weak_change = c_patient2.post("/api/auth/password/change/",
                                  {"current_password": _NEW_PASSWORD,
                                   "new_password": _WEAK_COMMON})
    check("change-password rejects weak password", weak_change.status_code == 400)

    # ---------------------------------------------------------------- §26 reset oracle/cooldown
    before_events = SecurityEvent.objects.filter(event_type="PASSWORD_RESET").count()
    before_tokens = OneTimeToken.objects.filter(purpose="PASSWORD_RESET").count()
    ghost = _JsonAPIClient().post(
        "/api/auth/password-reset/request/",
        {"email_or_phone": f"ghost-{uuid.uuid4().hex}@example.com"})
    check("unknown account still gets uniform 202",
          ghost.status_code in (200, 202))
    check("unknown account mints nothing (no oracle)",
          SecurityEvent.objects.filter(event_type="PASSWORD_RESET").count() == before_events
          and OneTimeToken.objects.filter(purpose="PASSWORD_RESET").count() == before_tokens)
    probe = orm_user("PATIENT")
    _JsonAPIClient().post("/api/auth/password-reset/request/",
                          {"email_or_phone": probe.email})
    _JsonAPIClient().post("/api/auth/password-reset/request/",
                          {"email_or_phone": probe.email})
    check("cooldown caps reset-token issuance",
          OneTimeToken.objects.filter(user=probe, purpose="PASSWORD_RESET").count() == 1)

    # --------------------------------------------------------- §27 provider fail-closed
    with override_settings(PAYMENT_ENV="production",
                           PAYMENT_SECRET_KEY="dev-webhook-secret-not-for-production",
                           PAYMENT_PROVIDER_SECRETS={}):
        try:
            providers._secret("M_PESA")
            secret_refused = False
        except providers.ProviderConfigurationError:
            secret_refused = True
    check("production refuses to use dev webhook secret", secret_refused)
    with override_settings(PAYMENT_ENV="production",
                           PAYMENT_SECRET_KEY="dev-webhook-secret-not-for-production",
                           PAYMENT_PROVIDER_SECRETS={"M_PESA": "live-abc"}):
        check("production accepts per-provider live secret",
              providers._secret("M_PESA") == "live-abc")

    # Settings fail-closed (subprocess; cannot re-import in-process).
    env_pass = dict(os.environ, DJANGO_SETTINGS_MODULE="config.settings.production",
                    DJANGO_SECRET_KEY="a-unique-operator-secret",
                    PAYMENT_ENV="production", PAYMENT_PROVIDER_SECRET_M_PESA="live-abc")
    env_placeholder = dict(env_pass, DJANGO_SECRET_KEY="change-me-in-production")
    prod_ok = subprocess.run([sys.executable, "-c", "import django; django.setup()"],
                             cwd=os.path.dirname(os.path.abspath(__file__)),
                             env=env_pass, capture_output=True)
    prod_refused = subprocess.run([sys.executable, "-c", "import django; django.setup()"],
                                  cwd=os.path.dirname(os.path.abspath(__file__)),
                                  env=env_placeholder, capture_output=True)
    check("production settings import with real secret", prod_ok.returncode == 0)
    check("production settings refuse the SECRET_KEY placeholder",
          prod_refused.returncode != 0 and b"DJANGO_SECRET_KEY" in prod_refused.stderr)

    # ---------------------------------------------------------------- §28 MFA refund
    from decimal import Decimal
    from django.utils import timezone
    from donations.models import Campaign, CampaignStatus, Donation, DonationStatus

    campaign_owner = orm_user("SUPER_ADMIN")
    campaign = Campaign.objects.create(
        owner=campaign_owner, title="Surgery fund", description=".",
        goal_amount=Decimal("500000.00"), raised_amount=Decimal("0.00"),
        status=CampaignStatus.ACTIVE, verified_at=timezone.now())
    donation = Donation.objects.create(
        campaign=campaign, donor=orm_user("PATIENT"), amount=Decimal("10000.00"),
        status=DonationStatus.COMPLETED, idempotency_key=uuid.uuid4().hex,
        transaction_ref=uuid.uuid4().hex[:32])
    mfa_admin = orm_user("ADMIN", mfa_enabled=True)
    check("refund (money movement) honours MFA boundary",
          _client(mfa_admin).post(f"/api/admin/donations/{donation.uid}/refund/",
                                  {"reason": "duplicate"}).status_code == 403)
    check("refund allowed for non-step-up admin",
          _client(orm_user("ADMIN")).post(f"/api/admin/donations/{donation.uid}/refund/",
                                          {"reason": "duplicate"}).status_code == 201)

    # ---------------------------------------------------------------- §15 community
    post = c_patient2.post("/api/community/posts/",
                          {"title": "Need help", "content": "<p>body</p>"})
    assert post.status_code == 201, post.data
    uid = post.data["uid"]
    CommunityPost.objects.filter(uid=uid).update(status="HIDDEN",
                                                 moderation_reason="policy breach")
    mine = c_patient2.get(f"/api/community/posts/{uid}/")
    check("author sees post but NOT moderation_reason",
          mine.status_code == 200 and mine.data["moderation_reason"] is None)
    mod_view = _client(orm_user("MODERATOR")).get(f"/api/community/posts/{uid}/")
    check("moderator sees moderation_reason",
          mod_view.status_code == 200
          and mod_view.data["moderation_reason"] == "policy breach")
    other = orm_user("PATIENT")
    o_c, _ = login(other)
    check("HIDDEN post comment thread hidden from members",
          o_c.get(f"/api/community/posts/{uid}/comments/").status_code == 404)
    check("HIDDEN post comment thread visible to moderators",
          _client(orm_user("MODERATOR")).get(
              f"/api/community/posts/{uid}/comments/").status_code == 200)
    # Reactions are checked against a PUBLISHED post (reaction endpoint is
    # not intended to expose moderated threads).
    visible_post = c_patient2.post("/api/community/posts/",
                                   {"title": "Public note", "content": "<p>hi</p>"})
    assert visible_post.status_code == 201, visible_post.data
    uid_visible = visible_post.data["uid"]
    reject = o_c.post(f"/api/community/posts/{uid_visible}/reactions/",
                      {"reaction_type": "HEHE"})
    check("arbitrary reaction type rejected", reject.status_code == 400)
    like = o_c.post(f"/api/community/posts/{uid_visible}/reactions/",
                    {"reaction_type": "LIKE"})
    check("whitelisted reaction accepted", like.status_code == 200)

    # ---------------------------------------------------------------- §16 blood privacy
    donor_user = orm_user("BLOOD_DONOR")
    donor = BloodDonor.objects.create(user=donor_user, blood_group="O+",
                                      region="Greater Accra", city="Accra",
                                      is_verified=True, is_available=True)
    facility = Facility.objects.create(name="Clinic", facility_type="CLINIC",
                                       city="Accra", is_verified=True)
    req = c_patient2.post("/api/blood/requests/",
                         {"blood_group_needed": "O+", "units": 1, "urgency": "URGENT",
                          "facility_uid": str(facility.uid),
                          "location": {"region": "Greater Accra", "city": "Accra"}})
    assert req.status_code == 201, req.data
    req_uid = req.data["uid"]
    _client(orm_user("VERIFICATION_OFFICER")).post(
        f"/api/admin/blood/requests/{req_uid}/verify/", {})
    donor_list = _client(donor_user).get("/api/blood/requests/")
    row = next(r for r in donor_list.data["results"] if r["uid"] == req_uid)
    check("donor-facing request list is PII-free",
          not any(k in row for k in ("creator_email", "created_by",
                                     "rejection_reason", "idempotency_key"))
          and "blood_group_needed" in row)
    request_obj = BloodRequest.objects.get(uid=req_uid)
    ev = {"donor_id": donor.pk, "facility_uid": str(facility.uid), "units": 1,
          "donated_at": timezone.now().isoformat(), "outcome": "COMPLETED"}
    staff = _client(orm_user("HEALTHCARE_STAFF"))
    check("COMPLETED donation without accepted match blocked",
          staff.post(f"/api/blood/requests/{req_uid}/donation-events/", ev).status_code == 400)
    BloodMatch.objects.create(request=request_obj, donor=donor, status="ACCEPTED")
    check("COMPLETED donation with accepted match recorded",
          staff.post(f"/api/blood/requests/{req_uid}/donation-events/", ev).status_code == 201)

    # ---------------------------------------------------------------- §18 emergencies
    emg = c_patient2.post("/api/emergency/requests/",
                         {"severity": "CRITICAL", "type": "PAIN_CRISIS",
                          "location": {"region": "Greater Accra", "city": "Accra"},
                          "description": "severe pain", "phone_verified": True})
    from emergencies.models import EmergencyRequest
    check("client cannot self-assert phone_verified",
          emg.status_code == 201
          and EmergencyRequest.objects.get(uid=emg.data["uid"]).phone_verified is False)

    # ---------------------------------------------------------------- §33 schema/docs
    check("schema 404 for regular member",
          o_c.get("/api/schema/").status_code == 404)
    check("schema 404 when anonymous",
          APIClient().get("/api/schema/").status_code == 404)
    check("schema 200 for audit reader (SUPER_ADMIN)",
          c_super.get("/api/schema/").status_code == 200)
    check("swagger UI 200 for audit reader",
          c_super.get("/api/docs/").status_code == 200)
    with override_settings(DEBUG=True):
        check("schema open when DEBUG",
              APIClient().get("/api/schema/").status_code == 200)

    # ---------------------------------------------------------------- §26 correlation id
    r = APIClient().get("/api/schema/", HTTP_X_CORRELATION_ID="bad\ninjection")
    check("hostile correlation header replaced",
          r.status_code == 404 and re.fullmatch(r"[0-9a-f]{16}", r.headers["X-Correlation-ID"]))
    r = APIClient().get("/api/schema/", HTTP_X_CORRELATION_ID="trace-a_1.b-cdef")
    check("valid correlation header kept",
          r.headers["X-Correlation-ID"] == "trace-a_1.b-cdef")

    ok = len(checks) == sum(1 for _, passed in checks if passed)
finally:
    runner.teardown_databases(old_config)

print(f"Stage 4.17 gate: {sum(1 for _, p in checks if p)}/{len(checks)} checks passed")
for name, passed in checks:
    if not passed:
        print(f"  FAILED: {name}")
print("GATE_OK" if ok else "GATE_FAILED")
raise SystemExit(0 if ok else 1)