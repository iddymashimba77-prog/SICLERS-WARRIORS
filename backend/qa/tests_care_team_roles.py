"""PSYCHOLOGIST / SOCIAL_SUPPORT care-team roles.

Two new clinical-support roles were added to the platform. The risk in adding a
role is that it quietly inherits more than it should, so these tests are written
against the *boundaries* rather than the feature list:

* both roles are `is_system`, but ARE open-registration — a self-registered
  PSYCHOLOGIST/SOCIAL_SUPPORT account must land in the C5 verification pipeline
  and is never auto-approved;
* neither is a doctor — `is_verified_doctor` must stay false for an APPROVED
  psychologist, so no doctor-only gate (prescribing) can be passed by them;
* an unverified professional cannot chat with a patient (C13b);
* SOCIAL_SUPPORT can read a consented chart but cannot write into it;
* PSYCHOLOGIST can write only under a live consent, never on the role alone;
* the directory says which profession a verified person is.

Run::

    venv/bin/python manage.py test qa.tests_care_team_roles \
        --settings=config.settings.ephemeral_test
"""

import uuid

from django.test import TestCase

from doctors.models import Doctor
from medical_records import models as med_models, services as med_services
from qa.qa_helpers import client, directory_facility, orm_patient_profile, orm_user


def _professional(role_code, *, professional_type=None, verified=True, account_status="ACTIVE"):
    """A care-team user with a registry row in the requested state."""
    user = orm_user(role_code, account_status=account_status)
    doctor = Doctor.objects.create(
        user=user,
        license_number=f"LIC-{uuid.uuid4().hex[:8]}",
        specialty="Clinical psychology" if role_code == "PSYCHOLOGIST" else "Social care",
        verification_status="APPROVED" if verified else "PENDING",
        professional_type=professional_type or role_code,
    )
    return user, doctor


class CareTeamRoleSeedTests(TestCase):
    def test_both_roles_exist_with_self_serve_registration_gated_by_verification(self):
        from accounts.models import Role

        for code in ("PSYCHOLOGIST", "SOCIAL_SUPPORT"):
            role = Role.objects.get(code=code)
            self.assertTrue(role.is_system, f"{code} must be a system role")
        # `/api/auth/register/` now accepts the care roles, but never approves:
        # the account gets the role + a verification-required flag, and no
        # registry row is auto-created.
        for role_code in ("PSYCHOLOGIST", "SOCIAL_SUPPORT"):
            response = client(orm_user("PATIENT")).post(
                "/api/auth/register/",
                {
                    "email": f"{role_code.lower()}-{uuid.uuid4().hex[:8]}@example.com",
                    "password": "Str0ng!Pass9",
                    "first_name": "Test",
                    "last_name": "User",
                    "role_code": role_code,
                },
                format="json",
            )
            self.assertEqual(response.status_code, 201, response.data)
            self.assertTrue(response.data["verification_required"])
            self.assertIn(role_code, response.data["user"]["role_codes"])
        self.assertFalse(
            Doctor.objects.filter(professional_type="PSYCHOLOGIST").exists()
            or Doctor.objects.filter(professional_type="SOCIAL_SUPPORT").exists()
        )

    def test_social_support_has_no_clinical_write_or_prescribe_permission(self):
        from accounts.models import Role

        forbidden = {
            "medical_records.create", "medical_records.update",
            "medical_records.upload", "medical_records.delete",
            "medications.prescribe",
        }
        granted = set(
            Role.objects.get(code="SOCIAL_SUPPORT").role_permissions.values_list(
                "permission__code", flat=True
            )
        )
        self.assertEqual(granted & forbidden, set())

    def test_psychologist_does_not_get_prescribing(self):
        from accounts.models import Role

        granted = set(
            Role.objects.get(code="PSYCHOLOGIST").role_permissions.values_list(
                "permission__code", flat=True
            )
        )
        self.assertNotIn("medications.prescribe", granted)
        self.assertIn("medical_records.create", granted)

    def test_admin_can_assign_the_roles_and_registration_requires_verification(self):
        """C17 keeps ADMIN-only assignment for privileged roles; care roles ARE
        self-registerable but land in the C5 verification pipeline."""
        from accounts.serializers import (
            SELF_REGISTERABLE_ROLES,
            VERIFICATION_REQUIRED_ROLE_CODES,
        )

        self.assertIn("PSYCHOLOGIST", SELF_REGISTERABLE_ROLES)
        self.assertIn("SOCIAL_SUPPORT", SELF_REGISTERABLE_ROLES)
        self.assertIn("PSYCHOLOGIST", VERIFICATION_REQUIRED_ROLE_CODES)
        self.assertIn("SOCIAL_SUPPORT", VERIFICATION_REQUIRED_ROLE_CODES)


