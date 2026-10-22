"""Social-support workspace tests (§3).

Run::

    venv/bin/python manage.py test social_work \
        --settings=config.settings.ephemeral_test

Written against the boundaries rather than the feature list:

* the role gate: PSYCHOLOGIST, DOCTOR, PATIENT … never reach social URLs,
  even holding a social consent (separation of the two roles);
* consent: every read/write follows a live ``social.*`` code;
* verification: a pending registry row cannot write (C5);
* state machines: case and referral status only move through allowed edges;
* no financial system: ``linked_workflow`` is a plain pointer, nothing else;
* audit: every write lands in the audit log without note content.
"""

from datetime import timedelta
from uuid import uuid4

from django.test import TestCase
from django.utils import timezone

from audit.models import AuditLog
from medical_records import services as med_services
from qa.qa_helpers import client, orm_patient_profile, orm_user
from social_work.models import (
    NEED_CODES,
    CaseNote,
    SocialCase,
    SocialNeedsAssessment,
    SocialReferral,
)

SOCIAL_FULL_SCOPE = [
    "social.cases.create",
    "social.cases.read",
    "social.cases.update",
    "social.resources.manage",
    "social.referrals.create",
    "social.referrals.read",
    "social.referrals.update",
    "social.family_support.manage",
]


def _professional(role_code, *, verified=True):
    import uuid

    from doctors.models import Doctor

    user = orm_user(role_code)
    Doctor.objects.create(
        user=user,
        license_number=f"LIC-{uuid.uuid4().hex[:8]}",
        specialty="Social care",
        verification_status="APPROVED" if verified else "PENDING",
        professional_type=role_code,
    )
    return user


class SocialWorkspaceTestBase(TestCase):
    def setUp(self):
        self.worker = _professional("SOCIAL_SUPPORT")
        self.worker_client = client(self.worker)
        self.patient_user = orm_user("PATIENT")
        self.patient = orm_patient_profile(self.patient_user)

    def _grant(self, grantee, *codes, days=30):
        return med_services.grant(
            patient=self.patient,
            granted_to=grantee,
            permission_scope=list(codes),
            resource_type="medical_records",
            expires_at=timezone.now() + timedelta(days=days),
            purpose="social support",
        )

    def _open_case(self, **extra):
        payload = {
            "patient_uid": str(self.patient_user.uid),
            "title": "Transport to monthly clinic visit",
        }
        payload.update(extra)
        response = self.worker_client.post("/api/social/cases/", payload, format="json")
        self.assertIn(response.status_code, (200, 201), response.data)
        return response.data


class RoleGateTests(SocialWorkspaceTestBase):
    """§3 separation: the social workspace answers only to social work."""

    def test_non_social_roles_are_denied_on_every_endpoint(self):
        self._grant(self.worker, *SOCIAL_FULL_SCOPE)
        self._open_case()
        endpoints = [
            ("get", "/api/social/caseload/"),
            ("get", "/api/social/cases/"),
            ("post", "/api/social/cases/"),
            ("get", "/api/social/needs/"),
            ("post", "/api/social/needs/"),
            ("get", "/api/social/referrals/"),
            ("post", "/api/social/referrals/"),
        ]
        for role_code in ("PATIENT", "DOCTOR", "PSYCHOLOGIST", "CAREGIVER"):
            intruder = client(orm_user(role_code))
            for method, url in endpoints:
                if method == "get":
                    response = intruder.get(url)
                else:
                    response = intruder.post(
                        url,
                        {
                            "patient_uid": str(self.patient_user.uid),
                            "title": "x",
                            "needs": [NEED_CODES[0]],
                            "destination": "x",
                            "reason": "x",
                        },
                        format="json",
                    )
                self.assertEqual(
                    response.status_code, 403,
                    f"{role_code} reached {method.upper()} {url}: {response.status_code}",
                )

    def test_psychologist_with_social_consent_is_still_denied(self):
        psychologist = _professional("PSYCHOLOGIST")
        self._grant(psychologist, *SOCIAL_FULL_SCOPE)
        response = client(psychologist).get("/api/social/cases/")
        self.assertEqual(response.status_code, 403)


