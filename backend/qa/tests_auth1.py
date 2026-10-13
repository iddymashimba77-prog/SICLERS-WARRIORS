"""AUTH-1 — identity, roles, verification & authorization acceptance suite.

Covers Stage 4.x acceptance categories that were open after Stage 4.19/4.20:

  * Doctor professional verification (BR-001, FR-DOC-001..004): registry rows
    are never auto-approved; submit → PENDING; VO/ADM/SUP approve/reject/suspend
    via the unified verify endpoint; each decision audited (doctors.verify) and
    a matching SecurityEvent emitted. Clinical/prescription/chat functions gate
    on ``User.is_verified_doctor``.
  * Caregiver relationships (§8.1, C14): invite/accept/decline/remove and the
    consent-scoped permissions endpoint; the CAREGIVER role alone grants NO
    data access — ACTIVE relationship + ACTIVE consent required for reads.
  * Consent authorization (§9, FR-MEDREC-005): grant/amend/revoke/renew,
    immediate revocation, DB-clock expiry, grantee C2 evaluation.
  * Emergency access override (§ C10, FR-EMG-006): the bounded grant is audited
    on issue/expire/revoke and emits EMERGENCY_ACCESS_GRANTED/REVOKED events.
  * SecurityEvent taxonomy: the audit events this stage emits are declared kinds
    (approved security-database-traceability), not free-form strings.

Deny-by-default holds: role grants come from the seeded matrix (accounts 0011),
object conditions (owner / named grantee / consent scope) from the views.
"""

from datetime import timedelta

from django.core.cache import cache
from django.test import TestCase
from django.utils import timezone

from accounts.models import SecurityEvent, User
from audit.models import AuditLog
from doctors.models import Doctor
from medical_records.models import Consent
from patients.models import CaregiverRelationship, Patient

from .qa_helpers import client, orm_user


