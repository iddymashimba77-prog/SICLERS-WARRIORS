"""Stage 4.17 security-hardening regression suite.

Runs REAL endpoints end-to-end so the hardening changes from this stage are
proven, not just asserted at the unit level. Deliberately cross-app, hence its
own app (``security_hardening``) so ``manage.py test`` discovers it.

Coverage by finding:

  §20 session lifecycle — logout invalidates refresh; rotation denylists the
      old refresh; password change/reset revokes every outstanding session
      (denylist + rev-claim) including login-issued tokens; suspension kills
      the live session (is_active flips too, not just account_status).
  §25 password policy   — weak passwords rejected at register, reset-confirm
      and change-password; strong passwords still accepted.
  §26 reset oracle/cooldown — unknown account still 202/200 (no 500, uniform),
      no SecurityEvent/one-time token minted for unknown accounts, and a
      second request within the cooldown window does NOT mint another token.
  §27 provider fail-closed — production payment env refuses the shared/dev
      webhook secret and requires a per-provider secret.
  §28 privileges         — refund (money movement) now honours the MFA boundary.
  §15 community          — moderation_reason is moderation-only; comment thread
      of a HIDDEN post is 404 for regular members; arbitrary reaction types 400.
  §16 blood privacy      — donor-facing request list uses the public subset
      (no requester contact / rejection internals); COMPLETED donation events
      require an ACCEPTED/FULFILLED match (chain of custody).
  §18 emergencies        — callers cannot self-assert phone_verified on create.
  §26 correlation id     — hostile X-Correlation-ID is replaced, valid one kept.
  §33 schema/docs gate   — schema JSON + Swagger UI are 404 for non-privileged
      users when DEBUG is off; open in DEBUG; allowed for audit readers.
"""

import re
import uuid as _uuid

from django.conf import settings
from django.core.cache import cache
from django.test import TestCase, override_settings
from django.utils import timezone
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


class _JsonAPIClient(APIClient):
    def _json(self, kwargs):
        kwargs.setdefault("format", "json")

    def post(self, *args, **kwargs):
        self._json(kwargs)
        return super().post(*args, **kwargs)

    def patch(self, *args, **kwargs):
        self._json(kwargs)
        return super().patch(*args, **kwargs)


def _client(user):
    client = _JsonAPIClient()
    client.credentials(HTTP_AUTHORIZATION=f"Bearer {RefreshToken.for_user(user).access_token}")
    return client


def _login(user):
    client = _JsonAPIClient()
    resp = client.post(
        "/api/auth/login/", {"email_or_phone": user.email, "password": _PASSWORD}
    )
    assert resp.status_code == 200, resp.data
    client.credentials(HTTP_AUTHORIZATION=f"Bearer {resp.data['access']}")
    return client, resp


