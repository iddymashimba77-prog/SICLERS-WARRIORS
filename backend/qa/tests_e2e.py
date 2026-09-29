"""End-to-end role journeys across the assembled app (Stage 4.19 / §10).

Each journey exercises the real public auth entrypoint and a minimal, real
slice of the target role's daily loop. They are the closest thing this repo
has to integration tests and would be the shoulders CI could stand on next.
"""

from django.core.cache import cache
from django.test import TestCase

from . import qa_helpers as h


class PatientDayOneJourneyTests(TestCase):
    def setUp(self):
        super().setUp()
        cache.clear()

    def _me(self, access):
        c = h.APIClient()
        c.credentials(HTTP_AUTHORIZATION=f"Bearer {access}")
        return c

    def test_register_to_first_medication(self):
        _, resp = h.register("PATIENT")
        self.assertEqual(resp.status_code, 201)
        self.assertIn("access", resp.data)
        self.assertIn("PATIENT", resp.data["user"]["role_codes"])

        c = self._me(resp.data["access"])
        me = c.get("/api/auth/me/")
        self.assertEqual(me.status_code, 200)

        profile = c.patch(
            "/api/patients/me/",
            {"genotype": "SC", "date_of_birth": "1998-06-01", "gender": "FEMALE"},
            format="json",
        )
        self.assertEqual(profile.status_code, 200)

        med = c.post(
            "/api/medications/",
            {"name": "Hydroxyurea", "generic_name": "hydroxycarbamide",
             "strength": "500 mg", "dosage": "1 tablet", "route": "ORAL",
             "frequency": "daily", "start_date": "2026-01-01",
             "end_date": "2026-12-31"},
            format="json",
        )
        self.assertEqual(med.status_code, 201)
        rows = c.get("/api/medications/").data["results"]
        self.assertEqual(rows[0]["uid"], med.data["uid"])

    def test_registered_patient_can_report_sos(self):
        _, resp = h.register("PATIENT")
        c = self._me(resp.data["access"])
        sos = c.post(
            "/api/emergency/requests/",
            {"severity": "CRITICAL", "type": "PAIN_CRISIS",
             "location": {"city": "Accra"}},
            format="json",
        )
        self.assertEqual(sos.status_code, 201)
        grants = c.get("/api/emergency/access-grants/")
        self.assertEqual(grants.data["count"], 1)


class CaregiverCannotInventClaimsTests(TestCase):
    def test_registered_caregiver_cannot_reach_admin_console(self):
        _, resp = h.register("CAREGIVER")
        access = resp.data["access"]
        c = h.APIClient()
        c.credentials(HTTP_AUTHORIZATION=f"Bearer {access}")
        self.assertEqual(c.get("/api/admin/users/").status_code, 403)
        self.assertEqual(c.get("/api/admin/emergency/").status_code, 403)


class DonorJourneyTests(TestCase):
    def test_donor_signs_in_and_creates_profile(self):
        user = h.orm_user("BLOOD_DONOR")
        c = h.APIClient()
        login = c.post(
            "/api/auth/login/",
            {"email_or_phone": user.email, "password": h._PASSWORD},
            format="json",
        )
        self.assertEqual(login.status_code, 200)
        auth = h.APIClient()
        auth.credentials(HTTP_AUTHORIZATION=f"Bearer {login.data['access']}")
        me = auth.get("/api/auth/me/")
        self.assertIn("BLOOD_DONOR", me.data["role_codes"])
        profile = auth.patch(
            "/api/blood/donors/me/",
            {"blood_group": "O+", "region": "Greater Accra", "city": "Accra"},
            format="json",
        )
        self.assertEqual(profile.status_code, 200)
        self.assertEqual(profile.data["blood_group"], "O+")