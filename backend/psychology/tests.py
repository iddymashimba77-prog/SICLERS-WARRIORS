"""Psychology workspace tests (§2).

Run::

    venv/bin/python manage.py test psychology \
        --settings=config.settings.ephemeral_test

Written against the boundaries rather than the feature list:

* the role gate: no other professional role reaches these endpoints on a
  consent alone (SOCIAL_SUPPORT especially — separation of the two roles);
* consent: reads and writes follow live ``psychology.*`` codes, revoke hides
  rows, an unrelated grant never substitutes;
* verification: a pending registry row cannot write (C5);
* no scoring: defaults are neutral, concerns are validated codes only;
* audit: every write lands in the audit log.
"""

from django.test import TestCase
from django.utils import timezone
from uuid import uuid4

from audit.models import AuditLog
from medical_records import services as med_services
from qa.qa_helpers import client, orm_patient_profile, orm_user
from psychology.models import (
    CONCERN_CODES,
    ProgressNote,
    PsychAssessment,
)

PSY_FULL_SCOPE = [
    "psychology.assessments.create",
    "psychology.assessments.read",
    "psychology.assessments.update",
    "psychology.counseling.manage",
    "psychology.progress_notes.create",
    "psychology.progress_notes.read",
    "psychology.progress_notes.update",
]


def _professional(role_code, *, verified=True):
    """A care-team user with a registry row in the requested state."""
    import uuid

    from doctors.models import Doctor

    user = orm_user(role_code)
    Doctor.objects.create(
        user=user,
        license_number=f"LIC-{uuid.uuid4().hex[:8]}",
        specialty="Clinical psychology" if role_code == "PSYCHOLOGIST" else "Social care",
        verification_status="APPROVED" if verified else "PENDING",
        professional_type=role_code,
    )
    return user


class PsychologyWorkspaceTestBase(TestCase):
    def setUp(self):
        self.psychologist = _professional("PSYCHOLOGIST")
        self.psych_client = client(self.psychologist)
        self.patient_user = orm_user("PATIENT")
        self.patient = orm_patient_profile(self.patient_user)

    def _grant(self, grantee, *codes, days=30):
        return med_services.grant(
            patient=self.patient,
            granted_to=grantee,
            permission_scope=list(codes),
            resource_type="medical_records",
            expires_at=timezone.now() + timezone.timedelta(days=days),
            purpose="mental-health support",
        )

    def _assessment_payload(self, **extra):
        payload = {
            "patient_uid": str(self.patient_user.uid),
            "concerns": ["pain_related_distress", "sleep_difficulties"],
            "notes": "Patient describes night-time pain limiting sleep.",
        }
        payload.update(extra)
        return payload

    def _create_assessment(self):
        response = self.psych_client.post(
            "/api/psychology/assessments/", self._assessment_payload(), format="json",
        )
        self.assertIn(response.status_code, (200, 201), response.data)
        return response


class RoleGateTests(PsychologyWorkspaceTestBase):
    """§2 separation: the psychology workspace answers only to psychology."""

    def test_non_psychologist_roles_are_denied_on_every_endpoint(self):
        self._grant(self.psychologist, *PSY_FULL_SCOPE)
        self._create_assessment()
        endpoints = [
            ("get", "/api/psychology/caseload/"),
            ("get", "/api/psychology/assessments/"),
            ("post", "/api/psychology/assessments/"),
            ("get", "/api/psychology/notes/"),
            ("post", "/api/psychology/notes/"),
            ("get", "/api/psychology/referrals/"),
            ("post", "/api/psychology/referrals/"),
        ]
        for role_code in ("PATIENT", "DOCTOR", "SOCIAL_SUPPORT", "CAREGIVER"):
            intruder = client(orm_user(role_code))
            for method, url in endpoints:
                if method == "get":
                    response = intruder.get(url)
                else:
                    response = intruder.post(
                        url,
                        {
                            "patient_uid": str(self.patient_user.uid),
                            "note": "x",
                            "concerns": [CONCERN_CODES[0]],
                            "destination": "x",
                            "reason": "x",
                        },
                        format="json",
                    )
                self.assertEqual(
                    response.status_code, 403,
                    f"{role_code} reached {method.upper()} {url}: {response.status_code}",
                )

    def test_social_support_role_cannot_read_psychology_rows_even_with_consent(self):
        # The psychological grant is irrelevant: the role itself holds no
        # psychology.* permission code, so separation never leans on consent.
        social = _professional("SOCIAL_SUPPORT")
        self._grant(social, *PSY_FULL_SCOPE)
        self._grant(self.psychologist, *PSY_FULL_SCOPE)
        self._create_assessment()
        response = client(social).get("/api/psychology/assessments/")
        self.assertEqual(response.status_code, 403)


