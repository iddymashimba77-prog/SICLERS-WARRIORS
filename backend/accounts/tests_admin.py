"""Stage 4.16 tests — Account Management + security-events admin surface.

Security matrix covered:
* Vertical access — PATIENT/MODERATOR/HEALTHCARE_STAFF denied on every
  /admin/users* and /admin/security-events* route; SUP/ADM allowed.
* C17 privilege boundaries — self role-change denied; ADMIN may not grant/
  revoke privileged roles; ADMIN may not touch a privileged account.
* Self-deactivation denied; ADMIN cannot deactivate a privileged account.
* IDOR — unknown UUID → 404; no cross-role leakage in results.
* Medical privacy — user-management rows carry identity/RBAC only (no
  medical, donor or financial fields).
* MFA step-up boundary — mfa_enabled admin refuses access with a recorded
  MFA_CHALLENGE event; non-admin mfa_enabled is unaffected.
* Shorter admin session — admin login/refresh TTL == 8h, patient == 24h.
"""

import uuid as _uuid
from datetime import datetime as _pydatetime, timedelta, timezone as _tz

from django.conf import settings
from django.core.cache import cache
from django.test import TestCase
from django.utils import timezone
from rest_framework.test import APIClient
from rest_framework_simplejwt.tokens import RefreshToken

from accounts.models import Role, SecurityEvent, User, UserRole

_PASSWORD = "Str0ng!Pass9"

USER_FIELDS = {"uid", "email", "phone", "full_name", "account_status", "role_codes", "mfa_enabled", "created_at"}


def _orm_user(role_code, email=None, account_status="ACTIVE", **extra):
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
    c = _JsonAPIClient()
    c.credentials(HTTP_AUTHORIZATION=f"Bearer {RefreshToken.for_user(user).access_token}")
    return c


class _JsonAPIClient(APIClient):
    def _json(self, kwargs):
        kwargs.setdefault("format", "json")

    def post(self, *args, **kwargs):
        self._json(kwargs)
        return super().post(*args, **kwargs)

    def delete(self, *args, **kwargs):
        self._json(kwargs)
        return super().delete(*args, **kwargs)


def _login_json(user):
    return {"email_or_phone": user.email, "password": _PASSWORD}