class DoctorVerificationTests(TestCase):
    """FR-DOC-001..004 verification workflow (database-design §3.4)."""

    def setUp(self):
        cache.clear()

    def _submit(self, c, extra=None):
        payload = {
            "license_number": "GMC-778812",
            "specialty": "HEMATOLOGY",
            "registration_body": "Medical Council",
            "documents": [
                {"doc_type": "LICENSE", "file_url": "secure://docs/778812-license"},
                {"doc_type": "NATIONAL_ID", "file_url": "secure://docs/778812-nida"},
            ],
        }
        payload.update(extra or {})
        return c.post("/api/doctors/me/verification/", payload)

    def test_registration_never_auto_approves(self):
        doctor = orm_user("DOCTOR")
        self.assertFalse(doctor.is_verified_doctor)
        self.assertEqual(Doctor.objects.filter(user=doctor).count(), 0)

    def test_submit_requires_doctor_role(self):
        patient = orm_user("PATIENT")
        resp = self._submit(client(patient))
        self.assertEqual(resp.status_code, 403)

    def test_submit_sets_pending_and_documents(self):
        doctor = orm_user("DOCTOR")
        resp = self._submit(client(doctor))
        self.assertEqual(resp.status_code, 200)
        row = Doctor.objects.get(user=doctor)
        self.assertEqual(row.verification_status, "PENDING")
        self.assertEqual(row.license_number, "GMC-778812")
        self.assertEqual(doctor.verification_documents.filter(status="PENDING").count(), 2)
        self.assertTrue(
            AuditLog.objects.filter(action_code="doctors.verification_submit", resource_id=row.pk).exists()
        )
        self.assertTrue(
            SecurityEvent.objects.filter(user=doctor, event_type="DOCTOR_VERIFICATION_SUBMITTED").exists()
        )

    def test_directory_lists_approved_only(self):
        pending = orm_user("DOCTOR")
        approved = orm_user("DOCTOR")
        Doctor.objects.create(user=pending, verification_status="PENDING")
        Doctor.objects.create(user=approved, verification_status="APPROVED")
        c = client(orm_user("PATIENT"))
        names = [d["uid"] for d in c.get("/api/doctors/").json()["data"]["results"]]
        self.assertIn(str(approved.uid), names)
        self.assertNotIn(str(pending.uid), names)
        self.assertEqual(c.get(f"/api/doctors/{pending.uid}/").status_code, 404)

    def test_verify_requires_doctors_verify_code(self):
        doctor = orm_user("DOCTOR")
        self._submit(client(doctor))
        patient = orm_user("PATIENT")
        resp = client(patient).post(f"/api/admin/doctors/{doctor.uid}/verify/", {"approve": True})
        self.assertEqual(resp.status_code, 403)

    def test_approve_flow_verifies_and_audits(self):
        doctor = orm_user("DOCTOR")
        self._submit(client(doctor))
        officer = orm_user("VERIFICATION_OFFICER")
        oc = client(officer)
        queue = oc.get("/api/admin/doctors/verification-queue/").json()["data"]["results"]
        self.assertEqual([d["uid"] for d in queue], [str(doctor.uid)])
        resp = oc.post(f"/api/admin/doctors/{doctor.uid}/verify/", {"approve": True})
        self.assertEqual(resp.status_code, 200)
        row = Doctor.objects.get(user=doctor)
        self.assertEqual(row.verification_status, "APPROVED")
        self.assertIsNotNone(row.verified_at)
        self.assertEqual(row.verified_by_id, officer.id)
        self.assertTrue(doctor.is_verified_doctor)
        self.assertTrue(
            AuditLog.objects.filter(action_code="doctors.verify", details__approve=True).exists()
        )
        self.assertTrue(
            SecurityEvent.objects.filter(user=officer, event_type="DOCTOR_VERIFIED").exists()
        )
        self.assertEqual(
            oc.get("/api/admin/doctors/verification-queue/").json()["data"]["count"], 0
        )

    def test_reject_requires_reason_and_persists(self):
        doctor = orm_user("DOCTOR")
        self._submit(client(doctor))
        officer = orm_user("VERIFICATION_OFFICER")
        oc = client(officer)
        no_reason = oc.post(f"/api/admin/doctors/{doctor.uid}/verify/", {"approve": False})
        self.assertEqual(no_reason.status_code, 400)
        resp = oc.post(
            f"/api/admin/doctors/{doctor.uid}/verify/",
            {"approve": False, "reason": "License could not be matched to registry."},
        )
        self.assertEqual(resp.status_code, 200)
        row = Doctor.objects.get(user=doctor)
        self.assertEqual(row.verification_status, "REJECTED")
        self.assertEqual(row.rejection_reason, "License could not be matched to registry.")
        self.assertFalse(doctor.is_verified_doctor)

    def test_suspend_requires_reason_and_revokes_verification(self):
        doctor = orm_user("DOCTOR")
        Doctor.objects.create(user=doctor, verification_status="APPROVED")
        officer = orm_user("VERIFICATION_OFFICER")
        oc = client(officer)
        no_reason = oc.post(f"/api/admin/doctors/{doctor.uid}/suspend/", {})
        self.assertEqual(no_reason.status_code, 400)
        resp = oc.post(f"/api/admin/doctors/{doctor.uid}/suspend/", {"reason": "Licensing dispute."})
        self.assertEqual(resp.status_code, 200)
        row = Doctor.objects.get(user=doctor)
        self.assertEqual(row.verification_status, "SUSPENDED")
        # Fresh User instance — the test's in-memory one caches the reverse
        # one-to-one Doctor row from before the suspend.
        self.assertFalse(User.objects.get(pk=doctor.pk).is_verified_doctor)
        self.assertTrue(
            SecurityEvent.objects.filter(user=officer, event_type="DOCTOR_SUSPENDED").exists()
        )

    def test_br001_gates_patient_to_doctor_chat(self):
        pending = orm_user("DOCTOR")
        verified = orm_user("DOCTOR")
        Doctor.objects.create(user=verified, verification_status="APPROVED")
        pc = client(orm_user("PATIENT"))
        denied = pc.post(
            "/api/chat/conversations/",
            {"participant_uid": str(pending.uid), "type": "DOCTOR_PATIENT"},
        )
        self.assertEqual(denied.status_code, 403)
        ok = pc.post(
            "/api/chat/conversations/",
            {"participant_uid": str(verified.uid), "type": "DOCTOR_PATIENT"},
        )
        self.assertEqual(ok.status_code, 201)

    def test_security_event_kinds_are_declared(self):
        required = {
            "REGISTER", "LOGOUT", "PASSWORD_CHANGE",
            "DOCTOR_VERIFICATION_SUBMITTED", "DOCTOR_VERIFIED", "DOCTOR_REJECTED",
            "DOCTOR_SUSPENDED",
            "CONSENT_GRANTED", "CONSENT_RENEWED", "CONSENT_REVOKED",
            "CAREGIVER_INVITED", "CAREGIVER_ACCEPTED", "CAREGIVER_DECLINED",
            "CAREGIVER_REVOKED",
            "EMERGENCY_ACCESS_GRANTED", "EMERGENCY_ACCESS_REVOKED",
        }
        self.assertTrue(required.issubset(set(SecurityEvent.KINDS)))