class ProfessionalIdentityTests(TestCase):
    def test_approved_psychologist_is_not_a_doctor(self):
        user, _ = _professional("PSYCHOLOGIST")
        self.assertTrue(user.is_verified_professional)
        self.assertTrue(user.is_verified_psychologist)
        self.assertFalse(user.is_verified_doctor)

    def test_pending_professional_is_not_verified_at_all(self):
        user, _ = _professional("PSYCHOLOGIST", verified=False)
        self.assertFalse(user.is_verified_professional)
        self.assertFalse(user.is_verified_psychologist)
        self.assertFalse(user.is_verified_doctor)

    def test_suspended_account_is_not_verified(self):
        user, _ = _professional("PSYCHOLOGIST", account_status="SUSPENDED")
        self.assertFalse(user.is_verified_professional)

    def test_psychologist_registry_row_cannot_satisfy_the_doctor_gate(self):
        """A psychologist's own registry row is still professional_type=PSYCHOLOGIST."""
        user, doctor = _professional("PSYCHOLOGIST")
        self.assertEqual(doctor.professional_type, "PSYCHOLOGIST")
        user.refresh_from_db()
        self.assertFalse(user.is_verified_doctor)

    def test_doctor_keeps_the_doctor_gate(self):
        user, _ = _professional("DOCTOR", professional_type="DOCTOR")
        self.assertTrue(user.is_verified_professional)
        self.assertTrue(user.is_verified_doctor)

    def test_submit_rejects_a_professional_type_that_contradicts_the_role(self):
        """A DOCTOR account cannot file itself as a psychologist."""
        user, _ = _professional("DOCTOR", professional_type="DOCTOR", verified=False)
        response = client(user).post(
            "/api/doctors/me/verification/",
            {
                "license_number": f"LIC-{uuid.uuid4().hex[:8]}",
                "professional_type": "PSYCHOLOGIST",
                "documents": [
                    {"doc_type": "CERTIFICATE", "file_url": "media/cert-mock.pdf"},
                    {"doc_type": "NATIONAL_ID", "file_url": "media/nida-mock.jpg"},
                ],
            },
            format="json",
        )
        self.assertEqual(response.status_code, 400, response.data)
        self.assertIn("professional_type", response.data["error"]["details"])

    def test_psychologist_submits_as_a_psychologist_and_lands_in_the_queue(self):
        user, doctor = _professional("PSYCHOLOGIST", verified=False)
        response = client(user).post(
            "/api/doctors/me/verification/",
            {
                "license_number": f"LIC-{uuid.uuid4().hex[:8]}",
                "specialty": "Clinical psychology",
                "professional_type": "PSYCHOLOGIST",
                "documents": [
                    {"doc_type": "CERTIFICATE", "file_url": "media/cert-mock.pdf"},
                    {"doc_type": "NATIONAL_ID", "file_url": "media/nida-mock.jpg"},
                ],
            },
            format="json",
        )
        self.assertIn(response.status_code, (200, 201), response.data)
        doctor.refresh_from_db()
        self.assertEqual(doctor.professional_type, "PSYCHOLOGIST")
        self.assertEqual(doctor.verification_status, "PENDING")

        queue = client(orm_user("VERIFICATION_OFFICER")).get(
            "/api/admin/doctors/verification-queue/?professional_type=PSYCHOLOGIST"
        )
        self.assertEqual(queue.status_code, 200)
        self.assertEqual([r["uid"] for r in queue.data["results"]], [str(user.uid)])

    def test_queue_rejects_an_unknown_professional_type(self):
        response = client(orm_user("VERIFICATION_OFFICER")).get(
            "/api/admin/doctors/verification-queue/?professional_type=WIZARD"
        )
        self.assertEqual(response.status_code, 400)


