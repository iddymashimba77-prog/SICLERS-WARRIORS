"""Backend tests for the Stage 4.10 private chat API.

Run::

    venv/bin/python manage.py test doctors --settings=config.settings.ephemeral_test

Covers: conversation creation with C13b/C13 enforcement, membership-scoped
isolation (non-participant → 404, admins hold no chat.* code), message send/
read/delete tombstone, leave/close, add-participant privacy guard, sanitization,
unread counts and audit rows.
"""

import uuid as _uuid

from django.core.cache import cache
from django.test import TestCase
from rest_framework.test import APIClient
from rest_framework_simplejwt.tokens import RefreshToken

from accounts.models import Role, User, UserRole
from audit.models import AuditLog
from doctors.models import Conversation, Doctor, Message

_PASSWORD = "Str0ng!Pass9"


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
    client = APIClient()
    client.credentials(HTTP_AUTHORIZATION=f"Bearer {RefreshToken.for_user(user).access_token}")
    return client


class ChatApiTests(TestCase):
    def setUp(self):
        cache.clear()
        self.doctor = _orm_user("DOCTOR")
        self.doctor_client = _client(self.doctor)
        self.patient = _orm_user("PATIENT")
        self.patient_client = _client(self.patient)
        self.other_patient = _orm_user("PATIENT")
        self.other_client = _client(self.other_patient)
        self.unverified_doctor = _orm_user("DOCTOR", account_status="PENDING_VERIFICATION")
        self.admin_client = _client(_orm_user("SUPER_ADMIN"))
        # AUTH-1 (BR-001): chat's C13b gate keys on professional verification —
        # the verified doctor carries an APPROVED `doctors` row, the other a
        # REJECTED one, so the patient->doctor rule stays testable.
        Doctor.objects.create(user=self.doctor, verification_status="APPROVED")
        Doctor.objects.create(user=self.unverified_doctor, verification_status="REJECTED")

    def _start(self, client, partner_uid):
        return client.post(
            "/api/chat/conversations/", {"participant_uid": str(partner_uid)}, format="json",
        )

    # --- creation / C13b -----------------------------------------------------
    def test_verified_doctor_can_start_with_patient(self):
        resp = self._start(self.doctor_client, self.patient.uid)
        self.assertEqual(resp.status_code, 201)
        self.assertEqual(resp.data["type"], "DOCTOR_PATIENT")
        self.assertEqual(len(resp.data["participants"]), 2)
        conv = Conversation.objects.get(uid=resp.data["uid"])
        self.assertEqual(conv.participants.filter(status="ACTIVE").count(), 2)
        self.assertTrue(AuditLog.objects.filter(action_code="conversations.create").exists())

    def test_patient_needs_verified_doctor_partner(self):
        denied = self._start(self.patient_client, self.unverified_doctor.uid)
        self.assertEqual(denied.status_code, 403)
        peer = self._start(self.patient_client, self.other_patient.uid)
        self.assertEqual(peer.status_code, 403)
        ok = self._start(self.patient_client, self.doctor.uid)
        self.assertEqual(ok.status_code, 201)

    def test_self_and_unknown_partner_rejected(self):
        self.assertEqual(self._start(self.doctor_client, self.doctor.uid).status_code, 400)
        self.assertEqual(self._start(self.doctor_client, _uuid.uuid4()).status_code, 400)

    def test_admin_cannot_start(self):
        self.assertEqual(self._start(self.admin_client, self.patient.uid).status_code, 403)

    # --- isolation -----------------------------------------------------------
    def test_non_participant_gets_404(self):
        uid = self._start(self.doctor_client, self.patient.uid).data["uid"]
        self.assertEqual(self.doctor_client.get(f"/api/chat/conversations/{uid}/").status_code, 200)
        self.assertEqual(self.other_client.get(f"/api/chat/conversations/{uid}/").status_code, 404)
        self.assertEqual(
            self.other_client.get(f"/api/chat/conversations/{uid}/messages/").status_code, 404,
        )
        self.assertEqual(
            self.other_client.post(
                f"/api/chat/conversations/{uid}/messages/", {"content": "hi"}, format="json",
            ).status_code,
            404,
        )

    def test_admin_sees_no_conversations(self):
        self._start(self.doctor_client, self.patient.uid)
        listing = self.admin_client.get("/api/chat/conversations/")
        self.assertEqual(listing.status_code, 200)
        self.assertEqual(listing.data["count"], 0)

    # --- messages ------------------------------------------------------------
    def test_send_list_sanitize_and_audit(self):
        uid = self._start(self.doctor_client, self.patient.uid).data["uid"]
        sent = self.doctor_client.post(
            f"/api/chat/conversations/{uid}/messages/",
            {"content": '<script>x</script>Hello <b>there</b>'},
            format="json",
        )
        self.assertEqual(sent.status_code, 201)
        self.assertNotIn("<script", sent.data["content"])
        self.assertIn("<b>there</b>", sent.data["content"])
        self.assertTrue(sent.data["is_mine"])
        self.assertTrue(AuditLog.objects.filter(action_code="messages.send").exists())
        listing = self.patient_client.get(f"/api/chat/conversations/{uid}/messages/")
        self.assertEqual(listing.data["count"], 1)

    def test_unread_count_and_read(self):
        uid = self._start(self.doctor_client, self.patient.uid).data["uid"]
        self.doctor_client.post(
            f"/api/chat/conversations/{uid}/messages/", {"content": "ping"}, format="json",
        )
        listing = self.patient_client.get("/api/chat/conversations/")
        self.assertEqual(listing.data["results"][0]["unread_count"], 1)
        read = self.patient_client.post(f"/api/chat/conversations/{uid}/read/")
        self.assertEqual(read.status_code, 200)
        listing = self.patient_client.get("/api/chat/conversations/")
        self.assertEqual(listing.data["results"][0]["unread_count"], 0)

    def test_message_delete_is_sender_only_tombstone(self):
        uid = self._start(self.doctor_client, self.patient.uid).data["uid"]
        msg = self.patient_client.post(
            f"/api/chat/conversations/{uid}/messages/", {"content": "secret"}, format="json",
        ).data
        # The other participant cannot delete a message they did not send.
        denied = self.doctor_client.delete(
            f"/api/chat/conversations/{uid}/messages/{msg['uid']}/",
        )
        self.assertEqual(denied.status_code, 403)
        ok = self.patient_client.delete(
            f"/api/chat/conversations/{uid}/messages/{msg['uid']}/",
        )
        self.assertEqual(ok.status_code, 204)
        row = Message.objects.get(uid=msg["uid"])
        self.assertIsNotNone(row.deleted_at)
        self.assertEqual(row.content, "")
        listing = self.doctor_client.get(f"/api/chat/conversations/{uid}/messages/")
        self.assertEqual(listing.data["results"][0]["content"], "")
        self.assertTrue(listing.data["results"][0]["deleted"])

    # --- leave / add participant --------------------------------------------
    def test_leave_closes_when_empty(self):
        uid = self._start(self.doctor_client, self.patient.uid).data["uid"]
        self.assertEqual(self.patient_client.post(f"/api/chat/conversations/{uid}/leave/").status_code, 200)
        self.assertEqual(self.patient_client.get(f"/api/chat/conversations/{uid}/").status_code, 404)
        self.doctor_client.post(f"/api/chat/conversations/{uid}/leave/")
        self.assertEqual(Conversation.objects.get(uid=uid).status, "CLOSED")

    def test_add_participant_denied_for_doctor_patient(self):
        uid = self._start(self.doctor_client, self.patient.uid).data["uid"]
        resp = self.doctor_client.post(
            f"/api/chat/conversations/{uid}/add-participant/",
            {"user_uid": str(self.other_patient.uid)},
            format="json",
        )
        self.assertEqual(resp.status_code, 400)