class ConsentTests(PsychologyWorkspaceTestBase):
    def test_create_requires_live_consent(self):
        response = self.psych_client.post(
            "/api/psychology/assessments/", self._assessment_payload(), format="json",
        )
        self.assertEqual(response.status_code, 403, response.data)

    def test_create_and_read_work_under_full_scope(self):
        self._grant(self.psychologist, *PSY_FULL_SCOPE)
        response = self._create_assessment()
        body = response.data
        self.assertEqual(body["patient_uid"], str(self.patient_user.uid))
        self.assertEqual(body["risk_level"], "ROUTINE")
        self.assertEqual(body["impression"], "NONE")

        listed = self.psych_client.get("/api/psychology/assessments/")
        self.assertEqual(listed.status_code, 200)
        self.assertEqual(listed.data["count"], 1)

    def test_write_consent_alone_does_not_grant_read_and_vice_versa(self):
        self._grant(self.psychologist, "psychology.assessments.create")
        self._create_assessment()

        listed = self.psych_client.get("/api/psychology/assessments/")
        self.assertEqual(listed.status_code, 200)
        self.assertEqual(listed.data["count"], 0)

        self._grant(self.psychologist, "psychology.assessments.read")
        listed = self.psych_client.get("/api/psychology/assessments/")
        self.assertEqual(listed.data["count"], 1)

    def test_revoked_consent_hides_existing_rows(self):
        self._grant(self.psychologist, *PSY_FULL_SCOPE)
        self._create_assessment()
        consent = self.psychologist.granted_consents.first()
        consent.status = "REVOKED"
        consent.revoked_by = self.patient_user
        consent.revoked_at = timezone.now()
        consent.save(update_fields=["status", "revoked_by", "revoked_at", "updated_at"])

        listed = self.psych_client.get("/api/psychology/assessments/")
        self.assertEqual(listed.data["count"], 0)

        refused = self.psych_client.post(
            "/api/psychology/assessments/", self._assessment_payload(), format="json",
        )
        self.assertEqual(refused.status_code, 403)

    def test_unrelated_consent_scope_does_not_open_the_workspace(self):
        self._grant(self.psychologist, "medical_records.view", "appointments.view")
        response = self.psych_client.get("/api/psychology/caseload/")
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.data["count"], 0)

    def test_expired_consent_is_denied(self):
        self._grant(self.psychologist, *PSY_FULL_SCOPE)
        consent = self.psychologist.granted_consents.first()
        consent.expires_at = timezone.now() - timezone.timedelta(days=1)
        consent.save(update_fields=["expires_at", "updated_at"])
        response = self.psych_client.get("/api/psychology/caseload/")
        self.assertEqual(response.data["count"], 0)


class VerificationGateTests(PsychologyWorkspaceTestBase):
    def test_pending_registry_row_cannot_write(self):
        pending = _professional("PSYCHOLOGIST", verified=False)
        self._grant(pending, *PSY_FULL_SCOPE)
        response = client(pending).post(
            "/api/psychology/assessments/", self._assessment_payload(), format="json",
        )
        self.assertEqual(response.status_code, 403, response.data)
        self.assertIn("verification", str(response.data))