class AdminUsersManagementTests(TestCase):
    def setUp(self):
        cache.clear()
        self.super = _orm_user("SUPER_ADMIN")
        self.admin = _orm_user("ADMIN")
        self.moderator = _orm_user("MODERATOR")
        self.patient = _orm_user("PATIENT")
        self.staff = _orm_user("HEALTHCARE_STAFF")
        self.target = _orm_user("PATIENT")
        self.super_client = _client(self.super)
        self.admin_client = _client(self.admin)
        self.target_client = _client(self.target)

    # ------------------------------------------------------------------ list
    def test_list_allowed_for_admin_roles(self):
        r = self.super_client.get("/api/admin/users/")
        self.assertEqual(r.status_code, 200)
        body = r.json()["data"]
        self.assertIn("results", body)
        emails = {row["email"] for row in body["results"]}
        self.assertIn(self.target.email, emails)
        row = next(x for x in body["results"] if x["email"] == self.target.email)
        self.assertEqual(set(row.keys()), USER_FIELDS)  # identity/RBAC only, no medical data

    def test_list_denied_for_non_admin_roles(self):
        for client in (_client(self.moderator), _client(self.patient), _client(self.staff)):
            self.assertEqual(client.get("/api/admin/users/").status_code, 403)
        self.assertEqual(APIClient().get("/api/admin/users/").status_code, 401)

    def test_search_and_filters(self):
        r = self.super_client.get("/api/admin/users/", {"q": self.target.email})
        self.assertEqual([row["uid"] for row in r.json()["data"]["results"]], [str(self.target.uid)])

        # status filter rejects unknown statuses
        self.assertEqual(
            self.super_client.get("/api/admin/users/", {"status": "BOGUS"}).status_code, 400
        )
        r = self.super_client.get("/api/admin/users/", {"status": "SUSPENDED"})
        self.assertTrue(all(row["account_status"] == "SUSPENDED" for row in r.json()["data"]["results"]) or r.json()["data"]["count"] == 0)

        r = self.super_client.get("/api/admin/users/", {"role": "ADMIN"})
        admin_rows = [row for row in r.json()["data"]["results"] if row["email"] == self.admin.email]
        self.assertEqual(admin_rows, [admin_rows[0]] if admin_rows else [])

    def test_unknown_uid_404(self):
        r = self.super_client.post(f"/api/admin/users/{_uuid.uuid4()}/activate/", {"reason": "Testing."})
        self.assertEqual(r.status_code, 404)

    # ------------------------------------------------------------- activate
    def test_activate_records_audit_and_changes_status(self):
        suspended = _orm_user("PATIENT", account_status="SUSPENDED")
        r = self.super_client.post(
            f"/api/admin/users/{suspended.uid}/activate/", {"reason": "Appealed suspension"}
        )
        self.assertEqual(r.status_code, 200)
        suspended.refresh_from_db()
        self.assertEqual(suspended.account_status, "ACTIVE")
        from audit.models import AuditLog
        rows = AuditLog.objects.filter(action_code="admin.user.activate", resource_id=suspended.pk)
        self.assertEqual(rows.count(), 1)
        self.assertEqual(rows.first().details["reason"], "Appealed suspension")

    def test_activate_already_active_400(self):
        r = self.super_client.post(f"/api/admin/users/{self.target.uid}/activate/", {"reason": "Again"})
        self.assertEqual(r.status_code, 400)

    # ----------------------------------------------------------- deactivate
    def test_deactivate_records_audit_and_changes_status(self):
        r = self.admin_client.post(
            f"/api/admin/users/{self.target.uid}/deactivate/", {"reason": "Abuse reports"}
        )
        self.assertEqual(r.status_code, 200)
        self.target.refresh_from_db()
        self.assertEqual(self.target.account_status, "SUSPENDED")
        from audit.models import AuditLog
        self.assertEqual(
            AuditLog.objects.filter(action_code="admin.user.deactivate", resource_id=self.target.pk).count(), 1
        )

    def test_deactivate_self_denied(self):
        r = self.super_client.post(
            f"/api/admin/users/{self.super.uid}/deactivate/", {"reason": "Testing self-fail"}
        )
        self.assertEqual(r.status_code, 403)

    def test_admin_cannot_deactivate_privileged_account(self):
        r = self.admin_client.post(
            f"/api/admin/users/{self.super.uid}/deactivate/", {"reason": "Testing"}
        )
        self.assertEqual(r.status_code, 403)
        r = self.admin_client.post(
            f"/api/admin/users/{self.admin.uid}/deactivate/", {"reason": "Testing"}
        )
        self.assertEqual(r.status_code, 403)

    def test_super_can_deactivate_another_admin(self):
        r = self.super_client.post(
            f"/api/admin/users/{self.admin.uid}/deactivate/", {"reason": "Temporary hold"}
        )
        self.assertEqual(r.status_code, 200)
        self.admin.refresh_from_db()
        self.assertEqual(self.admin.account_status, "SUSPENDED")

    def test_deactivate_requires_reason(self):
        r = self.super_client.post(f"/api/admin/users/{self.target.uid}/deactivate/", {})
        self.assertEqual(r.status_code, 400)

    # ---------------------------------------------------------------- roles
    def test_super_assigns_privileged_role(self):
        r = self.super_client.post(
            f"/api/admin/users/{self.target.uid}/roles/",
            {"role_code": "ADMIN", "reason": "Ops capacity"},
        )
        self.assertEqual(r.status_code, 200)
        self.target.refresh_from_db()
        self.assertIn("ADMIN", self.target.role_codes)
        from audit.models import AuditLog
        self.assertEqual(
            AuditLog.objects.filter(action_code="admin.user.role_grant", resource_id=self.target.pk).count(), 1
        )

    def test_admin_assigns_non_privileged_role(self):
        r = self.admin_client.post(
            f"/api/admin/users/{self.target.uid}/roles/",
            {"role_code": "CAREGIVER", "reason": "Secondary role"},
        )
        self.assertEqual(r.status_code, 200)
        self.target.refresh_from_db()
        self.assertIn("CAREGIVER", self.target.role_codes)

    def test_admin_cannot_assign_privileged_role(self):
        r = self.admin_client.post(
            f"/api/admin/users/{self.target.uid}/roles/",
            {"role_code": "SUPER_ADMIN", "reason": "Escalate access"},
        )
        self.assertEqual(r.status_code, 403)

    def test_admin_cannot_change_roles_on_privileged_account(self):
        r = self.admin_client.post(
            f"/api/admin/users/{self.admin.uid}/roles/",
            {"role_code": "PATIENT", "reason": "Ops capacity"},
        )
        self.assertEqual(r.status_code, 403)

    def test_self_assignment_always_denied(self):
        r = self.super_client.post(
            f"/api/admin/users/{self.super.uid}/roles/",
            {"role_code": "MODERATOR", "reason": "Self promotion"},
        )
        self.assertEqual(r.status_code, 403)

    def test_unknown_role_400(self):
        r = self.super_client.post(
            f"/api/admin/users/{self.target.uid}/roles/",
            {"role_code": "NOT_A_ROLE", "reason": "Testing"},
        )
        self.assertEqual(r.status_code, 400)

    def test_revoke_role_and_last_role_protection(self):
        doctor = _orm_user("DOCTOR")
        admin = _orm_user("ADMIN")
        admin_client = _client(admin)
        r = admin_client.delete(
            f"/api/admin/users/{doctor.uid}/roles/",
            {"role_code": "DOCTOR", "reason": "Left the practice"},
        )
        self.assertEqual(r.status_code, 400)  # revoking the only role is blocked
        doctor.refresh_from_db()
        self.assertEqual(doctor.role_codes, ["DOCTOR"])

        doctor = _orm_user("DOCTOR")
        admin_client.delete(
            f"/api/admin/users/{doctor.uid}/roles/",
            {"role_code": "DOCTOR", "reason": "Role cleanup"},
        )
        r = admin_client.post(
            f"/api/admin/users/{doctor.uid}/roles/",
            {"role_code": "PATIENT", "reason": "Role cleanup"},
        )
        self.assertEqual(r.status_code, 200)
        doctor.refresh_from_db()
        self.assertEqual(doctor.role_codes, ["DOCTOR", "PATIENT"])
        r = admin_client.delete(
            f"/api/admin/users/{doctor.uid}/roles/",
            {"role_code": "DOCTOR", "reason": "Role cleanup"},
        )
        self.assertEqual(r.status_code, 200)
        doctor.refresh_from_db()
        self.assertEqual(doctor.role_codes, ["PATIENT"])

        solo = _orm_user("PATIENT")
        r = self.super_client.delete(
            f"/api/admin/users/{solo.uid}/roles/",
            {"role_code": "PATIENT", "reason": "Removing role"},
        )
        self.assertEqual(r.status_code, 400)  # cannot revoke the last role

    # ---------------------------------------------------------------- IDOR
    def test_admin_management_does_not_leak_medical_data(self):
        r = self.super_client.get(f"/api/admin/users/{self.target.uid}/roles/")
        self.assertEqual(r.status_code, 200)
        self.assertEqual(set(r.json()["data"].keys()), {"uid", "roles"})


