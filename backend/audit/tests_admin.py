"""Stage 4.16 tests — audit search/filter surface + CSV export.

Security matrix covered:
* Vertical access — audit_logs.view for SUP/ADM list; audit_logs.export is
  SUPER_ADMIN-only for the CSV export.
* Filter contract — action_code/resource_type substring, exact result
  (SUCCESS/FAILURE/DENIED), actor email substring, date_from/date_to (YYYY-MM-DD).
* Payload-free policy — neither the list serializer nor the CSV exports
  free-form ``details``.
* Export hygiene — reason mandatory (min 5), the export appends its own audit
  row, and MFA step-up applies.
"""

import uuid as _uuid
from datetime import timedelta

from django.core.cache import cache
from django.test import TestCase
from django.utils import timezone
from rest_framework.test import APIClient
from rest_framework_simplejwt.tokens import RefreshToken

from accounts.models import Role, User, UserRole
from audit.models import AuditLog
from audit.services import record_audit

_PASSWORD = "Str0ng!Pass9"


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


def _client(user):
    client = APIClient()
    client.credentials(HTTP_AUTHORIZATION=f"Bearer {RefreshToken.for_user(user).access_token}")
    return client


class AuditAdminFiltersTests(TestCase):
    def setUp(self):
        cache.clear()
        self.super = _orm_user("SUPER_ADMIN")
        self.admin = _orm_user("ADMIN")
        self.patient = _orm_user("PATIENT")
        self.super_client = _client(self.super)
        self.admin_client = _client(self.admin)
        self.patient_client = _client(self.patient)
        record_audit(actor=self.admin, action_code="users.activate", resource_type="users",
                     result="SUCCESS")
        record_audit(actor=self.admin, action_code="users.deactivate", resource_type="users",
                     result="SUCCESS")
        record_audit(actor=self.super, action_code="payments.refund", resource_type="refund",
                     result="FAILURE")

    def test_list_requires_audit_logs_view(self):
        self.assertEqual(self.admin_client.get("/api/admin/audit-logs/").status_code, 200)
        self.assertEqual(self.patient_client.get("/api/admin/audit-logs/").status_code, 403)

    def test_action_code_filter(self):
        r = self.super_client.get("/api/admin/audit-logs/", {"action_code": "users."})
        self.assertEqual(r.status_code, 200)
        codes = {row["action_code"] for row in r.json()["data"]["results"]}
        self.assertEqual(codes, {"users.activate", "users.deactivate"})

    def test_result_filter(self):
        r = self.super_client.get("/api/admin/audit-logs/", {"result": "FAILURE"})
        self.assertEqual(r.status_code, 200)
        self.assertTrue(all(x["result"] == "FAILURE" for x in r.json()["data"]["results"]))
        bad = self.super_client.get("/api/admin/audit-logs/", {"result": "NOPE"})
        self.assertEqual(bad.status_code, 400)

    def test_actor_email_filter(self):
        r = self.super_client.get("/api/admin/audit-logs/", {"actor": self.super.email})
        self.assertEqual(r.status_code, 200)
        self.assertTrue(all(x["actor_email"] == self.super.email for x in r.json()["data"]["results"]))

    def test_date_range_filter(self):
        old = AuditLog.objects.filter(action_code="users.activate").first()
        AuditLog.objects.filter(pk=old.pk).update(
            created_at=timezone.now() - timedelta(days=10)
        )
        r = self.super_client.get("/api/admin/audit-logs/", {
            "date_from": (timezone.now() - timedelta(days=1)).date().isoformat(),
            "date_to": timezone.now().date().isoformat(),
        })
        self.assertEqual(r.status_code, 200)
        self.assertTrue(all(
            row["action_code"] != "users.activate" for row in r.json()["data"]["results"]
        ))
        bad = self.super_client.get("/api/admin/audit-logs/", {"date_from": "not-a-date"})
        self.assertEqual(bad.status_code, 400)

    def test_rows_never_include_payload(self):
        r = self.super_client.get("/api/admin/audit-logs/")
        for row in r.json()["data"]["results"]:
            self.assertNotIn("details", row)
            self.assertNotIn("payload", row)


class AuditAdminExportTests(TestCase):
    def setUp(self):
        cache.clear()
        self.super = _orm_user("SUPER_ADMIN")
        self.admin = _orm_user("ADMIN")
        self.super_client = _client(self.super)
        self.admin_client = _client(self.admin)
        record_audit(actor=self.super, action_code="donations.refund", resource_type="refund",
                     result="SUCCESS", details={"reason": "duplicate charge"})

    def test_export_supervisor_only(self):
        r = self.super_client.get("/api/admin/audit-logs/export/", {"reason": "Annual archive"})
        self.assertEqual(r.status_code, 200)
        self.assertTrue(r.content.startswith(b"created_at,"))
        self.assertEqual(r["Content-Disposition"], 'attachment; filename="audit-log.csv"')

    def test_export_denied_without_reason(self):
        r = self.super_client.get("/api/admin/audit-logs/export/")
        self.assertEqual(r.status_code, 400)
        short = self.super_client.get("/api/admin/audit-logs/export/", {"reason": "x"})
        self.assertEqual(short.status_code, 400)

    def test_export_admin_denied(self):
        r = self.admin_client.get("/api/admin/audit-logs/export/", {"reason": "Annual archive"})
        self.assertEqual(r.status_code, 403)

    def test_export_records_own_audit_row(self):
        r = self.super_client.get("/api/admin/audit-logs/export/", {"reason": "Annual archive"})
        self.assertEqual(r.status_code, 200)
        self.assertTrue(
            AuditLog.objects.filter(action_code="audit_logs.export", result="SUCCESS").exists()
        )
        self.assertIn(b"donations.refund", r.content)

    def test_export_never_includes_details(self):
        r = self.super_client.get("/api/admin/audit-logs/export/", {"reason": "Annual archive"})
        header = b"created_at,actor_email,action_code,resource_type,resource_id,result,ip_address,request_id"
        self.assertTrue(r.content.startswith(header))
        self.assertNotIn(b"duplicate charge", r.content)

    def test_export_mfa_boundary(self):
        admin = _orm_user("SUPER_ADMIN", mfa_enabled=True)
        r = _client(admin).get("/api/admin/audit-logs/export/", {"reason": "Annual archive"})
        self.assertEqual(r.status_code, 403)