class ConsentTests(SocialWorkspaceTestBase):
    def test_case_create_requires_live_consent(self):
        response = self.worker_client.post(
            "/api/social/cases/",
            {"patient_uid": str(self.patient_user.uid), "title": "x"},
            format="json",
        )
        self.assertEqual(response.status_code, 403, response.data)

    def test_case_create_and_read_work_under_full_scope(self):
        self._grant(self.worker, *SOCIAL_FULL_SCOPE)
        created = self._open_case()
        self.assertEqual(created["status"], "NEW")
        self.assertEqual(created["patient_uid"], str(self.patient_user.uid))

        listed = self.worker_client.get("/api/social/cases/")
        self.assertEqual(listed.status_code, 200)
        self.assertEqual(listed.data["count"], 1)

    def test_revoked_consent_hides_existing_cases(self):
        self._grant(self.worker, *SOCIAL_FULL_SCOPE)
        self._open_case()
        consent = self.worker.granted_consents.first()
        consent.status = "REVOKED"
        consent.revoked_by = self.patient_user
        consent.revoked_at = timezone.now()
        consent.save(update_fields=["status", "revoked_by", "revoked_at", "updated_at"])

        listed = self.worker_client.get("/api/social/cases/")
        self.assertEqual(listed.data["count"], 0)

        refused = self.worker_client.post(
            "/api/social/cases/",
            {"patient_uid": str(self.patient_user.uid), "title": "x"},
            format="json",
        )
        self.assertEqual(refused.status_code, 403)

    def test_read_consent_alone_does_not_grant_writes(self):
        self._grant(self.worker, "social.cases.read")
        listed = self.worker_client.get("/api/social/cases/")
        self.assertEqual(listed.status_code, 200)
        self.assertEqual(listed.data["count"], 0)

        refused = self.worker_client.post(
            "/api/social/cases/",
            {"patient_uid": str(self.patient_user.uid), "title": "x"},
            format="json",
        )
        self.assertEqual(refused.status_code, 403)

    def test_unrelated_consent_scope_does_not_open_the_workspace(self):
        self._grant(self.worker, "psychology.assessments.read", "medical_records.view")
        response = self.worker_client.get("/api/social/caseload/")
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.data["count"], 0)


class VerificationGateTests(SocialWorkspaceTestBase):
    def test_pending_registry_row_cannot_write(self):
        pending = _professional("SOCIAL_SUPPORT", verified=False)
        self._grant(pending, *SOCIAL_FULL_SCOPE)
        response = client(pending).post(
            "/api/social/cases/",
            {"patient_uid": str(self.patient_user.uid), "title": "x"},
            format="json",
        )
        self.assertEqual(response.status_code, 403, response.data)
        self.assertIn("verification", str(response.data))


class CaseWorkflowTests(SocialWorkspaceTestBase):
    def setUp(self):
        super().setUp()
        self._grant(self.worker, *SOCIAL_FULL_SCOPE)
        self.case_uid = self._open_case()["uid"]

    def test_status_moves_only_through_the_state_machine(self):
        def move(to):
            return self.worker_client.patch(
                f"/api/social/cases/{self.case_uid}/", {"status": to}, format="json",
            )

        self.assertEqual(move("IN_PROGRESS").status_code, 200)
        self.assertEqual(move("AWAITING_REFERRAL").status_code, 200)
        self.assertEqual(move("RESOLVED").status_code, 200)

        case = SocialCase.objects.get(uid=self.case_uid)
        self.assertIsNotNone(case.closed_at)

        self.assertEqual(move("IN_PROGRESS").status_code, 200)  # reopen
        case.refresh_from_db()
        self.assertIsNone(case.closed_at)

        bad = move("NEW")
        self.assertEqual(bad.status_code, 400, bad.data)

    def test_write_requires_case_update_consent(self):
        # READ grant alone: detail visible, transition refused.
        only_read = SocialCase.objects.get(uid=self.case_uid)
        only_read.status = "NEW"
        only_read.save()
        self.worker.granted_consents.all().delete()
        self._grant(self.worker, "social.cases.read")
        visible = self.worker_client.get(f"/api/social/cases/{self.case_uid}/")
        self.assertEqual(visible.status_code, 200)
        refused = self.worker_client.patch(
            f"/api/social/cases/{self.case_uid}/", {"status": "IN_PROGRESS"}, format="json",
        )
        self.assertEqual(refused.status_code, 403)

    def test_other_worker_without_consent_sees_404(self):
        other = _professional("SOCIAL_SUPPORT")
        hidden = client(other).get(f"/api/social/cases/{self.case_uid}/")
        self.assertEqual(hidden.status_code, 404)

    def test_status_update_is_audited(self):
        self.worker_client.patch(
            f"/api/social/cases/{self.case_uid}/", {"status": "IN_PROGRESS"}, format="json",
        )
        row = AuditLog.objects.filter(action_code="social.cases.update").first()
        self.assertIsNotNone(row)
        self.assertEqual(row.actor, self.worker)