class CaseloadTests(PsychologyWorkspaceTestBase):
    def test_caseload_shows_consent_patients_and_appointment_patients(self):
        from appointments.models import ClinicAppointment
        from doctors.models import Doctor

        self._grant(self.psychologist, "psychology.assessments.read")

        # Appointment-only patient: visible as a relationship, not as a chart.
        appointment_user = orm_user("PATIENT")
        orm_patient_profile(appointment_user)
        my_row = Doctor.objects.get(user=self.psychologist)
        ClinicAppointment.objects.create(
            patient=appointment_user,
            created_by=appointment_user,
            doctor=my_row,
            scheduled_at=timezone.now() + timezone.timedelta(days=2),
            reason="Follow-up",
        )

        # Unrelated patient must never appear.
        stranger = orm_user("PATIENT")
        orm_patient_profile(stranger)

        response = self.psych_client.get("/api/psychology/caseload/")
        self.assertEqual(response.status_code, 200)
        rows = response.data["results"]
        by_uid = {row["patient_uid"]: row for row in rows}

        self.assertIn(str(self.patient_user.uid), by_uid)
        self.assertTrue(by_uid[str(self.patient_user.uid)]["has_consent"])
        self.assertIn("psychology.assessments.read", by_uid[str(self.patient_user.uid)]["consent_scope"])

        self.assertIn(str(appointment_user.uid), by_uid)
        self.assertFalse(by_uid[str(appointment_user.uid)]["has_consent"])
        self.assertEqual(by_uid[str(appointment_user.uid)]["consent_scope"], [])
        # Upcoming sessions are first-class: the future appointment must show
        # as `next_appointment_at`, not only as the latest scheduled slot.
        self.assertIsNotNone(
            by_uid[str(appointment_user.uid)]["next_appointment_at"]
        )
        self.assertIsNone(
            by_uid[str(self.patient_user.uid)]["next_appointment_at"]
        )

        self.assertNotIn(str(stranger.uid), by_uid)


class AssessmentValidationTests(PsychologyWorkspaceTestBase):
    def setUp(self):
        super().setUp()
        self._grant(self.psychologist, *PSY_FULL_SCOPE)

    def test_unknown_concern_code_is_rejected(self):
        response = self.psych_client.post(
            "/api/psychology/assessments/",
            self._assessment_payload(concerns=["made_up_domain"]),
            format="json",
        )
        self.assertEqual(response.status_code, 400, response.data)

    def test_empty_concerns_and_unknown_patient_are_rejected(self):
        empty = self.psych_client.post(
            "/api/psychology/assessments/",
            self._assessment_payload(concerns=[]),
            format="json",
        )
        self.assertEqual(empty.status_code, 400, empty.data)

        unknown = self.psych_client.post(
            "/api/psychology/assessments/",
            self._assessment_payload(patient_uid=str(uuid4())),
            format="json",
        )
        self.assertEqual(unknown.status_code, 400, unknown.data)

    def test_risk_filter_validates_its_input(self):
        bad = self.psych_client.get("/api/psychology/assessments/?risk_level=CHAOTIC")
        self.assertEqual(bad.status_code, 400)

    def test_create_lands_in_the_audit_log_without_note_content(self):
        response = self._create_assessment()
        assessment = PsychAssessment.objects.get(uid=response.data["uid"])
        row = AuditLog.objects.filter(action_code="psychology.assessments.create").first()
        self.assertIsNotNone(row)
        self.assertEqual(row.actor, self.psychologist)
        self.assertEqual(row.resource_id, assessment.pk)
        self.assertNotIn("night-time pain", str(row.details))


class ProgressNoteTests(PsychologyWorkspaceTestBase):
    def test_note_flow_with_consent(self):
        self._grant(self.psychologist, "psychology.progress_notes.create")
        created = self.psych_client.post(
            "/api/psychology/notes/",
            {"patient_uid": str(self.patient_user.uid), "note": "Session held."},
            format="json",
        )
        self.assertIn(created.status_code, (200, 201), created.data)
        self.assertEqual(
            ProgressNote.objects.filter(patient=self.patient).count(), 1,
        )

        # Read code still missing — the write grant is not a read grant.
        listed = self.psych_client.get("/api/psychology/notes/")
        self.assertEqual(listed.data["count"], 0)

        self._grant(self.psychologist, "psychology.progress_notes.read")
        listed = self.psych_client.get("/api/psychology/notes/")
        self.assertEqual(listed.data["count"], 1)

    def test_note_create_without_consent_is_denied(self):
        response = self.psych_client.post(
            "/api/psychology/notes/",
            {"patient_uid": str(self.patient_user.uid), "note": "Session held."},
            format="json",
        )
        self.assertEqual(response.status_code, 403)


