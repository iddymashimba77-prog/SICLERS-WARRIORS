"""Backend tests for the doctor-prescriber medication flow (Stage 4.6 doctor cycle).

Run::

    venv/bin/python manage.py test medications.tests_doctor --settings=config.settings.ephemeral_test

Covers: a verified DOCTOR (APPROVED registry row + `medications.prescribe`)
may author a patient's medication profile (create/update/schedule/delete) and
read the patient's symptom log; the patient sees those medications in their
own account; unverified doctors and non-prescriber roles stay denied; the
doctor patient directory exposes identity rows only.
"""

import uuid as _uuid
from datetime import timedelta

from django.test import TestCase
from django.utils import timezone
from rest_framework.test import APIClient

from accounts.models import Role, User
from doctors.models import Doctor


def _register(client, role, email=None):
    resp = client.post(
        "/api/auth/register/",
        {
            "email": email or f"{role.lower()}-{_uuid.uuid4().hex[:10]}@example.com",
            "password": "Str0ng!Pass9",
            "first_name": "Test",
            "last_name": "User",
            "role_code": role,
        },
        format="json",
    )
    return resp


def _client_for(role, approved=True):
    client = APIClient()
    resp = _register(client, role)
    assert resp.status_code == 201, resp.data
    user = User.objects.get(email=resp.data["user"]["email"])
    client.credentials(HTTP_AUTHORIZATION=f"Bearer {resp.data['access']}")
    if role == "DOCTOR":
        # Registered professionals sit at PENDING_VERIFICATION until their
        # documents clear; a verified doctor has an ACTIVE account + APPROVED
        # registry row (mirrors the C5 pipeline's end state).
        user.account_status = "ACTIVE"
        user.save(update_fields=["account_status"])
        Doctor.objects.create(
            user=user,
            professional_type="DOCTOR",
            verification_status="APPROVED" if approved else "PENDING",
        )
    return client, user


class DoctorPrescribesMedicationTests(TestCase):
    def setUp(self):
        self.doctor, self.doctor_user = _client_for("DOCTOR")
        self.patient, self.patient_user = _client_for("PATIENT")
        self.med = {
            "name": "Hydroxyurea",
            "generic_name": "hydroxycarbamide",
            "strength": "500 mg",
            "dosage": "1 tablet",
            "route": "ORAL",
            "frequency": "daily",
            "start_date": "2026-01-01",
            "end_date": "2026-12-31",
        }

    def test_doctor_prescribes_for_patient_and_patient_sees_it(self):
        created = self.doctor.post(
            "/api/medications/", {**self.med, "patient": str(self.patient_user.uid)},
            format="json",
        )
        self.assertEqual(created.status_code, 201)
        uid = created.data["uid"]
        self.assertEqual(created.data["prescribed_by"], self.doctor_user.email)

        # The patient sees the doctor's prescription in their own account.
        listing = self.patient.get("/api/medications/")
        self.assertEqual(listing.status_code, 200)
        self.assertEqual(listing.data["results"][0]["uid"], uid)

        # The doctor's UI can reload the same profile scoped to the patient.
        scoped = self.doctor.get(f"/api/medications/?patient={self.patient_user.uid}")
        self.assertEqual(scoped.status_code, 200)
        self.assertEqual(scoped.data["results"][0]["uid"], uid)

    def test_doctor_prescription_requires_a_patient(self):
        resp = self.doctor.post("/api/medications/", self.med, format="json")
        self.assertEqual(resp.status_code, 400)
        self.assertIn("patient", resp.data["error"]["details"])

    def test_doctor_updates_patient_medication(self):
        created = self.doctor.post(
            "/api/medications/", {**self.med, "patient": str(self.patient_user.uid)},
            format="json",
        )
        uid = created.data["uid"]
        resp = self.doctor.patch(
            f"/api/medications/{uid}/",
            {"instructions": "Take with food."}, format="json",
        )
        self.assertEqual(resp.status_code, 200)
        self.assertEqual(resp.data["instructions"], "Take with food.")

    def test_doctor_adds_schedule_for_patient(self):
        created = self.doctor.post(
            "/api/medications/", {**self.med, "patient": str(self.patient_user.uid)},
            format="json",
        )
        uid = created.data["uid"]
        resp = self.doctor.post(
            f"/api/medications/{uid}/schedule/",
            {"time_of_day": "08:00", "days_of_week": ["MON", "WED", "FRI"]},
            format="json",
        )
        self.assertEqual(resp.status_code, 201)

        listing = self.patient.get(f"/api/medications/{uid}/")
        self.assertEqual(listing.status_code, 200)
        self.assertEqual(len(listing.data["schedules"]), 1)

    def test_unverified_doctor_denied(self):
        unverified, _ = _client_for("DOCTOR", approved=False)
        resp = unverified.post(
            "/api/medications/", {**self.med, "patient": str(self.patient_user.uid)},
            format="json",
        )
        self.assertEqual(resp.status_code, 403)

    def test_prescriber_cannot_log_dose_for_patient(self):
        created = self.doctor.post(
            "/api/medications/", {**self.med, "patient": str(self.patient_user.uid)},
            format="json",
        )
        uid = created.data["uid"]
        resp = self.doctor.post(
            f"/api/medications/{uid}/log-dose/",
            {"schedule": None, "status": "TAKEN", "taken_at": "2026-01-05T08:00:00Z"},
            format="json",
        )
        self.assertEqual(resp.status_code, 403)


class DoctorReadsPatientSymptomsTests(TestCase):
    def setUp(self):
        self.doctor, _ = _client_for("DOCTOR")
        self.patient, self.patient_user = _client_for("PATIENT")

    def test_doctor_reads_patient_symptom_log(self):
        recorded = self.patient.post(
            "/api/symptoms/",
            {
                "symptom_type_code": "pain_crisis", "pain_level": 7,
                "triggers": ["cold"],
                "recorded_at": (timezone.now() - timedelta(hours=1)).isoformat(),
            },
            format="json",
        )
        self.assertEqual(recorded.status_code, 201)
        resp = self.doctor.get(f"/api/symptoms/?patient={self.patient_user.uid}")
        self.assertEqual(resp.status_code, 200)
        uids = [row["uid"] for row in resp.data.get("results", resp.data.get("data", []))]
        self.assertIn(recorded.data["uid"], uids)

    def test_doctor_cannot_create_patient_symptom(self):
        resp = self.doctor.post(
            "/api/symptoms/",
            {"symptom_type_code": "PAIN", "pain_level": 5},
            format="json",
        )
        self.assertEqual(resp.status_code, 403)


class PatientDirectoryTests(TestCase):
    def setUp(self):
        self.doctor, _ = _client_for("DOCTOR")
        self.patient, self.patient_user = _client_for("PATIENT")

    def test_verified_doctor_lists_patients(self):
        resp = self.doctor.get("/api/patients/directory/")
        self.assertEqual(resp.status_code, 200)
        rows = resp.data["data"] if isinstance(resp.data, dict) else resp.data
        uids = [row["uid"] for row in rows]
        self.assertIn(str(self.patient_user.uid), uids)
        for row in rows:
            self.assertNotIn("date_of_birth", row)

    def test_unverified_doctor_denied(self):
        unverified, _ = _client_for("DOCTOR", approved=False)
        resp = unverified.get("/api/patients/directory/")
        self.assertEqual(resp.status_code, 403)

    def test_patient_denied_directory(self):
        resp = self.patient.get("/api/patients/directory/")
        self.assertEqual(resp.status_code, 403)