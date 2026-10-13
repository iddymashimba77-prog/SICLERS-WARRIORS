"""AUTH-2 — public signup, login-PIN & role-verification surface.

Covers the public authentication experience the mobile app relies on, without
duplicating the Stage 4.17/4.19 suites:

* Register issues an identity-bound JWT pair and lands a usable ACTIVE account
  immediately (there is no email-verification step).
* POST /auth/pin/set (authenticated) configures a hashed 4-digit login PIN.
* POST /auth/pin/login signs in a device-remembered identity with the PIN.
* Login/me surface the account status + doctor/facility verification so the
  client can route a PENDING doctor / unverified organisation correctly.
* Genuinely administrative roles (ADMIN / SUPER_ADMIN) are never grantable
  through registration, while professional and facility roles land in the C5
  verification pipeline.
"""

from django.contrib.auth.hashers import check_password
from django.test import TestCase

from accounts.models import OneTimeToken, SecurityEvent, User

from . import qa_helpers as h


class RegisterActivatesAccountTests(TestCase):
    def test_register_activates_account_without_email_verification(self):
        c, resp = h.register("PATIENT")
        self.assertEqual(resp.status_code, 201, resp.data)
        # The response no longer carries any email-verification material.
        self.assertNotIn("email_verification_pending", resp.data)
        self.assertNotIn("verify_token", resp.data)
        self.assertEqual(resp.data["user"]["account_status"], "ACTIVE")
        self.assertIs(resp.data["user"]["has_login_pin"], False)
        user = User.objects.get(email=resp.data["user"]["email"])
        self.assertEqual(user.account_status, "ACTIVE")
        self.assertFalse(
            OneTimeToken.objects.filter(user=user, purpose="EMAIL_VERIFY").exists()
        )
        self.assertTrue(
            SecurityEvent.objects.filter(user=user, event_type="REGISTER").exists()
        )

    def test_self_registration_never_grants_privileged_roles(self):
        """Open registration grants care/facility/donor roles, never admin ones."""
        for role in ("PATIENT", "CAREGIVER", "BLOOD_DONOR", "DOCTOR", "HOSPITAL"):
            _, resp = h.register(role)
            self.assertEqual(resp.status_code, 201, (role, resp.data))
            created = resp.data["user"]["role_codes"]
            self.assertIn(role, created)
            # Care/facility roles are verification-required; never auto-approved.
            if role in ("DOCTOR", "HOSPITAL"):
                self.assertTrue(resp.data["verification_required"])
        for role in ("ADMIN", "SUPER_ADMIN"):
            _, resp = h.register(role)
            self.assertEqual(resp.status_code, 400, role)


class SetLoginPinTests(TestCase):
    def test_set_pin_requires_authentication(self):
        resp = h.APIClient().post("/api/auth/pin/set/", {"pin": "1234"}, format="json")
        self.assertIn(resp.status_code, (401, 403))

    def test_set_pin_rejects_non_four_digit_values(self):
        user = h.orm_user("PATIENT")
        c = h.client(user)
        for bad in ("123", "12345", "12ab", "abcd", ""):
            resp = c.post("/api/auth/pin/set/", {"pin": bad}, format="json")
            self.assertEqual(resp.status_code, 400, bad)

    def test_set_pin_stores_a_hash_and_marks_the_summary(self):
        user = h.orm_user("PATIENT")
        c = h.client(user)
        resp = c.post("/api/auth/pin/set/", {"pin": "4821"}, format="json")
        self.assertEqual(resp.status_code, 204)
        user.refresh_from_db()
        self.assertTrue(user.login_pin_hash)
        self.assertNotEqual(user.login_pin_hash, "4821")
        self.assertTrue(check_password("4821", user.login_pin_hash))
        self.assertIsNotNone(user.login_pin_set_at)
        self.assertTrue(
            SecurityEvent.objects.filter(user=user, event_type="LOGIN_PIN_SET").exists()
        )
        me = c.get("/api/auth/me/")
        self.assertIs(me.data["has_login_pin"], True)

    def test_set_pin_can_be_changed(self):
        user = h.orm_user("PATIENT")
        c = h.client(user)
        c.post("/api/auth/pin/set/", {"pin": "1111"}, format="json")
        c.post("/api/auth/pin/set/", {"pin": "2222"}, format="json")
        user.refresh_from_db()
        self.assertFalse(check_password("1111", user.login_pin_hash))
        self.assertTrue(check_password("2222", user.login_pin_hash))


class LoginPinTests(TestCase):
    def test_pin_login_issues_a_token_pair(self):
        user = h.orm_user("PATIENT")
        h.client(user).post("/api/auth/pin/set/", {"pin": "9021"}, format="json")
        resp = h.APIClient().post(
            "/api/auth/pin/login/",
            {"email_or_phone": user.email, "pin": "9021"},
            format="json",
        )
        self.assertEqual(resp.status_code, 200, resp.data)
        self.assertIn("access", resp.data)
        self.assertIn("refresh", resp.data)
        self.assertEqual(resp.data["user"]["role_codes"], ["PATIENT"])
        self.assertTrue(
            SecurityEvent.objects.filter(
                user=user, event_type="LOGIN_SUCCESS", detail__method="PIN"
            ).exists()
        )

    def test_pin_login_rejects_wrong_pin_and_unknown_identity_uniformly(self):
        user = h.orm_user("PATIENT")
        h.client(user).post("/api/auth/pin/set/", {"pin": "1111"}, format="json")
        wrong = h.APIClient().post(
            "/api/auth/pin/login/", {"email_or_phone": user.email, "pin": "9999"}, format="json"
        )
        ghost = h.APIClient().post(
            "/api/auth/pin/login/", {"email_or_phone": "nobody@example.com", "pin": "1111"}, format="json"
        )
        self.assertEqual(wrong.status_code, 400)
        self.assertEqual(ghost.status_code, 400)
        self.assertTrue(
            SecurityEvent.objects.filter(user=user, event_type="LOGIN_FAILED").exists()
        )

    def test_pin_login_rejected_when_no_pin_configured(self):
        user = h.orm_user("PATIENT")
        resp = h.APIClient().post(
            "/api/auth/pin/login/", {"email_or_phone": user.email, "pin": "1234"}, format="json"
        )
        self.assertEqual(resp.status_code, 400)

    def test_pin_set_does_not_leak_pin_in_me(self):
        user = h.orm_user("PATIENT")
        h.client(user).post("/api/auth/pin/set/", {"pin": "4444"}, format="json")
        me = h.client(user).get("/api/auth/me/")
        self.assertEqual(me.status_code, 200)
        self.assertNotIn("pin", me.data)
        self.assertNotIn("login_pin_hash", me.data)


class VerificationSurfaceTests(TestCase):
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
    def test_login_returns_active_status_for_new_account(self):
        _c, resp = h.register("PATIENT")
        user = User.objects.get(email=resp.data["user"]["email"])
        login = h.APIClient().post(
            "/api/auth/login/",
            {"email_or_phone": user.email, "password": h._PASSWORD},
            format="json",
        )
        self.assertEqual(login.status_code, 200)
        self.assertEqual(login.data["user"]["account_status"], "ACTIVE")
        self.assertEqual(login.data["user"]["role_codes"], ["PATIENT"])
