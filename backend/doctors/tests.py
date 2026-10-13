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
from doctors.models import (
    Conversation,
    Doctor,
    DoctorVerificationDecision,
    Message,
)

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


class DoctorVerificationHistoryTests(TestCase):
    """FR-DOC-006/007: the verification trail is immutable and answerable.

    The failure this prevents: a rejected applicant reapplies and is approved.
    `Doctor.verification_status` says APPROVED and nothing anywhere says the
    licence was doubted first, or why.
    """

    def setUp(self):
        self.doctor_user = _orm_user("DOCTOR")
        self.doctor = Doctor.objects.create(
            user=self.doctor_user,
            license_number=f"LIC-{_uuid.uuid4().hex[:8]}",
            verification_status="PENDING",
        )
        self.vo_user = _orm_user("VERIFICATION_OFFICER")
        self.vo = _client(self.vo_user)
        self.other_user = _orm_user("DOCTOR")
        self.other_doctor = Doctor.objects.create(
            user=self.other_user,
            license_number=f"LIC-{_uuid.uuid4().hex[:8]}",
            verification_status="PENDING",
        )
        self.patient = _client(_orm_user("PATIENT"))

    def _submit(self, client=None, **extra):
        body = {
            "license_number": f"LIC-{_uuid.uuid4().hex[:8]}",
            "documents": [
                {"doc_type": "CERTIFICATE", "file_url": "media/cert-mock.pdf"},
                {"doc_type": "NATIONAL_ID", "file_url": "media/nida-mock.jpg"},
            ],
            **extra,
        }
        return (client or _client(self.doctor_user)).post(
            "/api/doctors/me/verification/", body, format="json"
        )

    def _rows(self, doctor=None):
        return DoctorVerificationDecision.objects.filter(
            doctor=doctor or self.doctor
        ).order_by("pk")

    def _verify(self, approve, reason="", client=None):
        return (client or self.vo).post(
            f"/api/admin/doctors/{self.doctor.user.uid}/verify/",
            {"approve": approve, "reason": reason},
            format="json",
        )

    def _suspend(self, reason="Licence under review", client=None):
        return (client or self.vo).post(
            f"/api/admin/doctors/{self.doctor.user.uid}/suspend/",
            {"reason": reason},
            format="json",
        )

    def test_submission_is_appended_with_the_applicant_as_actor(self):
        response = self._submit()
        self.assertIn(response.status_code, (200, 201))
        rows = self._rows()
        self.assertEqual([r.decision for r in rows], ["SUBMITTED"])
        self.assertEqual(rows[0].actor_id, self.doctor_user.id)
        self.assertEqual(rows[0].to_status, "PENDING")

    def test_rejection_then_resubmit_then_approval_keeps_every_reason(self):
        self._submit()
        self.assertEqual(self._verify(approve=False, reason="Licence number unverifiable").status_code, 200)
        self._submit(specialty="Cardiology")
        self.assertEqual(self._verify(approve=True).status_code, 200)

        rows = self._rows()
        self.assertEqual(
            [r.decision for r in rows], ["SUBMITTED", "REJECTED", "RESUBMITTED", "APPROVED"],
        )
        self.assertEqual(rows[1].reason, "Licence number unverifiable")
        self.assertEqual(rows[1].to_status, "REJECTED")
        self.assertEqual(rows[2].from_status, "REJECTED")
        self.assertEqual(rows[3].actor_id, self.vo_user.id)
        self.assertEqual(rows[3].to_status, "APPROVED")
        # The current row still remembers only the latest outcome...
        self.doctor.refresh_from_db()
        self.assertEqual(self.doctor.verification_status, "APPROVED")
        self.assertEqual(self.doctor.rejection_reason, "")

    def test_suspension_and_reinstatement_are_both_appended(self):
        self._submit()
        self._verify(approve=True)
        self.assertEqual(self._suspend(reason="Suspected fraud").status_code, 200)
        self.doctor.refresh_from_db()
        self.assertEqual(self.doctor.verification_status, "SUSPENDED")

        reinstate = self.vo.post(
            f"/api/admin/doctors/{self.doctor.user.uid}/reinstate/",
            {"reason": "Investigation closed, licence confirmed"},
            format="json",
        )
        self.assertEqual(reinstate.status_code, 200, reinstate.data)
        rows = self._rows()
        self.assertEqual(
            [r.decision for r in rows], ["SUBMITTED", "APPROVED", "SUSPENDED", "REINSTATED"],
        )
        self.assertEqual(rows[2].reason, "Suspected fraud")
        self.assertEqual(rows[3].from_status, "SUSPENDED")
        self.assertEqual(rows[3].to_status, "APPROVED")

    def test_reinstate_requires_a_reason_and_a_suspended_doctor(self):
        self._submit()
        self._verify(approve=True)
        no_reason = self.vo.post(
            f"/api/admin/doctors/{self.doctor.user.uid}/reinstate/", {"reason": "  "}, format="json"
        )
        self.assertEqual(no_reason.status_code, 400)
        not_suspended = self.vo.post(
            f"/api/admin/doctors/{self.doctor.user.uid}/reinstate/",
            {"reason": "no need"}, format="json",
        )
        self.assertEqual(not_suspended.status_code, 400)
        self.assertEqual(self._rows().filter(decision="REINSTATED").count(), 0)

    def test_suspension_requires_a_reason(self):
        self._submit()
        self._verify(approve=True)
        self.assertEqual(
            self.vo.post(
                f"/api/admin/doctors/{self.doctor.user.uid}/suspend/", {}, format="json"
            ).status_code,
            400,
        )
        self.assertEqual(self._rows().filter(decision="SUSPENDED").count(), 0)

    def test_history_is_append_only_at_instance_and_queryset_level(self):
        self._submit()
        row = self._rows()[0]
        row.reason = "rewritten"
        with self.assertRaises(ValueError):
            row.save()
        with self.assertRaises(ValueError):
            row.delete()
        with self.assertRaises(ValueError):
            DoctorVerificationDecision.objects.filter(doctor=self.doctor).update(reason="x")
        with self.assertRaises(ValueError):
            DoctorVerificationDecision.objects.filter(doctor=self.doctor).delete()
        row.refresh_from_db()
        self.assertEqual(row.reason, "")

    def test_history_is_protected_from_its_subject(self):
        self._submit()
        from django.db.models import ProtectedError

        with self.assertRaises(ProtectedError):
            Doctor.objects.filter(pk=self.doctor.pk).delete()
        self.assertEqual(self._rows().count(), 1)

    def test_applicant_reads_their_own_trail(self):
        self._submit()
        self._verify(approve=False, reason="Licence number unverifiable")
        response = _client(self.doctor_user).get(
            f"/api/doctors/{self.doctor.user.uid}/verification-history/"
        )
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.data["verification_status"], "REJECTED")
        self.assertEqual(response.data["count"], 2)
        self.assertEqual(
            [row["decision"] for row in response.data["decisions"]], ["REJECTED", "SUBMITTED"],
        )
        self.assertEqual(
            response.data["decisions"][0]["reason"], "Licence number unverifiable"
        )

    def test_reviewer_reads_any_doctors_trail(self):
        self._submit()
        response = self.vo.get(f"/api/doctors/{self.doctor.user.uid}/verification-history/")
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.data["count"], 1)

    def test_another_doctor_gets_404_not_403(self):
        self._submit()
        response = _client(self.other_user).get(
            f"/api/doctors/{self.doctor.user.uid}/verification-history/"
        )
        self.assertEqual(response.status_code, 404)

    def test_patient_and_anonymous_are_refused(self):
        self._submit()
        self.assertEqual(
            self.patient.get(f"/api/doctors/{self.doctor.user.uid}/verification-history/").status_code,
            404,
        )
        anon = APIClient()
        self.assertEqual(
            anon.get(f"/api/doctors/{self.doctor.user.uid}/verification-history/").status_code, 401
        )

    def test_registry_trail_requires_the_verify_permission(self):
        self._submit()
        response = self.vo.get("/api/admin/doctors/verification-history/")
        self.assertEqual(response.status_code, 200)
        self.assertEqual(len(response.data), 1)
        self.assertEqual(
            self.patient.get("/api/admin/doctors/verification-history/").status_code, 403
        )

    def test_registry_trail_filters_by_decision(self):
        self._submit()
        self._verify(approve=False, reason="nope")
        approvals = self.vo.get("/api/admin/doctors/verification-history/?decision=REJECTED")
        self.assertEqual(approvals.status_code, 200)
        self.assertEqual([r["decision"] for r in approvals.data], ["REJECTED"])
        bad = self.vo.get("/api/admin/doctors/verification-history/?decision=NOPE")
        self.assertEqual(bad.status_code, 400)

    def test_history_endpoint_cannot_be_written_to(self):
        self._submit()
        response = self.vo.post(
            f"/api/doctors/{self.doctor.user.uid}/verification-history/", {}, format="json"
        )
        self.assertEqual(response.status_code, 405)
