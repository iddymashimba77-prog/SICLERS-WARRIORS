"""ADMIN-3 tests — role & permission matrix surface (accounts/roles_views.py).

Run::

    venv/bin/python manage.py test accounts.tests_admin_roles --settings=config.settings.ephemeral_test

Covers the SUPER_ADMIN RBAC surface: read matrix for SUP/ADM, SUP-only
grant/revoke with mandatory audited reason, lockout guard on the SUPER_ADMIN
kernel, and strict 401/403/404/400 responses for non-privileged callers.
"""

import uuid as _uuid

from django.test import TestCase
from rest_framework.test import APIClient
from rest_framework_simplejwt.tokens import RefreshToken

from audit.models import AuditLog
from .models import Role, RolePermission, User, UserRole

_PASSWORD = "Str0ng!Pass9"


def _orm_user(role_code, email=None):
    user = User.objects.create_user(
        email=email or f"{role_code.lower()}-{_uuid.uuid4().hex[:10]}@example.com",
        password=_PASSWORD,
        first_name="Test",
        last_name=role_code.title(),
        account_status="ACTIVE",
    )
    UserRole.objects.create(user=user, role=Role.objects.get(code=role_code))
    return user


def _client(user):
    client = APIClient()
    client.credentials(HTTP_AUTHORIZATION=f"Bearer {RefreshToken.for_user(user).access_token}")
    return client