class CaseNoteTests(SocialWorkspaceTestBase):
    def setUp(self):
        super().setUp()
        self._grant(self.worker, *SOCIAL_FULL_SCOPE)
        self.case_uid = self._open_case()["uid"]

    def test_note_flow_and_read_scope(self):
        created = self.worker_client.post(
            f"/api/social/cases/{self.case_uid}/notes/",
            {"note": "Called the patient; transport arranged."},
            format="json",
        )
        self.assertIn(created.status_code, (200, 201), created.data)
        self.assertEqual(CaseNote.objects.filter(case__uid=self.case_uid).count(), 1)

        listed = self.worker_client.get(f"/api/social/cases/{self.case_uid}/notes/")
        self.assertEqual(listed.status_code, 200)
        self.assertEqual(listed.data["count"], 1)

        # Without read consent the notes list comes back empty, not leaked.
        self.worker.granted_consents.all().delete()
        listed = self.worker_client.get(f"/api/social/cases/{self.case_uid}/notes/")
        self.assertEqual(listed.status_code, 200)
        self.assertEqual(listed.data["count"], 0)

    def test_note_write_without_consent_is_denied(self):
        self.worker.granted_consents.all().delete()
        response = self.worker_client.post(
            f"/api/social/cases/{self.case_uid}/notes/", {"note": "x"}, format="json",
        )
        self.assertEqual(response.status_code, 403)

    def test_unknown_case_404s(self):
        response = self.worker_client.get(f"/api/social/cases/{uuid4()}/notes/")
        self.assertEqual(response.status_code, 404)


class NeedsAssessmentTests(SocialWorkspaceTestBase):
    def setUp(self):
        super().setUp()
        self._grant(self.worker, *SOCIAL_FULL_SCOPE)

    def _payload(self, **extra):
        payload = {
            "patient_uid": str(self.patient_user.uid),
            "needs": ["food_security", "transport_to_care"],
            "observations": "Family reports food runs out before month end.",
        }
        payload.update(extra)
        return payload

    def test_create_list_and_needs_validation(self):
        created = self.worker_client.post(
            "/api/social/needs/", self._payload(), format="json",
        )
        self.assertIn(created.status_code, (200, 201), created.data)
        self.assertEqual(
            created.data["needs"], ["food_security", "transport_to_care"],
        )

        listed = self.worker_client.get("/api/social/needs/")
        self.assertEqual(listed.data["count"], 1)

        bad_code = self.worker_client.post(
            "/api/social/needs/", self._payload(needs=["made_up_need"]), format="json",
        )
        self.assertEqual(bad_code.status_code, 400)

        empty = self.worker_client.post(
            "/api/social/needs/", self._payload(needs=[]), format="json",
        )
        self.assertEqual(empty.status_code, 400)

    def test_audit_row_carries_no_observations(self):
        created = self.worker_client.post(
            "/api/social/needs/", self._payload(), format="json",
        )
        row = AuditLog.objects.filter(action_code="social.needs.create").first()
        self.assertIsNotNone(row)
        self.assertNotIn("food runs out", str(row.details))
        self.assertEqual(
            row.resource_id,
            SocialNeedsAssessment.objects.get(uid=created.data["uid"]).pk,
        )


