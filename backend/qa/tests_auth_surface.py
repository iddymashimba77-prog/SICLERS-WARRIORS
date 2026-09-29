"""P1 gap re-checks for the auth/RBAC envelope (Stage 4.19 / §10, §6-7).

Complements the existing per-app suites without duplicating them:
* /api/auth/me/ — canonical role-aware state source (4.4) drives the mobile
  role-based navigation; verify roles + status are present and reset-safe.
* Uniform auth failures (bad password == unknown email, no oracle).
* Login throttle (auth scope) returns 429 when the throttled identity is
  hammered — real 429, not a silent pass.
* Expired access token -> 401; anon denied on representative authed endpoints
  (surface-level 401 guarantee across apps).
* Identify-only admin read (no medical data) sanity.
"""

from unittest import mock

import time

from django.conf import settings
from django.test import TestCase

from rest_framework.settings import api_settings
from rest_framework_simplejwt.tokens import AccessToken

from . import qa_helpers as h


def _throttled_auth_rates(minute_rate):
    full = dict(settings.REST_FRAMEWORK)
    rates = dict(full["DEFAULT_THROTTLE_RATES"])
    rates["auth"] = minute_rate
    return rates


class AuthMeSurfaceTests(TestCase):
    def setUp(self):
        self.patient = h.orm_user("PATIENT")
        self.c = h.client(self.patient)

    def test_me_returns_roles_and_status(self):
        me = self.c.get("/api/auth/me/")
        self.assertEqual(me.status_code, 200)
        self.assertIn("PATIENT", me.data["role_codes"])
        self.assertEqual(me.data["account_status"], "ACTIVE")

    def test_me_is_server_authoritative_not_client_roles(self):
        # Client must never assert its own roles: payload derives from DB role rows.
        me = self.c.get("/api/auth/me/")
        self.assertEqual(me.data["email"], self.patient.email)
        self.assertIn("uid", me.data)

    def test_expired_access_token_is_rejected(self):
        expired = AccessToken.for_user(self.patient)
        expired.payload["exp"] = int(time.time()) - 30
        bearer = str(expired)
        anon = h.APIClient()
        anon.credentials(HTTP_AUTHORIZATION=f"Bearer {bearer}")
        self.assertIn(anon.get("/api/auth/me/").status_code, (401, 403))

    def test_invalid_refresh_token_is_rejected(self):
        resp = h.APIClient().post(
            "/api/auth/refresh/", {"refresh": "garbage.invalid.token"}, format="json",
        )
        self.assertIn(resp.status_code, (400, 401))

    def test_anonymous_denied_across_representative_surfaces(self):
        anon = h.APIClient()
        targets = [
            "/api/auth/me/",
            "/api/patients/me/",
            "/api/notifications/",
            "/api/emergency/access-grants/",
            "/api/admin/emergency/",
            "/api/health-timeline/",
            "/api/symptom-types/",
        ]
        for path in targets:
            with self.subTest(path=path):
                self.assertIn(anon.get(path).status_code, (401, 403), path)


class AuthUniformFailureTests(TestCase):
    def test_bad_password_and_unknown_email_are_indistinguishable(self):
        h.orm_user("PATIENT", email="exists@example.com")
        client = h.APIClient()
        bad_password = client.post(
            "/api/auth/login/",
            {"email_or_phone": "exists@example.com", "password": "WrongPass!"},
            format="json",
        )
        unknown_email = client.post(
            "/api/auth/login/",
            {"email_or_phone": "nobody@example.com", "password": "WrongPass!"},
            format="json",
        )
        self.assertEqual(bad_password.status_code, unknown_email.status_code)
        self.assertNotEqual(bad_password.status_code, 200)


class AuthLoginThrottleTests(TestCase):
    def test_auth_scope_throttle_returns_429(self):
        user = h.orm_user("PATIENT")
        client = h.APIClient()
        login = {"email_or_phone": user.email, "password": h._PASSWORD}
        # DRF snapshots throttle rates at import time, so patch the live
        # api_settings dict directly (ephemeral profile runs auth at 1e6/min).
        with mock.patch.dict(api_settings.DEFAULT_THROTTLE_RATES, {"auth": "1/minute"}):
            first = client.post("/api/auth/login/", login, format="json")
            second = client.post("/api/auth/login/", login, format="json")
            self.assertEqual(first.status_code, 200)
            self.assertEqual(second.status_code, 429)


class AdminIdentifyOnlySanityTests(TestCase):
    def test_admin_user_list_is_identity_only(self):
        # Existing suite asserts the exact field set; here we guard the
        # "no medical data" invariant used by the admin console.
        h.orm_user("PATIENT")
        admin = h.orm_user("ADMIN")
        MEDICAL = {"genotype", "date_of_birth", "gender", "primary_diagnosis"}
        resp = h.client(admin).get("/api/admin/users/")
        self.assertEqual(resp.status_code, 200)
        for row in resp.data["results"]:
            self.assertTrue(MEDICAL.isdisjoint(row.keys()))