class AdminRolesTests(TestCase):
    def setUp(self):
        self.super = _client(_orm_user("SUPER_ADMIN"))
        self.admin = _client(_orm_user("ADMIN"))
        self.vo = _client(_orm_user("VERIFICATION_OFFICER"))
        self.doctor = _client(_orm_user("DOCTOR"))
        self.patient = _client(_orm_user("PATIENT"))

    # ------------------------------------------------------------------ read
    def test_matrix_read_allowed_for_sup_and_admin(self):
        for client in (self.super, self.admin):
            resp = client.get("/api/admin/roles/")
            self.assertEqual(resp.status_code, 200)
            roles = resp.json()["data"]["results"]
            codes = [r["code"] for r in roles]
            self.assertIn("SUPER_ADMIN", codes)
            self.assertIn("PATIENT", codes)
            sup_row = next(r for r in roles if r["code"] == "SUPER_ADMIN")
            self.assertGreaterEqual(sup_row["permission_count"], 8)
            self.assertGreaterEqual(sup_row["member_count"], 1)

    def test_matrix_read_denied_for_non_admin_roles(self):
        for client in (self.vo, self.doctor, self.patient):
            self.assertEqual(client.get("/api/admin/roles/").status_code, 403)

    def test_matrix_read_requires_auth(self):
        self.assertEqual(APIClient().get("/api/admin/roles/").status_code, 401)

    def test_single_role_permissions_read(self):
        resp = self.super.get("/api/admin/roles/SUPER_ADMIN/permissions/")
        self.assertEqual(resp.status_code, 200)
        self.assertEqual(resp.data["code"], "SUPER_ADMIN")
        self.assertIn("admin.permissions.manage", resp.data["permissions"])

    def test_unknown_role_404(self):
        resp = self.super.get("/api/admin/roles/NO_SUCH_ROLE/permissions/")
        self.assertEqual(resp.status_code, 404)

    # ----------------------------------------------------------------- write
    def test_super_grants_and_revokes_a_permission(self):
        grant = self.super.post(
            "/api/admin/roles/CAREGIVER/permissions/",
            {"permission_code": "symptoms.record", "grant": True, "reason": "Caregiver support"},
            format="json",
        )
        self.assertEqual(grant.status_code, 201)
        self.assertTrue(
            RolePermission.objects.filter(
                role__code="CAREGIVER", permission__code="symptoms.record",
            ).exists()
        )
        self.assertTrue(
            AuditLog.objects.filter(
                action_code="admin.roles.permission_grant",
                details__role="CAREGIVER",
                details__permission="symptoms.record",
            ).exists()
        )

        revoke = self.super.post(
            "/api/admin/roles/CAREGIVER/permissions/",
            {"permission_code": "symptoms.record", "grant": False, "reason": "Policy change"},
            format="json",
        )
        self.assertEqual(revoke.status_code, 200)
        self.assertFalse(
            RolePermission.objects.filter(
                role__code="CAREGIVER", permission__code="symptoms.record",
            ).exists()
        )
        self.assertTrue(
            AuditLog.objects.filter(
                action_code="admin.roles.permission_revoke",
                details__role="CAREGIVER",
            ).exists()
        )

    def test_duplicate_grant_400(self):
        resp = self.super.post(
            "/api/admin/roles/PATIENT/permissions/",
            {"permission_code": "symptoms.record", "grant": True, "reason": "Duplicate check"},
            format="json",
        )
        self.assertEqual(resp.status_code, 400)

    def test_revoke_unheld_permission_400(self):
        resp = self.super.post(
            "/api/admin/roles/PATIENT/permissions/",
            {"permission_code": "doctors.verify", "grant": False, "reason": "Noop revoke"},
            format="json",
        )
        self.assertEqual(resp.status_code, 400)

    def test_unknown_permission_400(self):
        resp = self.super.post(
            "/api/admin/roles/PATIENT/permissions/",
            {"permission_code": "totally.made.up", "grant": False, "reason": "Unknown code"},
            format="json",
        )
        self.assertEqual(resp.status_code, 400)

    def test_reason_required_for_write(self):
        resp = self.super.post(
            "/api/admin/roles/PATIENT/permissions/",
            {"permission_code": "symptoms.record", "grant": True, "reason": "x"},
            format="json",
        )
        self.assertEqual(resp.status_code, 400)

    def test_admin_cannot_write_permissions(self):
        resp = self.admin.post(
            "/api/admin/roles/PATIENT/permissions/",
            {"permission_code": "symptoms.record", "grant": True, "reason": "Escalation check"},
            format="json",
        )
        self.assertEqual(resp.status_code, 403)

    def test_non_admin_cannot_write(self):
        resp = self.vo.post(
            "/api/admin/roles/PATIENT/permissions/",
            {"permission_code": "symptoms.record", "grant": True, "reason": "Escalation check"},
            format="json",
        )
        self.assertEqual(resp.status_code, 403)

    def test_super_admin_kernel_lockout_guard(self):
        for code in (
            "admin.permissions.manage", "admin.roles.manage", "admin.users.manage",
            "admin.audit.read", "admin.audit.export", "admin.system.manage",
        ):
            resp = self.super.post(
                "/api/admin/roles/SUPER_ADMIN/permissions/",
                {"permission_code": code, "grant": False, "reason": "Lockout attempt"},
                format="json",
            )
            self.assertEqual(resp.status_code, 400, code)
            self.assertTrue(
                RolePermission.objects.filter(
                    role__code="SUPER_ADMIN", permission__code=code,
                ).exists()
            )

    def test_kernel_guard_does_not_block_grants(self):
        resp = self.super.post(
            "/api/admin/roles/SUPER_ADMIN/permissions/",
            {"permission_code": "doctors.view", "grant": True, "reason": "Idempotent-risk probe"},
            format="json",
        )
        self.assertEqual(resp.status_code, 400)  # already held -> duplicate grant

    def test_write_matrix_response_shape(self):
        resp = self.super.post(
            "/api/admin/roles/CAREGIVER/permissions/",
            {"permission_code": "analytics.view", "grant": True, "reason": "Support tools"},
            format="json",
        )
        self.assertEqual(resp.data, {"code": "CAREGIVER", "permission": "analytics.view", "granted": True})

    def test_write_reflects_in_read(self):
        self.super.post(
            "/api/admin/roles/CAREGIVER/permissions/",
            {"permission_code": "analytics.view", "grant": True, "reason": "Support tools"},
            format="json",
        )
        permissions = self.super.get("/api/admin/roles/CAREGIVER/permissions/").data["permissions"]
        self.assertIn("analytics.view", permissions)