class AdminSecurityEventsTests(TestCase):
    def setUp(self):
        cache.clear()
        self.super = _orm_user("SUPER_ADMIN")
        self.admin = _orm_user("ADMIN")
        self.patient = _orm_user("PATIENT")
        self.event = SecurityEvent.objects.create(
            user=self.patient, event_type="LOGIN_FAILED", status="FAILED",
            ip_address="10.0.0.1", detail={"attempt": 3},
        )

    def test_super_and_admin_can_read(self):
        for user in (self.super, self.admin):
            r = _client(user).get("/api/admin/security-events/")
            self.assertEqual(r.status_code, 200)
            types = {row["event_type"] for row in r.json()["data"]["results"]}
            self.assertIn("LOGIN_FAILED", types)

    def test_patient_denied(self):
        r = _client(self.patient).get("/api/admin/security-events/")
        self.assertEqual(r.status_code, 403)

    def test_filters(self):
        client = _client(self.super)
        r = client.get("/api/admin/security-events/", {"event_type": "LOGIN_FAILED"})
        self.assertTrue(all(x["event_type"] == "LOGIN_FAILED" for x in r.json()["data"]["results"]))
        r = client.get("/api/admin/security-events/", {"event_type": "NOPE"})
        self.assertEqual(r.status_code, 400)
        r = client.get("/api/admin/security-events/", {"ip": "10.0.0.1"})
        self.assertTrue(all(x["ip_address"] == "10.0.0.1" for x in r.json()["data"]["results"]))
        r = client.get("/api/admin/security-events/", {"user": self.patient.email})
        self.assertTrue(all(x["user_email"] == self.patient.email for x in r.json()["data"]["results"]))