class SessionRevocationTests(TestCase):
    """§20 — logout / rotation / password-change / suspension kill sessions."""

    def setUp(self):
        cache.clear()
        self.patient = _orm_user("PATIENT")
        self.super = _orm_user("SUPER_ADMIN")
        self.super_client = _client(self.super)

    def test_logout_blacklists_refresh_token(self):
        client, resp = _login(self.patient)
        refresh = resp.data["refresh"]
        out = client.post("/api/auth/logout/", {"refresh": refresh})
        self.assertEqual(out.status_code, 205)
        for _ in range(2):
            again = _JsonAPIClient().post("/api/auth/refresh/", {"refresh": refresh})
            self.assertEqual(again.status_code, 401)

    def test_rotation_denylists_old_refresh(self):
        _, resp = _login(self.patient)
        old_refresh = resp.data["refresh"]
        rotated = _JsonAPIClient().post("/api/auth/refresh/", {"refresh": old_refresh})
        self.assertEqual(rotated.status_code, 200)
        self.assertIn("refresh", rotated.data)
        reuse = _JsonAPIClient().post("/api/auth/refresh/", {"refresh": old_refresh})
        self.assertEqual(reuse.status_code, 401)

    def test_password_change_revokes_all_sessions(self):
        client, resp = _login(self.patient)
        old_access = resp.data["access"]
        old_refresh = resp.data["refresh"]
        changed = client.post(
            "/api/auth/password/change/",
            {"current_password": _PASSWORD, "new_password": _NEW_PASSWORD},
        )
        self.assertEqual(changed.status_code, 200, changed.data)
        # Previously issued access is dead (rev-claim)…
        stale_access = _JsonAPIClient()
        stale_access.credentials(HTTP_AUTHORIZATION=f"Bearer {old_access}")
        self.assertEqual(stale_access.get("/api/auth/me/").status_code, 401)
        # …and the previously issued refresh is denylisted (outstanding revoked).
        self.assertEqual(
            _JsonAPIClient().post("/api/auth/refresh/", {"refresh": old_refresh}).status_code,
            401,
        )
        # Fresh sign-in with the new password works.
        login2 = _JsonAPIClient().post(
            "/api/auth/login/", {"email_or_phone": self.patient.email, "password": _NEW_PASSWORD}
        )
        self.assertEqual(login2.status_code, 200)

    def test_suspension_blocks_live_session_and_refresh(self):
        client, resp = _login(self.patient)
        target_uid = str(self.patient.uid)
        suspended = self.super_client.post(
            f"/api/admin/users/{target_uid}/deactivate/", {"reason": "Abuse"}
        )
        self.assertEqual(suspended.status_code, 200)
        self.patient.refresh_from_db()
        self.assertFalse(self.patient.is_active)
        self.assertEqual(self.patient.account_status, "SUSPENDED")
        self.assertEqual(client.get("/api/auth/me/").status_code, 401)
        self.assertEqual(
            _JsonAPIClient().post("/api/auth/refresh/", {"refresh": resp.data["refresh"]}).status_code,
            401,
        )


class PasswordPolicyTests(TestCase):
    """§25 — Django password validators now run at every entry point."""

    def setUp(self):
        cache.clear()
        self.client = _JsonAPIClient()

    def _register(self, password):
        return self.client.post(
            "/api/auth/register/",
            {
                "email": f"pw-{_uuid.uuid4().hex[:10]}@example.com",
                "password": password,
                "first_name": "Test",
                "last_name": "User",
                "role_code": "PATIENT",
            },
        )

    def test_register_rejects_common_password(self):
        self.assertEqual(self._register(_WEAK_COMMON).status_code, 400)

    def test_register_rejects_numeric_password(self):
        self.assertEqual(self._register(_WEAK_NUMERIC).status_code, 400)

    def test_register_accepts_strong_password(self):
        self.assertEqual(self._register(_PASSWORD).status_code, 201)

    def test_change_password_rejects_weak(self):
        patient = _orm_user("PATIENT")
        client, _ = _login(patient)
        resp = client.post(
            "/api/auth/password/change/",
            {"current_password": _PASSWORD, "new_password": _WEAK_COMMON},
        )
        self.assertEqual(resp.status_code, 400)

    def test_reset_confirm_rejects_weak(self):
        patient = _orm_user("PATIENT")
        req = _JsonAPIClient().post(
            "/api/auth/password-reset/request/", {"email_or_phone": patient.email}
        )
        self.assertEqual(req.status_code, 202)
        code = _extract_reset_code(patient)
        resp = _JsonAPIClient().post(
            "/api/auth/password-reset/confirm/",
            {"token": code, "new_password": _WEAK_NUMERIC},
        )
        self.assertEqual(resp.status_code, 400)


def _extract_reset_code(user):
    note = Notification.objects.filter(
        recipient=user, type="SYSTEM", title="Password reset code"
    ).order_by("-created_at").first()
    assert note is not None, "no reset notification delivered"
    match = re.search(r"Your password reset code is ([^\s]+)", note.body)
    assert match, note.body
    return match.group(1)


