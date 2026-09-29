"""Stage 4.16 tests — admin AI monitoring (`admin.audit.read`).

Security matrix covered:
* Vertical access — PATIENT/MODERATOR denied; SUP/ADM allowed.
* Window validation — days must be an integer in [1, 90].
* Aggregation contract — counters derive from the append-only audit trail and
  only from the approved AI action codes; absent content/privacy (never any
  conversation text, prompt or user content is returned).
* MFA step-up boundary.
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
_API = "/api/admin/ai/monitoring/"


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


class AdminAiMonitoringTests(TestCase):
    def setUp(self):
        cache.clear()
        self.super = _orm_user("SUPER_ADMIN")
        self.admin = _orm_user("ADMIN")
        self.patient = _orm_user("PATIENT")
        self.moderator = _orm_user("MODERATOR")
        self.super_client = _client(self.super)
        self.admin_client = _client(self.admin)

    def _seed(self):
        patient = _orm_user("PATIENT")
        record_audit(actor=patient, action_code="ai.request", resource_type="ai", result="SUCCESS")
        record_audit(actor=patient, action_code="ai.completed", resource_type="ai", result="SUCCESS")
        record_audit(actor=patient, action_code="ai.completed", resource_type="ai", result="SUCCESS")
        record_audit(actor=patient, action_code="ai.safety_block", resource_type="ai", result="DENIED")
        record_audit(actor=patient, action_code="ai.provider_failure", resource_type="ai", result="FAILURE")
        record_audit(actor=patient, action_code="ai.use_denied", resource_type="ai", result="DENIED")
        record_audit(actor=self.admin, action_code="users.activate", resource_type="users",
                     result="SUCCESS", details={"reason": "not counting this"})

    def test_vertical_access(self):
        r = self.admin_client.get(_API)
        self.assertEqual(r.status_code, 200)
        for client in (_client(self.patient), _client(self.moderator)):
            self.assertEqual(client.get(_API).status_code, 403)

    def test_aggregation_counts(self):
        self._seed()
        r = self.super_client.get(_API)
        self.assertEqual(r.status_code, 200)
        data = r.json()["data"]
        self.assertEqual(data["total_events"], 6)
        self.assertEqual(data["safety_blocks"], 1)
        self.assertEqual(data["provider_failures"], 1)
        self.assertEqual(data["usage_denied"], 1)
        self.assertEqual(data["unique_users"], 1)

    def test_window_validation(self):
        self.assertEqual(self.super_client.get(_API, {"days": "0"}).status_code, 400)
        self.assertEqual(self.super_client.get(_API, {"days": "91"}).status_code, 400)
        self.assertEqual(self.super_client.get(_API, {"days": "abc"}).status_code, 400)
        self.assertEqual(self.super_client.get(_API, {"days": "7"}).status_code, 200)

    def test_window_excludes_old_rows(self):
        self._seed()
        patient = _orm_user("PATIENT")
        record_audit(actor=patient, action_code="ai.request", resource_type="ai", result="SUCCESS")
        old = AuditLog.objects.filter(action_code="ai.request").last()
        AuditLog.objects.filter(pk=old.pk).update(created_at=timezone.now() - timedelta(days=120))
        r = self.super_client.get(_API, {"days": "30"})
        self.assertEqual(r.status_code, 200)
        self.assertEqual(r.json()["data"]["total_events"], 6)

    def test_no_conversation_content_returned(self):
        self._seed()
        raw = self.super_client.get(_API).content.decode()
        forbidden = ("prompt", "user_content", "context", "message", "conversation")
        self.assertTrue(all(word not in raw.lower() for word in forbidden))

    def test_mfa_boundary(self):
        admin = _orm_user("ADMIN", mfa_enabled=True)
        self.assertEqual(_client(admin).get(_API).status_code, 403)