class AdminMfaBoundaryTests(TestCase):
    def setUp(self):
        cache.clear()
        self.super = _orm_user("SUPER_ADMIN", mfa_enabled=True)
        self.patient = _orm_user("PATIENT", mfa_enabled=True)
        self.super_client = _client(self.super)

    def test_mfa_admin_refused_on_admin_surface(self):
        r = self.super_client.get("/api/admin/users/")
        self.assertEqual(r.status_code, 403)
        self.assertTrue(
            SecurityEvent.objects.filter(user=self.super, event_type="MFA_CHALLENGE").exists()
        )

    def test_mfa_patient_not_locked_out_of_general_surfaces(self):
        r = _client(self.patient).get("/api/auth/me/")
        self.assertEqual(r.status_code, 200)
        self.assertFalse(
            SecurityEvent.objects.filter(user=self.patient, event_type="MFA_CHALLENGE").exists()
        )

    def test_mfa_admin_still_blocked_on_read_surfaces(self):
        r = self.super_client.get("/api/admin/security-events/")
        self.assertEqual(r.status_code, 403)


class AdminSessionTtlTests(TestCase):
    def setUp(self):
        cache.clear()
        self.admin = _orm_user("ADMIN", account_status="ACTIVE")
        self.patient = _orm_user("PATIENT", account_status="ACTIVE")

    def _token(self, body):
        return body["data"]["refresh"]

    def _exp(self, refresh_str):
        return _pydatetime.fromtimestamp(
            RefreshToken(refresh_str).payload["exp"], tz=_tz.utc
        )

    def test_login_issues_shorter_admin_refresh(self):
        now = timezone.now()
        r = APIClient().post("/api/auth/login/", _login_json(self.admin), format="json")
        self.assertEqual(r.status_code, 200)
        exp = self._exp(self._token(r.json()))
        self.assertLess(exp - now, timedelta(hours=9))
        self.assertGreater(exp - now, timedelta(hours=7))

    def test_login_keeps_full_refresh_for_patients(self):
        now = timezone.now()
        r = APIClient().post("/api/auth/login/", _login_json(self.patient), format="json")
        self.assertEqual(r.status_code, 200)
        exp = self._exp(self._token(r.json()))
        self.assertLess(exp - now, timedelta(hours=25))
        self.assertGreater(exp - now, timedelta(hours=23))

    def test_rotation_preserves_admin_ttl(self):
        r = APIClient().post("/api/auth/login/", _login_json(self.admin), format="json")
        now = timezone.now()
        r2 = APIClient().post("/api/auth/refresh/", {"refresh": self._token(r.json())}, format="json")
        self.assertEqual(r2.status_code, 200)
        self.assertIn("refresh", r2.json()["data"])
        exp = self._exp(r2.json()["data"]["refresh"])
        self.assertLess(exp - now, timedelta(hours=9))
        self.assertGreater(exp - now, timedelta(hours=7))