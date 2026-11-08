"""Patient hydration tracker API tests.

Run::

    venv/bin/python manage.py test patients.tests_hydration \
        --settings=config.settings.ephemeral_test

Contract under test: patient-owned only, optional patient-set goal, append-only
intake, honest daily summary, and deny-by-default for every other role.
"""

import uuid as _uuid
from datetime import timedelta

from django.test import TestCase
from django.utils import timezone
from rest_framework.test import APIClient
from rest_framework_simplejwt.tokens import RefreshToken

from accounts.models import Role, User, UserRole
from patients.models import HydrationEntry, Patient

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


class HydrationApiTests(TestCase):
    def setUp(self):
        self.patient = _orm_user("PATIENT")
        self.client = _client(self.patient)

    def test_no_default_goal_and_empty_day(self):
        res = self.client.get("/api/patients/me/hydration/")
        self.assertEqual(res.status_code, 200, res.data)
        self.assertIsNone(res.data["goal_ml"])
        self.assertEqual(res.data["consumed_ml"], 0)
        self.assertIsNone(res.data["remaining_ml"])
        self.assertIsNone(res.data["progress_pct"])
        self.assertEqual(res.data["entries"], [])

    def test_log_intake_and_daily_summary(self):
        res = self.client.post(
            "/api/patients/me/hydration/", {"amount_ml": 250}, format="json"
        )
        self.assertEqual(res.status_code, 201, res.data)
        self.assertEqual(res.data["amount_ml"], 250)

        self.client.post(
            "/api/patients/me/hydration/", {"amount_ml": 500}, format="json"
        )
        summary = self.client.get("/api/patients/me/hydration/")
        self.assertEqual(summary.status_code, 200)
        self.assertEqual(summary.data["consumed_ml"], 750)
        self.assertEqual(len(summary.data["entries"]), 2)

    def test_goal_round_trip_and_progress(self):
        goal = self.client.patch(
            "/api/patients/me/hydration/goal/",
            {"hydration_goal_ml": 2000},
            format="json",
        )
        self.assertEqual(goal.status_code, 200, goal.data)
        self.assertEqual(goal.data["hydration_goal_ml"], 2000)
        self.client.post(
            "/api/patients/me/hydration/", {"amount_ml": 500}, format="json"
        )
        summary = self.client.get("/api/patients/me/hydration/")
        self.assertEqual(summary.data["goal_ml"], 2000)
        self.assertEqual(summary.data["remaining_ml"], 1500)
        self.assertEqual(summary.data["progress_pct"], 25)

        cleared = self.client.patch(
            "/api/patients/me/hydration/goal/",
            {"hydration_goal_ml": None},
            format="json",
        )
        self.assertEqual(cleared.status_code, 200)
        self.assertIsNone(cleared.data["hydration_goal_ml"])

    def test_goal_and_amount_bounds(self):
        for value in (0, 249, 6001):
            res = self.client.patch(
                "/api/patients/me/hydration/goal/",
                {"hydration_goal_ml": value},
                format="json",
            )
            self.assertEqual(res.status_code, 400, (value, res.data))
        for value in (0, 3001):
            res = self.client.post(
                "/api/patients/me/hydration/", {"amount_ml": value}, format="json"
            )
            self.assertEqual(res.status_code, 400, (value, res.data))

    def test_future_intake_rejected(self):
        future = (timezone.now() + timedelta(hours=2)).isoformat()
        res = self.client.post(
            "/api/patients/me/hydration/",
            {"amount_ml": 200, "recorded_at": future},
            format="json",
        )
        self.assertEqual(res.status_code, 400, res.data)

    def test_other_patients_are_isolated(self):
        other = _orm_user("PATIENT")
        HydrationEntry.objects.create(patient=other, amount_ml=900)
        res = self.client.get("/api/patients/me/hydration/")
        self.assertEqual(res.status_code, 200)
        self.assertEqual(res.data["consumed_ml"], 0)
        self.assertEqual(res.data["entries"], [])

    def test_caregiver_doctor_and_admin_are_denied(self):
        for role_code in ("CAREGIVER", "DOCTOR", "ADMIN"):
            with self.subTest(role=role_code):
                client = _client(_orm_user(role_code))
                self.assertEqual(
                    client.get("/api/patients/me/hydration/").status_code, 403
                )
                self.assertEqual(
                    client.post(
                        "/api/patients/me/hydration/",
                        {"amount_ml": 250},
                        format="json",
                    ).status_code,
                    403,
                )
                self.assertEqual(
                    client.patch(
                        "/api/patients/me/hydration/goal/",
                        {"hydration_goal_ml": 2000},
                        format="json",
                    ).status_code,
                    403,
                )

    def test_anonymous_is_401(self):
        self.assertEqual(
            APIClient().get("/api/patients/me/hydration/").status_code, 401
        )

    def test_profile_goal_is_patient_owned(self):
        self.client.patch(
            "/api/patients/me/hydration/goal/",
            {"hydration_goal_ml": 1800},
            format="json",
        )
        profile = Patient.objects.get(user=self.patient)
        self.assertEqual(profile.hydration_goal_ml, 1800)