class ProfessionalDirectoryTests(TestCase):
    def test_directory_filters_by_profession(self):
        psychologist, _ = _professional("PSYCHOLOGIST")
        doctor_user, _ = _professional("DOCTOR", professional_type="DOCTOR")
        response = client(orm_user("PATIENT")).get(
            "/api/doctors/?professional_type=PSYCHOLOGIST"
        )
        self.assertEqual(response.status_code, 200)
        uids = [r["uid"] for r in response.data["results"]]
        self.assertEqual(uids, [str(psychologist.uid)])
        self.assertNotIn(str(doctor_user.uid), uids)

    def test_directory_serializes_the_profession(self):
        psychologist, _ = _professional("PSYCHOLOGIST")
        response = client(orm_user("PATIENT")).get("/api/doctors/")
        row = [r for r in response.data["results"] if r["uid"] == str(psychologist.uid)][0]
        self.assertEqual(row["professional_type"], "PSYCHOLOGIST")

    def test_unverified_professionals_stay_out_of_the_directory(self):
        _, pending = _professional("PSYCHOLOGIST", verified=False)
        response = client(orm_user("PATIENT")).get("/api/doctors/")
        self.assertNotIn(str(pending.user.uid), [r["uid"] for r in response.data["results"]])


class CareTeamChatTests(TestCase):
    def test_patient_can_chat_with_a_verified_psychologist(self):
        psychologist, _ = _professional("PSYCHOLOGIST")
        patient = orm_user("PATIENT")
        response = client(patient).post(
            "/api/chat/conversations/",
            {"participant_uid": str(psychologist.uid), "type": "DOCTOR_PATIENT"},
            format="json",
        )
        self.assertEqual(response.status_code, 201, response.data)

    def test_patient_can_chat_with_a_verified_social_support_worker(self):
        social, _ = _professional("SOCIAL_SUPPORT")
        patient = orm_user("PATIENT")
        response = client(patient).post(
            "/api/chat/conversations/",
            {"participant_uid": str(social.uid), "type": "DOCTOR_PATIENT"},
            format="json",
        )
        self.assertEqual(response.status_code, 201, response.data)

    def test_patient_cannot_chat_with_an_unverified_psychologist(self):
        pending, _ = _professional("PSYCHOLOGIST", verified=False)
        patient = orm_user("PATIENT")
        response = client(patient).post(
            "/api/chat/conversations/",
            {"participant_uid": str(pending.uid), "type": "DOCTOR_PATIENT"},
            format="json",
        )
        self.assertEqual(response.status_code, 403)

    def test_unverified_psychologist_cannot_open_a_conversation_with_a_patient(self):
        pending, _ = _professional("PSYCHOLOGIST", verified=False)
        patient = orm_user("PATIENT")
        response = client(pending).post(
            "/api/chat/conversations/",
            {"participant_uid": str(patient.uid), "type": "DOCTOR_PATIENT"},
            format="json",
        )
        self.assertEqual(response.status_code, 403)