class PasswordResetOracleTests(TestCase):
    """§26 — uniform 202, no existence oracle, cooldown caps token issuance."""

    def setUp(self):
        cache.clear()
        self.patient = _orm_user("PATIENT")
        self.client = _JsonAPIClient()

    def test_unknown_account_gets_uniform_202_no_side_effects(self):
        resp = self.client.post(
            "/api/auth/password-reset/request/",
            {"email_or_phone": f"nobody-{_uuid.uuid4().hex}@example.com"},
        )
        self.assertEqual(resp.status_code, 202)
        self.assertEqual(
            SecurityEvent.objects.filter(event_type="PASSWORD_RESET").count(), 0
        )
        self.assertEqual(OneTimeToken.objects.filter(purpose="PASSWORD_RESET").count(), 0)

    def test_known_account_gets_202_code_and_cooldown(self):
        first = self.client.post(
            "/api/auth/password-reset/request/", {"email_or_phone": self.patient.email}
        )
        self.assertEqual(first.status_code, 202)
        self.assertEqual(OneTimeToken.objects.filter(purpose="PASSWORD_RESET").count(), 1)
        self.assertEqual(
            SecurityEvent.objects.filter(event_type="PASSWORD_RESET").count(), 1
        )
        # Second (abusive) request inside the cooldown window issues NOTHING new.
        again = self.client.post(
            "/api/auth/password-reset/request/", {"email_or_phone": self.patient.email}
        )
        self.assertEqual(again.status_code, 202)
        self.assertEqual(OneTimeToken.objects.filter(purpose="PASSWORD_RESET").count(), 1)

    def test_reset_flow_works_and_revokes_old_session(self):
        _, resp = _login(self.patient)
        old_refresh = resp.data["refresh"]
        self.client.post(
            "/api/auth/password-reset/request/", {"email_or_phone": self.patient.email}
        )
        code = _extract_reset_code(self.patient)
        confirm = _JsonAPIClient().post(
            "/api/auth/password-reset/confirm/",
            {"token": code, "new_password": _NEW_PASSWORD},
        )
        self.assertEqual(confirm.status_code, 200, confirm.data)
        self.patient.refresh_from_db()
        self.assertTrue(self.patient.check_password(_NEW_PASSWORD))
        # Old session cannot be replayed after a reset.
        self.assertEqual(
            _JsonAPIClient().post("/api/auth/refresh/", {"refresh": old_refresh}).status_code,
            401,
        )


class PaymentSecretsTests(TestCase):
    """§27 — webhook secrets fail closed in the production payment env."""

    def test_production_requires_per_provider_secret(self):
        with override_settings(
            PAYMENT_ENV="production",
            PAYMENT_SECRET_KEY="dev-webhook-secret-not-for-production",
            PAYMENT_PROVIDER_SECRETS={},
        ):
            with self.assertRaises(providers.ProviderConfigurationError):
                providers._secret("M_PESA")

    def test_production_refuses_shared_dev_secret(self):
        with override_settings(
            PAYMENT_ENV="production",
            PAYMENT_PROVIDER_SECRETS={"M_PESA": "dev-webhook-secret-not-for-production"},
        ):
            with self.assertRaises(providers.ProviderConfigurationError):
                providers._secret("M_PESA")

    def test_production_accepts_real_per_provider_secret(self):
        with override_settings(
            PAYMENT_ENV="production",
            PAYMENT_PROVIDER_SECRETS={"M_PESA": "live-secret-abc123"},
        ):
            self.assertEqual(providers._secret("M_PESA"), "live-secret-abc123")


class PrivilegedMfaTests(TestCase):
    """§28 — refund access honours the MFA step-up boundary."""

    def _donation(self):
        from decimal import Decimal

        from donations.models import Campaign, CampaignStatus, Donation, DonationStatus

        super_user = _orm_user("SUPER_ADMIN")
        campaign = Campaign.objects.create(
            owner=super_user, title="Help fund surgery", description=".",
            goal_amount=Decimal("500000.00"), raised_amount=Decimal("0.00"),
            status=CampaignStatus.ACTIVE, verified_at=timezone.now(),
        )
        donor = _orm_user("PATIENT")
        return Donation.objects.create(
            campaign=campaign, donor=donor, amount=Decimal("10000.00"),
            status=DonationStatus.COMPLETED, idempotency_key=_uuid.uuid4().hex,
            transaction_ref=_uuid.uuid4().hex[:32],
        )

    def test_refund_denied_for_regular_admin_with_mfa(self):
        from donations.models import Donation

        donation = self._donation()
        mfa_admin = _orm_user("ADMIN", mfa_enabled=True)
        resp = _client(mfa_admin).post(
            f"/api/admin/donations/{donation.uid}/refund/", {"reason": "Duplicate charge"}
        )
        self.assertEqual(resp.status_code, 403)
        Donation.objects.get(pk=donation.pk)

    def test_refund_allowed_for_admin_without_mfa(self):
        donation = self._donation()
        admin = _orm_user("ADMIN", mfa_enabled=False)
        resp = _client(admin).post(
            f"/api/admin/donations/{donation.uid}/refund/", {"reason": "Duplicate charge"}
        )
        self.assertEqual(resp.status_code, 201, resp.data)

    def test_refund_denied_for_patient(self):
        donation = self._donation()
        patient = _orm_user("PATIENT")
        resp = _client(patient).post(
            f"/api/admin/donations/{donation.uid}/refund/", {"reason": "Duplicate charge"}
        )
        self.assertEqual(resp.status_code, 403)


