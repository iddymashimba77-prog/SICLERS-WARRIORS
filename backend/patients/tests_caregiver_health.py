"""Caregiver health-track tests (FR-CG: consent-gated linked-patient health).

Run::

    venv/bin/python manage.py test patients.tests_caregiver_health \
        --settings=config.settings.ephemeral_test

The contract these pin (never caregiver == patient, C14):

* ``GET /api/caregivers/me/health/`` answers **200 in every state** with a
  ``reason`` discriminator — ``no_link`` / ``no_consent`` / ``ok`` — so the
  client can render honest empty states instead of a permanent load failure.
* Every section is separately consent-gated (``symptoms.view`` /
  ``medications.view``); a section without its scope stays empty even when the
  patient has data — deny by default, no leak.
* ``POST /api/caregivers/me/health/observations/`` needs an ACTIVE link AND
  the ``symptoms.create`` consent scope, writes the symptom for the **linked
  patient**, and records timeline + audit + security event — same payload
  contract as the patient's own ``/api/symptoms/``.
* The patient-only dashboard (``/patients/me/dashboard/``) stays 403 for
  caregivers: the health track never reuses it.
"""

import uuid as _uuid
from datetime import timedelta

from django.test import TestCase
from django.utils import timezone
from rest_framework.test import APIClient
from rest_framework_simplejwt.tokens import RefreshToken

from accounts.models import Role, SecurityEvent, User, UserRole
from audit.models import AuditLog
from medical_records.models import Consent
from medications.models import HealthTimelineEntry, Medication, Symptom, SymptomType
from patients.models import CaregiverRelationship, Patient

_PASSWORD = "Str0ng!Pass9"


def _orm_user(role_code, email=None):
    user = User.objects.create_user(
        email=email or f"{role_code.lower()}-{_uuid.uuid4().hex[:10]}@example.com",
        password=_PASSWORD,
        first_name="Test",
        last_name=role_code.title(),
        account_status="ACTIVE",
    )
    UserRole.objects.create(user=user, role=Role.objects.get(code=role_code))
    return user


def _client(user):
    c = APIClient()
    c.credentials(HTTP_AUTHORIZATION=f"Bearer {RefreshToken.for_user(user).access_token}")
    return c


