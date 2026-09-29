"""AUTH-2 — public signup, email verification & role-verification surface.

Covers the public authentication experience the mobile app (Stage 4.22)
relies on, without duplicating the Stage 4.17/4.19 suites:

* Register always issues a hashed EMAIL_VERIFY one-time code + JWT pair; the
  account stays PENDING_VERIFICATION until the code is consumed.
* POST /auth/verify/email — happy path, invalid, expired, already-verified.
* POST /auth/verify/email/resend — uniform 202 (no enumeration), cooldown
  cap, never re-issues for active accounts.
* Login/me surface the account status + doctor/facility verification so the
  client can route a PENDING doctor / unverified organisation correctly.
* Account type is never verification: a newly registered self-registerable
  role is PENDING_VERIFICATION; DOCTOR/HOSPITAL privileges are never granted
  by registration.
"""

from django.test import TestCase
from django.utils import timezone

from accounts.models import OneTimeToken, SecurityEvent, User
from doctors.models import Doctor
from notifications.models import Notification

from . import qa_helpers as h


def _delivered_code(user):
    """Raw one-time code the dev delivery channel put into the last SYSTEM
    notification (test-only helper; production only ever hashes it)."""
    n = h.last_notification(user)
    assert n is not None, "no delivery notification present"
    body = n.body or ""
    return body.split("is ")[1].split(" (expires")[0]


class RegisterIssuesEmailVerificationTests(TestCase):
    def test_register_returns_code_and_stays_pending_until_verified(self):
        c, resp = h.register("PATIENT")
        self.assertEqual(resp.status_code, 201, resp.data)
        self.assertTrue(resp.data["email_verification_pending"])
        self.assertIsNotNone(resp.data["verify_token"])
        self.assertEqual(resp.data["user"]["account_status"], "PENDING_VERIFICATION")
        user = User.objects.get(email=resp.data["user"]["email"])
        self.assertTrue(
            OneTimeToken.objects.filter(
                user=user, purpose="EMAIL_VERIFY", used_at__isnull=True
            ).exists()
        )
        self.assertTrue(
            SecurityEvent.objects.filter(user=user, event_type="REGISTER").exists()
        )
        self.assertTrue(
            SecurityEvent.objects.filter(
                user=user, event_type="EMAIL_VERIFY_ISSUED"
            ).exists()
        )
        self.assertIsNotNone(h.last_notification(user, "SYSTEM"))

    def test_token_is_stored_hashed_never_raw(self):
        _, resp = h.register("PATIENT")
        raw = resp.data["verify_token"]
        self.assertIsNotNone(raw)
        # No stored token may ever contain the raw code.
        self.assertFalse(
            OneTimeToken.objects.filter(token_hash=raw).exists()
        )
        self.assertFalse(
            list(OneTimeToken.objects.values_list("token_hash", flat=True)).__contains__(raw)
        )

    def test_self_registration_never_grants_privileged_roles(self):
        for role in ("DOCTOR", "HOSPITAL", "BLOOD_DONOR", "ADMIN", "SUPER_ADMIN"):
            _, resp = h.register(role)
            self.assertIn(resp.status_code, (400, 201), role)
            if resp.status_code == 201:
                created = resp.data["user"]["role_codes"]
                self.assertNotIn("DOCTOR", created)
                self.assertNotIn("ADMIN", created)
                self.assertNotIn("HOSPITAL", created)


class VerifyEmailTests(TestCase):
    def _register(self):
        c, resp = h.register("PATIENT")
        return resp.data["verify_token"], resp.data["user"]["email"]

    def test_verify_promotes_account_to_active(self):
        token, email = self._register()
        user = User.objects.get(email=email)
        resp = h.APIClient().post(
            "/api/auth/verify/email/", {"token": token}, format="json"
        )
        self.assertEqual(resp.status_code, 204)
        user.refresh_from_db()
        self.assertEqual(user.account_status, "ACTIVE")
        self.assertTrue(
            SecurityEvent.objects.filter(user=user, event_type="EMAIL_VERIFIED").exists()
        )
        # Single-use: the same code is rejected afterwards.
        again = h.APIClient().post(
            "/api/auth/verify/email/", {"token": token}, format="json"
        )
        self.assertIn(again.status_code, (400, 404))

    def test_invalid_code_is_rejected_uniformly(self):
        resp = h.APIClient().post(
            "/api/auth/verify/email/", {"token": "not-a-real-code"}, format="json"
        )
        self.assertEqual(resp.status_code, 400)

    def test_expired_code_is_rejected(self):
        _, resp = h.register("PATIENT")
        token = resp.data["verify_token"]
        OneTimeToken.objects.filter(purpose="EMAIL_VERIFY").update(
            expires_at=timezone.now() - timezone.timedelta(minutes=1)
        )
        out = h.APIClient().post(
            "/api/auth/verify/email/", {"token": token}, format="json"
        )
        self.assertIn(out.status_code, (400, 404))

    def test_verify_is_idempotent_for_already_active_account(self):
        token, _email = self._register()
        fresh = h.APIClient().post(
            "/api/auth/verify/email/", {"token": token}, format="json"
        )
        self.assertEqual(fresh.status_code, 204)
        # A brand-new code on an already-ACTIVE account still resolves 204.
        _c, resp = h.register("PATIENT")
        token2 = resp.data["verify_token"]
        self.assertEqual(
            h.APIClient().post("/api/auth/verify/email/", {"token": token2}, format="json").status_code,
            204,
        )