class CommunityHardeningTests(TestCase):
    """§15 — moderation internals, hidden-thread reads, reaction whitelist."""

    def setUp(self):
        cache.clear()
        self.patient, self.patient_user = _register_via_api("PATIENT")
        self.other, self.other_user = _register_via_api("PATIENT")
        self.moderator = _client(_orm_user("MODERATOR"))

    def _post(self, client=None, **overrides):
        body = {"title": "Help needed", "content": "<p>body</p>", **overrides}
        return (client or self.patient).post("/api/community/posts/", body)

    def test_moderation_reason_visible_only_to_moderators(self):
        uid = self._post().data["uid"]
        CommunityPost.objects.filter(uid=uid).update(
            status="HIDDEN", moderation_reason="policy breach"
        )
        # Author (regular member) sees their post but not WHY it was moderated.
        mine = self.patient.get(f"/api/community/posts/{uid}/")
        self.assertEqual(mine.status_code, 200)
        self.assertIsNone(mine.data["moderation_reason"])
        # A moderator sees the moderation reason.
        mod_view = self.moderator.get(f"/api/community/posts/{uid}/")
        self.assertEqual(mod_view.status_code, 200)
        self.assertEqual(mod_view.data["moderation_reason"], "policy breach")

    def test_comment_thread_of_hidden_post_hidden_from_members(self):
        uid = self._post().data["uid"]
        Comment.objects.create(
            post=CommunityPost.objects.get(uid=uid), author=self.patient_user, content="public comment"
        )
        CommunityPost.objects.filter(uid=uid).update(status="HIDDEN")
        self.assertEqual(self.other.get(f"/api/community/posts/{uid}/comments/").status_code, 404)
        self.assertEqual(self.moderator.get(f"/api/community/posts/{uid}/comments/").status_code, 200)

    def test_reaction_type_whitelist(self):
        uid = self._post().data["uid"]
        bad = self.patient.post(
            f"/api/community/posts/{uid}/reactions/", {"reaction_type": "HEHE"}
        )
        self.assertEqual(bad.status_code, 400)
        ok = self.patient.post(
            f"/api/community/posts/{uid}/reactions/", {"reaction_type": "LIKE"}
        )
        self.assertEqual(ok.status_code, 200)


def _register_via_api(role, email=None):
    client = _JsonAPIClient()
    resp = client.post(
        "/api/auth/register/",
        {
            "email": email or f"{role.lower()}-{_uuid.uuid4().hex[:10]}@example.com",
            "password": _PASSWORD,
            "first_name": "Test",
            "last_name": "User",
            "role_code": role,
        },
    )
    user = User.objects.get(uid=resp.data["user"]["uid"])
    client.credentials(HTTP_AUTHORIZATION=f"Bearer {resp.data['access']}")
    return client, user


