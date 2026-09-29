"""Backend tests for the Stage 4.8 append-only audit log.

Run::

    venv/bin/python manage.py test audit --settings=config.settings.ephemeral_test

Covers: append-only immutability (update/delete raise), the admin list endpoint
(SUP/ADM only, C4) with action-code filtering, and that payloads are never
exposed.
"""

import uuid as _uuid

from django.test import TestCase
from rest_framework.test import APIClient
from rest_framework_simplejwt.tokens import RefreshToken

from accounts.models import Role, User, UserRole
from audit.models import AuditLog
from audit.services import record_audit


_PASSWORD = "Str0ng!Pass9"


def _orm_user(role_code="SUPER_ADMIN", email=None):
    user = User.objects.create_user(
        email=email or f"{role_code.lower()}-{_uuid.uuid4().hex[:10]}@example.com",
        password=_PASSWORD,
        first_name="Test",
        last_name="User",
        account_status="ACTIVE",
    )
    UserRole.objects.create(user=user, role=Role.objects.get(code=role_code))
    return user


def _client(user):
    client = APIClient()
    client.credentials(HTTP_AUTHORIZATION=f"Bearer {RefreshToken.for_user(user).access_token}")
    return client


class AuditLogModelTests(TestCase):
    def setUp(self):
        self.actor = _orm_user()

    def test_append_only_update_and_delete_blocked(self):
        record_audit(actor=self.actor, action_code="blood_requests.create", resource_type="blood_request")
        row = AuditLog.objects.get()
        row.action_code = "tampered"
        with self.assertRaises(ValueError):
            row.save()
        with self.assertRaises(ValueError):
            row.delete()

    def test_record_audit_ignores_bad_request_context(self):
        record_audit(actor=self.actor, action_code="x.y", result="DENIED")
        row = AuditLog.objects.get()
        self.assertEqual(row.result, "DENIED")
        self.assertIsNone(row.request_id)
        self.assertEqual(row.details, {})


class AuditLogApiTests(TestCase):
    def setUp(self):
        self.super_admin = _client(_orm_user("SUPER_ADMIN"))
        self.admin = _client(_orm_user("ADMIN"))
        self.patient = _client(_orm_user("PATIENT"))
        record_audit(action_code="blood_requests.create", resource_type="blood_request")
        record_audit(action_code="emergency_requests.create", resource_type="emergency_request")

    def test_admin_list_and_filter(self):
        listed = self.admin.get("/api/admin/audit-logs/")
        self.assertEqual(listed.status_code, 200)
        self.assertEqual(listed.data["count"], 2)
        filtered = self.super_admin.get("/api/admin/audit-logs/?action_code=emergency")
        self.assertEqual(filtered.data["count"], 1)
        self.assertEqual(filtered.data["results"][0]["action_code"], "emergency_requests.create")

    def test_non_admin_denied(self):
        self.assertEqual(self.patient.get("/api/admin/audit-logs/").status_code, 403)
        self.assertEqual(APIClient().get("/api/admin/audit-logs/").status_code, 401)

    def test_no_payload_fields_exposed(self):
        row = self.super_admin.get("/api/admin/audit-logs/").data["results"][0]
        self.assertNotIn("details", row)
        self.assertNotIn("user_agent", row)