class CaregiverHealthTrackTests(TestCase):
    def setUp(self):
        self.patient = _orm_user("PATIENT")
        self.patient_row = Patient.objects.create(user=self.patient, date_of_birth="2000-01-01")
        self.caregiver = _orm_user("CAREGIVER")
        self.caregiver_client = _client(self.caregiver)
        self.symptom_type = SymptomType.objects.get(code="pain_crisis")

    def _link(self, *, status="ACTIVE"):
        return CaregiverRelationship.objects.create(
            patient=self.patient_row, user=self.caregiver,
            relationship_type="PARENT", status=status, invited_by=self.patient,
            accepted_at=timezone.now() if status == "ACTIVE" else None,
        )

    def _grant(self, scope, resource_type="patients", relation=None):
        relation = relation or CaregiverRelationship.objects.get(user=self.caregiver)
        return Consent.objects.create(
            patient_profile=relation.patient, granted_to=self.caregiver,
            resource_type=resource_type, permission_scope=list(scope),
            start_date=timezone.now() - timedelta(days=1),
            expires_at=timezone.now() + timedelta(days=30),
            status="ACTIVE",
        )

    def _seed_patient_health(self):
        Symptom.objects.create(
            patient=self.patient, symptom_type=self.symptom_type,
            pain_level=8, triggers=["cold"], duration_minutes=30,
            recorded_at=timezone.now() - timedelta(hours=2),
        )
        Medication.objects.create(
            patient=self.patient, name="Hydroxyurea", route="ORAL",
            frequency="daily", start_date=timezone.now().date(),
        )

    def _observation(self, **overrides):
        payload = {
            "symptom_type_code": "pain_crisis",
            "pain_level": 6,
            "triggers": ["weather"],
            "duration_minutes": 20,
            "notes": "logged by caregiver",
            "recorded_at": (timezone.now() - timedelta(minutes=5)).isoformat(),
        }
        payload.update(overrides)
        return payload

    # --- GET /caregivers/me/health/ : the three honest states --------------
    def test_no_link_is_a_state_not_an_error(self):
        res = self.caregiver_client.get("/api/caregivers/me/health/")
        self.assertEqual(res.status_code, 200, res.data)
        body = res.data
        self.assertEqual(body["reason"], "no_link")
        self.assertIsNone(body["linked_patient"])
        self.assertEqual(body["symptoms"], [])
        self.assertEqual(body["medications"], [])
        self.assertFalse(body["can_view_symptoms"])
        self.assertFalse(body["can_log"])

    def test_link_without_consent_is_a_distinct_state(self):
        self._link()
        res = self.caregiver_client.get("/api/caregivers/me/health/")
        self.assertEqual(res.status_code, 200, res.data)
        self.assertEqual(res.data["reason"], "no_consent")
        self.assertIsNone(res.data["linked_patient"])
        self.assertEqual(res.data["consent_scope"], [])

    def test_scoped_consent_returns_the_health_track(self):
        self._seed_patient_health()
        self._link()
        self._grant(["patients.view"], resource_type="patients")
        self._grant(["symptoms.view", "symptoms.create"], resource_type="symptoms")
        self._grant(["medications.view"], resource_type="medications")
        res = self.caregiver_client.get("/api/caregivers/me/health/")
        self.assertEqual(res.status_code, 200, res.data)
        body = res.data
        self.assertEqual(body["reason"], "ok")
        self.assertEqual(
            str(body["linked_patient"]["patient_uid"]), str(self.patient.uid)
        )
        self.assertEqual(body["linked_patient"]["relationship_type"], "PARENT")
        self.assertEqual(
            set(body["consent_scope"]),
            {"patients.view", "symptoms.view", "symptoms.create", "medications.view"},
        )
        self.assertTrue(body["can_view_symptoms"])
        self.assertTrue(body["can_view_medications"])
        self.assertTrue(body["can_log"])
        self.assertEqual(len(body["symptoms"]), 1)
        self.assertEqual(body["symptoms"][0]["symptom_type_code"], "pain_crisis")
        self.assertEqual(body["symptoms"][0]["pain_level"], 8)
        self.assertEqual([m["name"] for m in body["medications"]], ["Hydroxyurea"])

    def test_sections_without_their_scope_stay_empty(self):
        """patients.view alone: the patient HAS data, but nothing leaks."""
        self._seed_patient_health()
        self._link()
        self._grant(["patients.view"], resource_type="patients")
        res = self.caregiver_client.get("/api/caregivers/me/health/")
        self.assertEqual(res.status_code, 200, res.data)
        self.assertEqual(res.data["reason"], "ok")
        self.assertTrue(res.data["linked_patient"])
        self.assertFalse(res.data["can_view_symptoms"])
        self.assertFalse(res.data["can_view_medications"])
        self.assertFalse(res.data["can_log"])
        self.assertEqual(res.data["symptoms"], [])
        self.assertEqual(res.data["medications"], [])

    def test_no_records_yet_is_empty_ok_not_failure(self):
        self._link()
        self._grant(
            ["patients.view", "symptoms.view", "symptoms.create", "medications.view"],
            resource_type="symptoms",
        )
        res = self.caregiver_client.get("/api/caregivers/me/health/")
        self.assertEqual(res.status_code, 200, res.data)
        self.assertEqual(res.data["reason"], "ok")
        self.assertEqual(res.data["symptoms"], [])
        self.assertEqual(res.data["medications"], [])

    def test_expired_consent_falls_back_to_no_consent(self):
        relation = self._link()
        Consent.objects.create(
            patient_profile=relation.patient, granted_to=self.caregiver,
            resource_type="patients", permission_scope=["patients.view"],
            start_date=timezone.now() - timedelta(days=10),
            expires_at=timezone.now() - timedelta(seconds=1),
            status="ACTIVE",
        )
        res = self.caregiver_client.get("/api/caregivers/me/health/")
        self.assertEqual(res.status_code, 200, res.data)
        self.assertEqual(res.data["reason"], "no_consent")

    def test_revoked_link_stops_the_track(self):
        self._link(status="REVOKED")
        self._grant(["patients.view"], resource_type="patients")
        res = self.caregiver_client.get("/api/caregivers/me/health/")
        self.assertEqual(res.status_code, 200, res.data)
        self.assertEqual(res.data["reason"], "no_link")

    def test_patient_identity_cannot_use_the_caregiver_track(self):
        res = _client(self.patient).get("/api/caregivers/me/health/")
        self.assertEqual(res.status_code, 403)

    def test_anonymous_is_401(self):
        self.assertEqual(APIClient().get("/api/caregivers/me/health/").status_code, 401)

    def test_non_caregiver_roles_are_denied_on_both_endpoints(self):
        """Deny by default: no other identity reaches the caregiver surface.

        A professional or staff role carries its own permissions elsewhere on
        the API — none of them substitute for the CAREGIVER identity plus an
        ACTIVE link + consent that this track requires.
        """
        for role_code in ("DOCTOR", "HEALTHCARE_STAFF", "ADMIN"):
            with self.subTest(role=role_code):
                client = _client(_orm_user(role_code))
                res = client.get("/api/caregivers/me/health/")
                self.assertEqual(res.status_code, 403, res.data)
                res = client.post(
                    "/api/caregivers/me/health/observations/",
                    self._observation(),
                    format="json",
                )
                self.assertEqual(res.status_code, 403, res.data)
                self.assertEqual(Symptom.objects.count(), 0)

    # --- POST /caregivers/me/health/observations/ --------------------------
    def test_observation_denied_without_any_link(self):
        res = self.caregiver_client.post(
            "/api/caregivers/me/health/observations/", self._observation(), format="json"
        )
        self.assertEqual(res.status_code, 403)
        self.assertEqual(Symptom.objects.count(), 0)

    def test_observation_denied_with_link_but_no_consent(self):
        self._link()
        res = self.caregiver_client.post(
            "/api/caregivers/me/health/observations/", self._observation(), format="json"
        )
        self.assertEqual(res.status_code, 403)
        self.assertEqual(Symptom.objects.count(), 0)

    def test_observation_denied_when_scope_lacks_symptoms_create(self):
        self._link()
        self._grant(["patients.view", "symptoms.view"], resource_type="symptoms")
        res = self.caregiver_client.post(
            "/api/caregivers/me/health/observations/", self._observation(), format="json"
        )
        self.assertEqual(res.status_code, 403)
        self.assertEqual(Symptom.objects.count(), 0)

    def test_observation_written_for_the_linked_patient_with_full_trail(self):
        from medical_records import services as consent_services

        relation = self._link()
        self._grant(["patients.view"], resource_type="patients")
        self._grant(["symptoms.create"], resource_type="symptoms")
        res = self.caregiver_client.post(
            "/api/caregivers/me/health/observations/", self._observation(), format="json"
        )
        self.assertEqual(res.status_code, 201, res.data)
        symptom = Symptom.objects.get(uid=res.data["uid"])
        # The record belongs to the LINKED patient — never to the caregiver.
        self.assertEqual(symptom.patient, self.patient)
        self.assertEqual(symptom.pain_level, 6)
        # Consents are read against the relation's patient, not request.user.
        self.assertTrue(
            consent_services.can_access(relation.patient, self.caregiver, "symptoms.create")
        )
        # Health timeline materialised (best-effort projection), same as the
        # patient's own logging.
        event_types = set(
            HealthTimelineEntry.objects.filter(patient=self.patient).values_list(
                "event_type", flat=True
            )
        )
        self.assertIn("SYMPTOM_RECORDED", event_types)
        self.assertIn("PAIN_RECORDED", event_types)
        # Audit: caregiver is the actor, patient the record subject.
        entry = AuditLog.objects.filter(
            actor=self.caregiver, action_code="symptoms.create"
        ).latest("created_at")
        self.assertEqual(entry.details["on_behalf_of"], str(self.patient.uid))
        self.assertTrue(
            SecurityEvent.objects.filter(
                user=self.caregiver, event_type="SYMPTOM_RECORDED"
            ).exists()
        )

    def test_observation_uses_the_shared_symptom_validation(self):
        self._link()
        self._grant(["symptoms.create"], resource_type="symptoms")
        for bad in ({"pain_level": 11}, {"triggers": [1]}, {"pain_level": -1}):
            res = self.caregiver_client.post(
                "/api/caregivers/me/health/observations/",
                self._observation(**bad), format="json",
            )
            self.assertEqual(res.status_code, 400, (bad, res.data))
        self.assertEqual(Symptom.objects.count(), 0)

    def test_health_listing_reflects_a_newly_logged_observation(self):
        self._link()
        self._grant(
            ["patients.view", "symptoms.view", "symptoms.create"],
            resource_type="symptoms",
        )
        self.caregiver_client.post(
            "/api/caregivers/me/health/observations/", self._observation(), format="json"
        )
        res = self.caregiver_client.get("/api/caregivers/me/health/")
        self.assertEqual(res.status_code, 200, res.data)
        self.assertEqual(len(res.data["symptoms"]), 1)
        self.assertEqual(res.data["symptoms"][0]["pain_level"], 6)
        self.assertEqual(
            res.data["symptoms"][0]["notes"], "logged by caregiver"
        )

    # --- regression: the patient-only dashboard stays closed ---------------
    def test_patient_dashboard_remains_forbidden(self):
        self._link()
        self._grant(
            ["patients.view", "symptoms.view", "medications.view"],
            resource_type="patients",
        )
        self.assertEqual(
            self.caregiver_client.get("/api/patients/me/dashboard/").status_code, 403
        )