class ReferralTests(PsychologyWorkspaceTestBase):
    def _create_referral(self):
        return self.psych_client.post(
            "/api/psychology/referrals/",
            {
                "patient_uid": str(self.patient_user.uid),
                "destination": "Hospital mental-health unit",
                "reason": "Persistent low mood reported in session.",
                "urgency": "URGENT",
            },
            format="json",
        )

    def test_referral_create_update_and_status_flow(self):
        self._grant(self.psychologist, "psychology.counseling.manage")
        created = self._create_referral()
        self.assertIn(created.status_code, (200, 201), created.data)
        uid = created.data["uid"]
        self.assertEqual(created.data["status"], "REQUESTED")

        patched = self.psych_client.patch(
            f"/api/psychology/referrals/{uid}/",
            {"status": "ACCEPTED", "responsible_person": "Dr Mkumbo"},
            format="json",
        )
        self.assertEqual(patched.status_code, 200, patched.data)
        self.assertEqual(patched.data["status"], "ACCEPTED")
        self.assertEqual(patched.data["responsible_person"], "Dr Mkumbo")

        self.assertTrue(
            AuditLog.objects.filter(action_code="psychology.referrals.update").exists()
        )

        detail = self.psych_client.get(f"/api/psychology/referrals/{uid}/")
        self.assertEqual(detail.status_code, 200)

    def test_referral_needs_consent_and_only_answers_to_its_holder(self):
        # No consent → the list is empty and the detail 404s (deny by default).
        created = self._create_referral()
        self.assertEqual(created.status_code, 403, created.data)

        self._grant(self.psychologist, "psychology.counseling.manage")
        created = self._create_referral()
        uid = created.data["uid"]

        other_psych = _professional("PSYCHOLOGIST")
        hidden = client(other_psych).get(f"/api/psychology/referrals/{uid}/")
        self.assertEqual(hidden.status_code, 404)

    def test_unknown_status_transition_is_rejected(self):
        self._grant(self.psychologist, "psychology.counseling.manage")
        uid = self._create_referral().data["uid"]
        bad = self.psych_client.patch(
            f"/api/psychology/referrals/{uid}/", {"status": "MAYBE"}, format="json",
        )
        self.assertEqual(bad.status_code, 400)


class NoScoringTests(PsychologyWorkspaceTestBase):
    def test_assessment_defaults_are_neutral_and_store_no_score(self):
        self._grant(self.psychologist, *PSY_FULL_SCOPE)
        response = self._create_assessment()
        row = PsychAssessment.objects.get(uid=response.data["uid"])
        self.assertEqual(row.risk_level, "ROUTINE")
        self.assertEqual(row.impression, "NONE")
        self.assertFalse(hasattr(row, "score"))
        self.assertEqual(
            set(row.concerns) & set(CONCERN_CODES), set(row.concerns),
        )

    def test_assessment_list_order_is_newest_first(self):
        self._grant(self.psychologist, *PSY_FULL_SCOPE)
        first = self._create_assessment()
        second = self.psych_client.post(
            "/api/psychology/assessments/",
            self._assessment_payload(assessed_at=str(timezone.now() + timezone.timedelta(hours=1))),
            format="json",
        )
        self.assertIn(second.status_code, (200, 201), second.data)
        listed = self.psych_client.get("/api/psychology/assessments/")
        uids = [row["uid"] for row in listed.data["results"]]
        self.assertEqual(uids[0], second.data["uid"])
        self.assertEqual(uids[1], first.data["uid"])