class ReferralWorkflowTests(SocialWorkspaceTestBase):
    def setUp(self):
        super().setUp()
        self._grant(self.worker, *SOCIAL_FULL_SCOPE)
        self.case_uid = self._open_case()["uid"]

    def _create_referral(self):
        return self.worker_client.post(
            "/api/social/referrals/",
            {
                "patient_uid": str(self.patient_user.uid),
                "case_uid": self.case_uid,
                "destination": "District social welfare office",
                "reason": "Food support requested.",
                "urgency": "URGENT",
                "responsible_person": "Mfumo wa jamii officer",
                "follow_up_at": str(timezone.now() + timedelta(days=7)),
            },
            format="json",
        )

    def test_referral_keeps_owner_and_follow_up_and_moves_through_states(self):
        created = self._create_referral()
        self.assertIn(created.status_code, (200, 201), created.data)
        uid = created.data["uid"]
        self.assertEqual(created.data["status"], "REQUESTED")
        self.assertEqual(created.data["responsible_person"], "Mfumo wa jamii officer")
        self.assertIsNotNone(created.data["follow_up_at"])
        self.assertEqual(created.data["case_uid"], self.case_uid)

        accepted = self.worker_client.patch(
            f"/api/social/referrals/{uid}/", {"status": "ACCEPTED"}, format="json",
        )
        self.assertEqual(accepted.status_code, 200, accepted.data)

        # REQUESTED cannot jump straight to COMPLETED (machine edge check).
        second = self._create_referral()
        second_uid = second.data["uid"]
        direct = self.worker_client.patch(
            f"/api/social/referrals/{second_uid}/", {"status": "COMPLETED"}, format="json",
        )
        self.assertEqual(direct.status_code, 400, direct.data)

        # Terminal states refuse further movement.
        self.worker_client.patch(
            f"/api/social/referrals/{uid}/", {"status": "COMPLETED"}, format="json",
        )
        frozen = self.worker_client.patch(
            f"/api/social/referrals/{uid}/", {"status": "ACCEPTED"}, format="json",
        )
        self.assertEqual(frozen.status_code, 400)

    def test_referral_needs_its_own_consent_code(self):
        self.worker.granted_consents.all().delete()
        self._grant(self.worker, "social.cases.read", "social.cases.create")
        refused = self._create_referral()
        self.assertEqual(refused.status_code, 403, refused.data)

    def test_referral_404s_for_a_worker_without_consent(self):
        uid = self._create_referral().data["uid"]
        other = _professional("SOCIAL_SUPPORT")
        hidden = client(other).get(f"/api/social/referrals/{uid}/")
        self.assertEqual(hidden.status_code, 404)

    def test_referral_write_needs_update_consent(self):
        uid = self._create_referral().data["uid"]
        self.worker.granted_consents.all().delete()
        self._grant(self.worker, "social.referrals.read")
        visible = self.worker_client.get(f"/api/social/referrals/{uid}/")
        self.assertEqual(visible.status_code, 200)
        refused = self.worker_client.patch(
            f"/api/social/referrals/{uid}/", {"status": "ACCEPTED"}, format="json",
        )
        self.assertEqual(refused.status_code, 403)


class CaseloadTests(SocialWorkspaceTestBase):
    def test_caseload_shows_consent_patients_and_appointment_patients(self):
        from appointments.models import ClinicAppointment
        from doctors.models import Doctor

        self._grant(self.worker, "social.cases.read")

        appointment_user = orm_user("PATIENT")
        orm_patient_profile(appointment_user)
        my_row = Doctor.objects.get(user=self.worker)
        ClinicAppointment.objects.create(
            patient=appointment_user,
            created_by=appointment_user,
            doctor=my_row,
            scheduled_at=timezone.now() + timedelta(days=3),
            reason="Social review",
        )
        stranger = orm_user("PATIENT")
        orm_patient_profile(stranger)

        response = self.worker_client.get("/api/social/caseload/")
        self.assertEqual(response.status_code, 200)
        rows = response.data["results"]
        by_uid = {row["patient_uid"]: row for row in rows}

        self.assertIn(str(self.patient_user.uid), by_uid)
        self.assertTrue(by_uid[str(self.patient_user.uid)]["has_consent"])
        self.assertIn("social.cases.read", by_uid[str(self.patient_user.uid)]["consent_scope"])

        self.assertIn(str(appointment_user.uid), by_uid)
        self.assertFalse(by_uid[str(appointment_user.uid)]["has_consent"])

        self.assertNotIn(str(stranger.uid), by_uid)


class NoFinancialSystemTests(SocialWorkspaceTestBase):
    """§3: link to existing workflows — never a money system of our own."""

    def test_linked_workflow_is_a_plain_pointer_and_no_money_fields_exist(self):
        self._grant(self.worker, *SOCIAL_FULL_SCOPE)
        created = self._open_case(linked_workflow="campaign:wheelchair-drive-2026")
        self.assertEqual(created["linked_workflow"], "campaign:wheelchair-drive-2026")

        forbidden = {"amount", "money", "balance", "donation_amount", "price"}
        for model in (SocialCase, CaseNote, SocialNeedsAssessment, SocialReferral):
            names = {field.name for field in model._meta.get_fields()}
            self.assertFalse(
                names & forbidden,
                f"{model.__name__} gained money fields: {names & forbidden}",
            )
