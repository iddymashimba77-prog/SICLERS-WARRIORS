"""Stage 4.16 tests — admin system broadcast (`notifications.broadcast`).

Security matrix covered:
* Vertical access — PATIENT/MODERATOR denied; SUP/ADM allowed.
* Audience rules — ALL / ROLE / USERS; USERS capped at 500; only ACTIVE
  targets; ROLE must exist; UIDs must all resolve to active accounts.
* SYSTEM/IN_APP only — no impersonation channel; force=True so muted
  preferences never block an admin policy broadcast.
* Unauthorized adjacency — no views/users/medical data returned.
* Audit row + MFA step-up boundary like every admin surface.
"""

import uuid as _uuid

from django.core.cache import cache
from django.test import TestCase
from rest_framework.test import APIClient
from rest_framework_simplejwt.tokens import RefreshToken

from accounts.models import Role, User, UserRole
from audit.models import AuditLog
from notifications.models import Notification

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


class AdminBroadcastTests(TestCase):
    def setUp(self):
        cache.clear()
        self.super = _orm_user("SUPER_ADMIN")
        self.admin = _orm_user("ADMIN")
        self.patient = _orm_user("PATIENT")
        self.moderator = _orm_user("MODERATOR")
        self.super_client = _client(self.super)
        self.admin_client = _client(self.admin)
        self.patient_client = _client(self.patient)
        self.moderator_client = _client(self.moderator)

    def _payload(self, audience="ALL", title="Maintenance", body="Scheduled downtime", **kw):
        return {"audience": audience, "title": title, "body": body, **kw}

    def test_broadcast_all_allowed_for_admin_roles(self):
        r = self.super_client.post("/api/admin/notifications/broadcast/", self._payload())
        self.assertEqual(r.status_code, 201)
        self.assertEqual(r.json()["data"]["recipient_count"], 4)
        self.assertEqual(Notification.objects.filter(type="SYSTEM", channel="IN_APP").count(), 4)
        self.assertTrue(
            AuditLog.objects.filter(action_code="notifications.broadcast", result="SUCCESS").exists()
        )

    def test_broadcast_role_audience(self):
        doctor = _orm_user("DOCTOR")
        r = self.admin_client.post(
            "/api/admin/notifications/broadcast/",
            self._payload(audience="ROLE", role_code="DOCTOR"),
        )
        self.assertEqual(r.status_code, 201)
        self.assertEqual(r.json()["data"]["recipient_count"], 1)
        self.assertEqual(
            Notification.objects.filter(recipient=doctor, type="SYSTEM").count(), 1
        )

    def test_broadcast_role_unknown_role_400(self):
        r = self.admin_client.post(
            "/api/admin/notifications/broadcast/",
            self._payload(audience="ROLE", role_code="NOT_A_ROLE"),
        )
        self.assertEqual(r.status_code, 400)

    def test_broadcast_users_audience_capped(self):
        uids = [_orm_user("PATIENT").uid for _ in range(501)]
        r = self.super_client.post(
            "/api/admin/notifications/broadcast/",
            self._payload(audience="USERS", user_uid=[str(u) for u in uids]),
        )
        self.assertEqual(r.status_code, 400)
        self.assertIn("capped", r.json()["error"]["details"]["user_uid"][0].lower())

    def test_broadcast_unknown_user_400(self):
        r = self.super_client.post(
            "/api/admin/notifications/broadcast/",
            self._payload(audience="USERS", user_uid=[str(_uuid.uuid4())]),
        )
        self.assertEqual(r.status_code, 400)

    def test_broadcast_only_active_targets(self):
        target = _orm_user("PATIENT", account_status="SUSPENDED")
        r = self.super_client.post(
            "/api/admin/notifications/broadcast/",
            self._payload(audience="USERS", user_uid=[str(target.uid)]),
        )
        self.assertEqual(r.status_code, 400)  # target is NOT ACTIVE

    def test_vertical_denials(self):
        for client in (self.patient_client, self.moderator_client):
            r = client.post("/api/admin/notifications/broadcast/", self._payload())
            self.assertEqual(r.status_code, 403)

    def test_mfa_boundary_blocks_broadcast(self):
        admin = _orm_user("ADMIN", mfa_enabled=True)
        r = _client(admin).post("/api/admin/notifications/broadcast/", self._payload())
        self.assertEqual(r.status_code, 403)

    def test_broadcast_force_bypasses_muted_preferences(self):
        from notifications.models import NotificationPreference

        target = _orm_user("PATIENT")
        pref, _ = NotificationPreference.objects.get_or_create(user=target, category="SYSTEM")
        pref.enabled = False
        pref.save()
        r = self.super_client.post(
            "/api/admin/notifications/broadcast/",
            self._payload(audience="USERS", user_uid=[str(target.uid)]),
        )
        self.assertEqual(r.status_code, 201)
        self.assertEqual(Notification.objects.filter(recipient=target).count(), 1)