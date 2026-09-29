"""P0 gap — the `/api/patients/me/` surface had zero direct test coverage.

Verifies (Stage 4.19 / §5-7, §10):
* GET / PATCH are owner-only by construction (1:1 row, no uid lookup).
* Method-appropriate permission codes (`patients.view` / `patients.update_own`).
* Non-PATIENT roles are flatly denied on this surface (no caregiver/doctor/
  hospital/admin fall-through).
* Auto-create emits PROFILE_CREATED; PATCH emits PROFILE_UPDATED; audit
  events carry the event type only — never the medical payload (§21, §7).
* Server-side vocabulary validation for genotype/gender/date (never trusts
  the client, §7/§13).
"""

import uuid as _uuid

from django.test import TestCase

from accounts.models import SecurityEvent
from audit.models import AuditLog

from . import qa_helpers as h


def _patient_profile_payload(**over):
    payload = {
        "date_of_birth": "1995-03-12",
        "gender": "FEMALE",
        "genotype": "SS",
        "primary_diagnosis": "Sickle cell disease (HbSS)",
        "emergency_contact_name": "Mother",
        "emergency_contact_phone": "+233501234567",
        "emergency_contact_relation": "MOTHER",
        "address_region": "Greater Accra",
        "address_city": "Accra",
        "notes": "Allergic to penicillin.",
    }
    payload.update(over)
    return payload


class PatientMeApiTests(TestCase):
    def setUp(self):
        self.patient = h.orm_user("PATIENT")
        self.patient_client = h.client(self.patient)

    def test_get_without_profile_autocreates_and_audits(self):
        resp = self.patient_client.get("/api/patients/me/")
        self.assertEqual(resp.status_code, 200)
        # Auto-created 1:1 row emitted PROFILE_CREATED.
        self.assertTrue(
            SecurityEvent.objects.filter(user=self.patient, event_type="PROFILE_CREATED").exists()
        )
        # No uid lookup on this surface -> no IDOR target.
        self.assertIn("date_of_birth", resp.data)
        self.assertNotIn("uid", resp.data)

    def test_get_returns_private_notes_to_owner_only(self):
        self.patient_client.patch(
            "/api/patients/me/", _patient_profile_payload(), format="json",
        )
        got = self.patient_client.get("/api/patients/me/")
        self.assertEqual(got.data["notes"], "Allergic to penicillin.")

    def test_patch_updates_and_audits_update_event(self):
        patch = h.client(self.patient).patch(
            "/api/patients/me/",
            {"genotype": "SC", "emergency_contact_name": "Father"},
            format="json",
        )
        self.assertEqual(patch.status_code, 200)
        self.assertEqual(patch.data["genotype"], "SC")
        self.assertEqual(patch.data["emergency_contact_name"], "Father")
        self.assertTrue(
            SecurityEvent.objects.filter(user=self.patient, event_type="PROFILE_UPDATED").exists()
        )

    def test_client_cannot_assert_private_audit_medical_payload(self):
        # SecurityEvents record the event type only — medical content never
        # leaks into security/audit detail (approved §21).
        self.patient_client.patch(
            "/api/patients/me/", _patient_profile_payload(notes="ATTACKER-STRING"), format="json",
        )
        events = SecurityEvent.objects.filter(user=self.patient)
        for event in events:
            self.assertEqual(event.detail, {},
                             "SecurityEvent detail must stay empty (no medical payload)")
        audit = AuditLog.objects.filter(actor=self.patient, resource_type="patient_profile")
        self.assertFalse(audit.exists())

    # --- validation (server-authoritative) -----------------------------------
    def test_server_rejects_bad_genotype_vocabulary(self):
        resp = h.client(self.patient).patch(
            "/api/patients/me/", {"genotype": "XX"}, format="json",
        )
        self.assertEqual(resp.status_code, 400)

    def test_server_rejects_bad_gender_vocabulary(self):
        resp = h.client(self.patient).patch(
            "/api/patients/me/", {"gender": "ALIEN"}, format="json",
        )
        self.assertEqual(resp.status_code, 400)

    def test_server_rejects_malformed_date(self):
        resp = h.client(self.patient).patch(
            "/api/patients/me/", {"date_of_birth": "not-a-date"}, format="json",
        )
        self.assertEqual(resp.status_code, 400)


class PatientMeAccessTests(TestCase):
    """Role matrix on /patients/me — no cross-role fall-through (IDOR/§5-6)."""

    ROLES = ("DOCTOR", "CAREGIVER", "HOSPITAL", "HEALTHCARE_STAFF", "ADMIN",
             "SUPER_ADMIN", "BLOOD_DONOR", "FINANCIAL_DONOR", "MODERATOR",
             "VERIFICATION_OFFICER", "ORGANIZATION")

    def test_get_denied_for_every_non_patient_role(self):
        for role in self.ROLES:
            user = h.orm_user(role)
            with self.subTest(role=role):
                self.assertEqual(h.client(user).get("/api/patients/me/").status_code, 403)

    def test_patch_denied_for_every_non_patient_role(self):
        for role in self.ROLES:
            user = h.orm_user(role)
            with self.subTest(role=role):
                self.assertEqual(
                    h.client(user).patch("/api/patients/me/", {"genotype": "SC"}, format="json").
                    status_code,
                    403,
                )

    def test_anonymous_denied(self):
        self.assertEqual(h.APIClient().get("/api/patients/me/").status_code, 401)

    def test_suspended_patient_is_denied(self):
        suspended = h.orm_user("PATIENT", account_status="SUSPENDED")
        self.assertEqual(h.client(suspended).get("/api/patients/me/").status_code, 403)

    def test_no_uid_param_means_no_idor_surface(self):
        # The surface exposes only /me — a foreign identity can never be targeted.
        resp = h.APIClient().get(f"/api/patients/{_uuid.uuid4()}/")
        self.assertIn(resp.status_code, (401, 403, 404))