class BloodPrivacyTests(TestCase):
    """§16 — donor-facing list is PII-free; donation events need an accepted match."""

    def setUp(self):
        cache.clear()
        self.patient, self.patient_user = _register_via_api("PATIENT")
        self.donor_user = _orm_user("BLOOD_DONOR")
        self.donor = BloodDonor.objects.create(
            user=self.donor_user, blood_group="O+", region="Greater Accra",
            city="Accra", is_available=True, is_verified=True,
        )
        self.vo = _client(_orm_user("VERIFICATION_OFFICER"))
        self.staff = _client(_orm_user("HEALTHCARE_STAFF"))
        self.facility = Facility.objects.create(
            name="Test Clinic", facility_type="CLINIC", city="Accra", is_verified=True,
        )
        self.payload = {
            "blood_group_needed": "O+",
            "units": 1,
            "urgency": "URGENT",
            "facility_uid": str(self.facility.uid),
            "location": {"region": "Greater Accra", "city": "Accra"},
        }

    def _verified_request(self):
        created = self.patient.post("/api/blood/requests/", self.payload)
        assert created.status_code == 201, created.data
        self.vo.post(f"/api/admin/blood/requests/{created.data['uid']}/verify/")
        return created.data["uid"]

    def test_donor_list_uses_public_subset(self):
        uid = self._verified_request()
        listing = _client(self.donor_user).get("/api/blood/requests/")
        self.assertEqual(listing.status_code, 200)
        row = next(r for r in listing.data["results"] if r["uid"] == uid)
        for forbidden in ("creator_email", "created_by", "rejection_reason", "idempotency_key"):
            self.assertNotIn(forbidden, row)
        self.assertIn("blood_group_needed", row)

    def test_completed_donation_requires_accepted_match(self):
        uid = self._verified_request()
        request_obj = BloodRequest.objects.get(uid=uid)
        payload = {
            "donor_id": self.donor.pk,
            "facility_uid": str(self.facility.uid),
            "units": 1,
            "donated_at": timezone.now().isoformat(),
            "outcome": "COMPLETED",
        }
        without_match = self.staff.post(f"/api/blood/requests/{uid}/donation-events/", payload)
        self.assertEqual(without_match.status_code, 400)
        BloodMatch.objects.create(request=request_obj, donor=self.donor, status="ACCEPTED")
        with_match = self.staff.post(f"/api/blood/requests/{uid}/donation-events/", payload)
        self.assertEqual(with_match.status_code, 201, with_match.data)


class EmergencyPhoneVerifiedTests(TestCase):
    """§18 — clients cannot self-assert phone_verified on emergency creation."""

    def setUp(self):
        cache.clear()
        self.patient, self.patient_user = _register_via_api("PATIENT")

    def test_phone_verified_is_not_client_settable(self):
        from emergencies.models import EmergencyRequest

        resp = self.patient.post(
            "/api/emergency/requests/",
            {
                "severity": "CRITICAL",
                "type": "PAIN_CRISIS",
                "location": {"region": "Greater Accra", "city": "Accra"},
                "description": "severe pain",
                "phone_verified": True,
            },
        )
        self.assertEqual(resp.status_code, 201, resp.data)
        emergency = EmergencyRequest.objects.get(uid=resp.data["uid"])
        self.assertIs(emergency.phone_verified, False)


class SchemaGateTests(TestCase):
    """§33 — schema JSON + Swagger UI are privileged; DEBUG opens them."""

    def setUp(self):
        cache.clear()

    def test_schema_hidden_for_non_privileged_and_anon(self):
        patient = _orm_user("PATIENT")
        self.assertEqual(_client(patient).get("/api/schema/").status_code, 404)
        self.assertEqual(_client(patient).get("/api/docs/").status_code, 404)
        # Anonymous visitors get the same silent 404 (no existence probe).
        self.assertEqual(APIClient().get("/api/schema/").status_code, 404)

    def test_schema_visible_to_audit_readers(self):
        admin = _orm_user("SUPER_ADMIN")
        self.assertEqual(_client(admin).get("/api/schema/").status_code, 200)
        self.assertEqual(_client(admin).get("/api/docs/").status_code, 200)

    def test_schema_open_when_debug(self):
        with override_settings(DEBUG=True):
            self.assertEqual(APIClient().get("/api/schema/").status_code, 200)


class CorrelationIdTests(TestCase):
    """§26 — hostile correlation headers are replaced, valid ones kept."""

    def test_invalid_header_replaced(self):
        client = APIClient()
        client.credentials(HTTP_X_CORRELATION_ID="injection\n%0dSet-Cookie:bad")
        resp = client.get("/api/schema/")
        self.assertIn("X-Correlation-ID", resp)
        value = resp["X-Correlation-ID"]
        self.assertRegex(value, r"^[0-9a-f]{16}$")

    def test_valid_header_kept(self):
        client = APIClient()
        client.credentials(HTTP_X_CORRELATION_ID="trace-a_1.b-cdef")
        resp = client.get("/api/schema/")
        self.assertEqual(resp["X-Correlation-ID"], "trace-a_1.b-cdef")