class EmailVerifyResendTests(TestCase):
    def test_resend_is_uniform_and_does_not_enumerate(self):
        c = h.APIClient()
        known = h.APIClient().post(
            "/api/auth/register/",
            {
                "email": "resend-known@example.com",
                "password": h._PASSWORD,
                "role_code": "PATIENT",
            },
            format="json",
        )
        self.assertEqual(known.status_code, 201)
        user = User.objects.get(email="resend-known@example.com")
        before = OneTimeToken.objects.filter(user=user, purpose="EMAIL_VERIFY", used_at__isnull=True).count()

        unknown = c.post(
            "/api/auth/verify/email/resend/", {"email": "ghost@example.com"}, format="json"
        )
        known_resp = c.post(
            "/api/auth/verify/email/resend/", {"email": "resend-known@example.com"}, format="json"
        )
        self.assertEqual(unknown.status_code, 202)
        self.assertEqual(known_resp.status_code, 202)
        # Cooldown: the register-issued code is still fresh, so no spam re-issue.
        self.assertEqual(
            OneTimeToken.objects.filter(user=user, purpose="EMAIL_VERIFY", used_at__isnull=True).count(),
            before,
        )

    def test_resend_issues_a_fresh_code_once_the_previous_has_expired(self):
        c = h.APIClient()
        c.post(
            "/api/auth/register/",
            {
                "email": "cooldown@example.com",
                "password": h._PASSWORD,
                "role_code": "PATIENT",
            },
            format="json",
        )
        user = User.objects.get(email="cooldown@example.com")
        live = lambda: OneTimeToken.objects.filter(  # noqa: E731 - test-only count
            user=user, purpose="EMAIL_VERIFY", used_at__isnull=True, expires_at__gt=timezone.now()
        ).count()
        # Let the register-issued code expire, then resend issues a new one.
        OneTimeToken.objects.filter(user=user, purpose="EMAIL_VERIFY").update(
            expires_at=timezone.now() - timezone.timedelta(minutes=1)
        )
        first = c.post("/api/auth/verify/email/resend/", {"email": "cooldown@example.com"}, format="json")
        self.assertEqual(first.status_code, 202)
        self.assertEqual(live(), 1)
        # Immediate second resend stays inside the cooldown window.
        second = c.post("/api/auth/verify/email/resend/", {"email": "cooldown@example.com"}, format="json")
        self.assertEqual(second.status_code, 202)
        self.assertEqual(live(), 1)

    def test_resend_never_issues_for_an_active_account(self):
        c, resp = h.register("PATIENT")
        user = User.objects.get(email=resp.data["user"]["email"])
        c = h.APIClient()
        c.post("/api/auth/verify/email/", {"token": resp.data["verify_token"]}, format="json")
        user.refresh_from_db()
        self.assertEqual(user.account_status, "ACTIVE")
        before = OneTimeToken.objects.filter(user=user, purpose="EMAIL_VERIFY").count()
        out = c.post("/api/auth/verify/email/resend/", {"email": user.email}, format="json")
        self.assertEqual(out.status_code, 202)
        self.assertEqual(
            OneTimeToken.objects.filter(user=user, purpose="EMAIL_VERIFY").count(), before
        )


class VerificationStatusSurfaceTests(TestCase):
    def test_pending_doctor_is_surfaced_not_verified(self):
        doctor = h.orm_user("DOCTOR")
        Doctor.objects.create(user=doctor, verification_status="PENDING")
        me = h.client(doctor).get("/api/auth/me/")
        self.assertEqual(me.status_code, 200)
        self.assertEqual(me.data["doctor_verification_status"], "PENDING")
        self.assertFalse(me.data["is_verified_doctor"])

    def test_approved_doctor_is_surfaced_verified(self):
        doctor = h.orm_user("DOCTOR")
        Doctor.objects.create(user=doctor, verification_status="APPROVED")
        me = h.client(doctor).get("/api/auth/me/")
        self.assertEqual(me.data["doctor_verification_status"], "APPROVED")
        self.assertTrue(me.data["is_verified_doctor"])

    def test_non_doctor_is_never_surfaced_with_doctor_state(self):
        patient = h.orm_user("PATIENT")
        me = h.client(patient).get("/api/auth/me/")
        self.assertIsNone(me.data["doctor_verification_status"])
        self.assertFalse(me.data["is_verified_doctor"])

    def test_hospital_operator_exposes_facility_verification(self):
        operator = h.orm_user("HOSPITAL")
        fac = h.facility(name="County Hospital", facility_type="HOSPITAL", verified=False)
        fac.operator = operator
        fac.save(update_fields=["operator"])
        me = h.client(operator).get("/api/auth/me/")
        self.assertEqual(me.data["account_status"], "ACTIVE")
        self.assertEqual(me.data["facility"]["name"], "County Hospital")
        self.assertEqual(me.data["facility"]["facility_type"], "HOSPITAL")
        self.assertFalse(me.data["facility"]["is_verified"])


class LoginStatusSurfaceTests(TestCase):
    def test_login_returns_pending_status_for_unverified_account(self):
        _c, resp = h.register("PATIENT")
        user = User.objects.get(email=resp.data["user"]["email"])
        self.assertEqual(
            OneTimeToken.objects.filter(user=user, purpose="EMAIL_VERIFY").exists(), True
        )
        login = h.APIClient().post(
            "/api/auth/login/",
            {"email_or_phone": user.email, "password": h._PASSWORD},
            format="json",
        )
        self.assertEqual(login.status_code, 200)
        self.assertEqual(login.data["user"]["account_status"], "PENDING_VERIFICATION")
        self.assertEqual(login.data["user"]["role_codes"], ["PATIENT"])