class CaregiverConsentTests(TestCase):
    """Caregiver links (§8.1) + consent-scoped authorization (C14, §9)."""

    def setUp(self):
        cache.clear()

    def _invite(self, patient, caregiver):
        return client(patient).post(
            "/api/caregivers/",
            {"user_uid": str(caregiver.uid), "relationship_type": "PARENT"},
        )

    def test_invite_requires_patient_and_active_caregiver(self):
        caregiver = orm_user("CAREGIVER")
        other_patient = orm_user("PATIENT")
        denied = client(caregiver).post(
            "/api/caregivers/",
            {"user_uid": str(other_patient.uid), "relationship_type": "PARENT"},
        )
        self.assertEqual(denied.status_code, 403)
        patient = orm_user("PATIENT")
        not_caregiver = orm_user("PATIENT")
        bad = self._invite(patient, not_caregiver)
        self.assertEqual(bad.status_code, 400)
        resp = self._invite(patient, caregiver)
        self.assertEqual(resp.status_code, 201)
        relation = CaregiverRelationship.objects.get(patient__user=patient, user=caregiver)
        self.assertEqual(relation.status, "PENDING")
        self.assertTrue(
            AuditLog.objects.filter(action_code="caregivers.invite", resource_id=relation.pk).exists()
        )
        self.assertTrue(
            SecurityEvent.objects.filter(user=patient, event_type="CAREGIVER_INVITED").exists()
        )

    def test_only_invitee_can_accept_or_decline(self):
        patient = orm_user("PATIENT")
        caregiver = orm_user("CAREGIVER")
        relation = CaregiverRelationship.objects.create(
            patient=Patient.objects.create(user=patient), user=caregiver,
            relationship_type="PARENT", status="PENDING", invited_by=patient,
        )
        wrong = client(patient).post(f"/api/caregivers/{relation.pk}/accept/", {})
        self.assertEqual(wrong.status_code, 403)
        resp = client(caregiver).post(f"/api/caregivers/{relation.pk}/accept/", {})
        self.assertEqual(resp.status_code, 200)
        relation.refresh_from_db()
        self.assertEqual(relation.status, "ACTIVE")
        self.assertIsNotNone(relation.accepted_at)
        self.assertTrue(
            SecurityEvent.objects.filter(user=caregiver, event_type="CAREGIVER_ACCEPTED").exists()
        )

    def test_decline_maps_to_revoked(self):
        patient = orm_user("PATIENT")
        caregiver = orm_user("CAREGIVER")
        relation = CaregiverRelationship.objects.create(
            patient=Patient.objects.create(user=patient), user=caregiver,
            relationship_type="SPOUSE", status="PENDING", invited_by=patient,
        )
        resp = client(caregiver).post(f"/api/caregivers/{relation.pk}/decline/", {})
        self.assertEqual(resp.status_code, 200)
        relation.refresh_from_db()
        self.assertEqual(relation.status, "REVOKED")
        self.assertTrue(
            SecurityEvent.objects.filter(user=caregiver, event_type="CAREGIVER_DECLINED").exists()
        )

    def test_caregiver_role_alone_grants_no_read(self):
        patient = orm_user("PATIENT")
        caregiver = orm_user("CAREGIVER")
        CaregiverRelationship.objects.create(
            patient=Patient.objects.create(user=patient), user=caregiver,
            relationship_type="PARENT", status="ACTIVE", invited_by=patient,
            accepted_at=timezone.now(),
        )
        resp = client(caregiver).get("/api/caregivers/me/patient/")
        self.assertEqual(resp.status_code, 403)

    def test_consent_scope_grants_caregiver_basics(self):
        patient = orm_user("PATIENT")
        caregiver = orm_user("CAREGIVER")
        relation = CaregiverRelationship.objects.create(
            patient=Patient.objects.create(user=patient), user=caregiver,
            relationship_type="PARENT", status="ACTIVE", invited_by=patient,
            accepted_at=timezone.now(),
        )
        scope = client(patient).patch(
            f"/api/caregivers/{relation.pk}/permissions/",
            {
                "resource_type": "patients",
                "permission_scope": ["patients.view"],
                "expires_at": (timezone.now() + timedelta(days=30)).isoformat(),
            },
        )
        self.assertEqual(scope.status_code, 200)
        consent = Consent.objects.get(patient_profile=relation.patient, granted_to=caregiver)
        self.assertEqual(consent.status, "ACTIVE")
        self.assertEqual(consent.permission_scope, ["patients.view"])
        read = client(caregiver).get("/api/caregivers/me/patient/")
        self.assertEqual(read.status_code, 200)
        body = read.json()["data"]
        self.assertEqual(set(body.keys()), {"patient_uid", "first_name", "last_name", "relationship_type"})
        self.assertTrue(
            AuditLog.objects.filter(action_code="consents.grant", resource_id=consent.pk).exists()
        )

    def test_revoke_is_immediate(self):
        patient = orm_user("PATIENT")
        caregiver = orm_user("CAREGIVER")
        relation = CaregiverRelationship.objects.create(
            patient=Patient.objects.create(user=patient), user=caregiver,
            relationship_type="PARENT", status="ACTIVE", invited_by=patient,
            accepted_at=timezone.now(),
        )
        consent = Consent.objects.create(
            patient_profile=relation.patient, granted_to=caregiver,
            resource_type="patients", permission_scope=["patients.view"],
            start_date=timezone.now(), expires_at=timezone.now() + timedelta(days=30),
            status="ACTIVE",
        )
        resp = client(patient).post(f"/api/consents/{consent.uid}/revoke/", {"reason": "No longer needed"})
        self.assertEqual(resp.status_code, 200)
        consent.refresh_from_db()
        self.assertEqual(consent.status, "REVOKED")
        self.assertEqual(client(caregiver).get("/api/caregivers/me/patient/").status_code, 403)
        self.assertTrue(
            SecurityEvent.objects.filter(user=patient, event_type="CONSENT_REVOKED").exists()
        )

    def test_expiry_is_enforced_against_db_clock(self):
        patient = orm_user("PATIENT")
        caregiver = orm_user("CAREGIVER")
        relation = CaregiverRelationship.objects.create(
            patient=Patient.objects.create(user=patient), user=caregiver,
            relationship_type="PARENT", status="ACTIVE", invited_by=patient,
            accepted_at=timezone.now(),
        )
        Consent.objects.create(
            patient_profile=relation.patient, granted_to=caregiver,
            resource_type="patients", permission_scope=["patients.view"],
            start_date=timezone.now() - timedelta(days=1),
            expires_at=timezone.now() - timedelta(seconds=1),
            status="ACTIVE",
        )
        self.assertEqual(client(caregiver).get("/api/caregivers/me/patient/").status_code, 403)

    def test_remove_revokes_link_and_consents(self):
        patient = orm_user("PATIENT")
        caregiver = orm_user("CAREGIVER")
        relation = CaregiverRelationship.objects.create(
            patient=Patient.objects.create(user=patient), user=caregiver,
            relationship_type="PARENT", status="ACTIVE", invited_by=patient,
            accepted_at=timezone.now(),
        )
        consent = Consent.objects.create(
            patient_profile=relation.patient, granted_to=caregiver,
            resource_type="patients", permission_scope=["patients.view"],
            start_date=timezone.now(), expires_at=timezone.now() + timedelta(days=30),
            status="ACTIVE",
        )
        resp = client(patient).delete(f"/api/caregivers/{relation.pk}/", {"reason": "Moved abroad"})
        self.assertEqual(resp.status_code, 204)
        relation.refresh_from_db()
        consent.refresh_from_db()
        self.assertEqual(relation.status, "REVOKED")
        self.assertEqual(consent.status, "REVOKED")
        self.assertTrue(
            AuditLog.objects.filter(action_code="caregivers.remove", resource_id=relation.pk).exists()
        )

    def test_consent_list_is_owner_scoped(self):
        owner = orm_user("PATIENT")
        caregiver = orm_user("CAREGIVER")
        relation = CaregiverRelationship.objects.create(
            patient=Patient.objects.create(user=owner), user=caregiver,
            relationship_type="PARENT", status="ACTIVE", invited_by=owner,
            accepted_at=timezone.now(),
        )
        consent = Consent.objects.create(
            patient_profile=relation.patient, granted_to=caregiver,
            resource_type="patients", permission_scope=["patients.view"],
            start_date=timezone.now(), expires_at=timezone.now() + timedelta(days=30),
            status="ACTIVE",
        )
        stranger = orm_user("PATIENT")
        uids = [r["uid"] for r in client(stranger).get("/api/consents/").json()["data"]["results"]]
        self.assertNotIn(str(consent.uid), uids)
        grantee_uids = [r["uid"] for r in client(caregiver).get("/api/consents/").json()["data"]["results"]]
        self.assertIn(str(consent.uid), grantee_uids)
        active = client(caregiver).get("/api/consents/active/").json()["data"]
        self.assertIn("patients.view", active["permission_scope"])

    def test_consent_actions_are_owner_only(self):
        owner = orm_user("PATIENT")
        caregiver = orm_user("CAREGIVER")
        relation = CaregiverRelationship.objects.create(
            patient=Patient.objects.create(user=owner), user=caregiver,
            relationship_type="PARENT", status="ACTIVE", invited_by=owner,
            accepted_at=timezone.now(),
        )
        consent = Consent.objects.create(
            patient_profile=relation.patient, granted_to=caregiver,
            resource_type="patients", permission_scope=["patients.view"],
            start_date=timezone.now(), expires_at=timezone.now() + timedelta(days=30),
            status="ACTIVE",
        )
        foreign_revoke = client(caregiver).post(
            f"/api/consents/{consent.uid}/revoke/", {"reason": "mine"}
        )
        self.assertEqual(foreign_revoke.status_code, 403)
        renew = client(owner).post(
            f"/api/consents/{consent.uid}/renew/",
            {"expires_at": (timezone.now() + timedelta(days=60)).isoformat()},
        )
        self.assertEqual(renew.status_code, 200)
        consent.refresh_from_db()
        self.assertEqual(consent.status, "ACTIVE")
        self.assertTrue(
            SecurityEvent.objects.filter(user=owner, event_type="CONSENT_RENEWED").exists()
        )