class CareTeamChartAccessTests(TestCase):
    def setUp(self):
        self.patient_user = orm_user("PATIENT")
        self.patient = orm_patient_profile(self.patient_user)
        self.facility = directory_facility()
        self.category = med_models.RecordCategory.objects.create(
            code="SESSION_NOTE", name="Session note",
        )
        self.record = self._record("Initial assessment", self.patient, self.patient_user)
        self.psychologist, _ = _professional("PSYCHOLOGIST")
        self.social, _ = _professional("SOCIAL_SUPPORT")

    def _record(self, title, patient, author, description=""):
        from django.utils import timezone

        return med_models.MedicalRecord.objects.create(
            patient=patient,
            category=self.category,
            title=title,
            description=description,
            recorded_by=author,
            recorded_at=timezone.now() - timezone.timedelta(days=1),
            facility=self.facility,
        )

    def _consent(self, grantee, *codes):
        from django.utils import timezone

        return med_services.grant(
            patient=self.patient,
            granted_to=grantee,
            permission_scope=list(codes),
            resource_type="medical_records",
            expires_at=timezone.now() + timezone.timedelta(days=30),
            purpose="treatment",
        )

    def test_psychologist_reads_a_consented_chart(self):
        self._consent(self.psychologist, "medical_records.view")
        response = client(self.psychologist).get(f"/api/medical-records/{self.record.uid}/")
        self.assertEqual(response.status_code, 200)

    def test_psychologist_without_consent_sees_nothing(self):
        response = client(self.psychologist).get(f"/api/medical-records/{self.record.uid}/")
        self.assertEqual(response.status_code, 404)

    def test_psychologist_writes_only_under_a_live_consent(self):
        without = client(self.psychologist).post(
            "/api/medical-records/",
            {
                "patient_uid": str(self.patient_user.uid),
                "title": "Unconsented note",
                "category_code": "SESSION_NOTE",
            },
            format="json",
        )
        self.assertEqual(without.status_code, 403)

        self._consent(self.psychologist, "medical_records.create")
        with_consent = client(self.psychologist).post(
            "/api/medical-records/",
            {
                "patient_uid": str(self.patient_user.uid),
                "title": "Therapy note",
                "category_code": "SESSION_NOTE",
                "description": "CBT session 1.",
            },
            format="json",
        )
        self.assertEqual(with_consent.status_code, 201, with_consent.data)
        self.assertEqual(with_consent.data["recorded_by_uid"], str(self.psychologist.uid))

    def test_social_support_reads_a_consented_chart(self):
        self._consent(self.social, "medical_records.view")
        response = client(self.social).get(f"/api/medical-records/{self.record.uid}/")
        self.assertEqual(response.status_code, 200)

    def test_social_support_cannot_write_into_a_chart_even_with_consent(self):
        """C15 is the point: consent grants *access*, it does not confer authorship."""
        self._consent(self.social, "medical_records.view", "medical_records.create")
        response = client(self.social).post(
            "/api/medical-records/",
            {
                "patient_uid": str(self.patient_user.uid),
                "title": "Support note",
                "category_code": "SESSION_NOTE",
            },
            format="json",
        )
        self.assertEqual(response.status_code, 403)
        self.assertEqual(
            med_models.MedicalRecord.objects.filter(title="Support note").count(), 0
        )

    def test_social_support_cannot_delete_a_record(self):
        self._consent(self.social, "medical_records.view")
        response = client(self.social).delete(f"/api/medical-records/{self.record.uid}/")
        self.assertEqual(response.status_code, 403)

    def test_patient_keeps_full_control_of_their_own_chart(self):
        """A care-team role must not widen what the patient sees either."""
        other_user = orm_user("PATIENT")
        other = orm_patient_profile(other_user)
        other_record = self._record("Another patient's note", other, other_user)
        self._consent(self.psychologist, "medical_records.view")
        response = client(self.psychologist).get(f"/api/medical-records/{other_record.uid}/")
        self.assertEqual(response.status_code, 404)