class EmergencyGrantAuditTests(TestCase):
    """C10 bounded override — audited on issue/expire/revoke (FR-EMG-006)."""

    def setUp(self):
        cache.clear()

    def _create(self, user):
        resp = client(user).post(
            "/api/emergency/requests/", {"type": "MEDICAL", "severity": "NORMAL"},
        )
        self.assertEqual(resp.status_code, 201)
        return resp.json()["data"]["uid"]

    def test_issue_is_audited_with_grant_event(self):
        patient = orm_user("PATIENT")
        uid = self._create(patient)
        grant = (
            AuditLog.objects.filter(action_code="emergency.access_grant", details__action="issue")
            .order_by("-created_at")
            .first()
        )
        self.assertIsNotNone(grant)
        self.assertEqual(grant.details["expires_at"] > str(timezone.now()), True)
        self.assertTrue(
            SecurityEvent.objects.filter(
                user=patient, event_type="EMERGENCY_ACCESS_GRANTED"
            ).exists()
        )
        from emergencies.models import EmergencyAccessGrant
        self.assertTrue(
            EmergencyAccessGrant.objects.filter(request__uid=uid, status="ACTIVE").exists()
        )

    def test_cancel_revokes_and_audits(self):
        patient = orm_user("PATIENT")
        uid = self._create(patient)
        resp = client(patient).post(f"/api/emergency/requests/{uid}/cancel/", {})
        self.assertEqual(resp.status_code, 200)
        from emergencies.models import EmergencyAccessGrant
        grant = EmergencyAccessGrant.objects.get(request__uid=uid)
        self.assertEqual(grant.status, "REVOKED")
        self.assertTrue(
            AuditLog.objects.filter(
                action_code="emergency.access_grant", details__action="revoke"
            ).exists()
        )
        self.assertTrue(
            SecurityEvent.objects.filter(
                user=patient, event_type="EMERGENCY_ACCESS_REVOKED", detail__action="revoke"
            ).exists()
        )

    def test_resolve_expires_and_audits(self):
        patient = orm_user("PATIENT")
        uid = self._create(patient)
        admin = orm_user("SUPER_ADMIN")
        resp = client(admin).post(f"/api/emergency/requests/{uid}/resolve/", {})
        self.assertEqual(resp.status_code, 200)
        from emergencies.models import EmergencyAccessGrant
        grant = EmergencyAccessGrant.objects.get(request__uid=uid)
        self.assertEqual(grant.status, "EXPIRED")
        self.assertTrue(
            AuditLog.objects.filter(
                action_code="emergency.access_grant", details__action="expire"
            ).exists()
        )
        self.assertTrue(
            SecurityEvent.objects.filter(
                user=admin, event_type="EMERGENCY_ACCESS_REVOKED", detail__action="expire"
            ).exists()
        )