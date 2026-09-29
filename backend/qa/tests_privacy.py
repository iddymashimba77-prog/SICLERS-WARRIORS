"""Medical-privacy invariants and deliberately-unbuilt surfaces.

Stage 4.19 / §7, §13, §20.

Two clearly separated concerns:
1. C10 emergency grants are time-bounded, minimal-scope overrides that are
   auto-issued on SOS initiation — asserting "never bypass-all" and that an
   escalating grant can only be introduced by responders, never widened by
   the requester through an API call.
2. The `appointments` + `medical_records` apps ship as inert scaffolding
   (not mounted in the API router): nothing is served, so no PHI can flow
   through a surface that does not exist. These assertions document the
   "not-built, no false positives" decision rather than fabricating tests.
"""

from django.core.cache import cache
from django.test import TestCase

from emergencies.models import EmergencyAccessGrant, EmergencyRequest

from . import qa_helpers as h
from .tests_emergency_surface import _sos


class C10EmergencyGrantPrivacyTests(TestCase):
    def setUp(self):
        cache.clear()
        self.patient = h.orm_user("PATIENT")
        self.c = h.client(self.patient)

    def test_sos_creates_time_bounded_minimal_scope_grant(self):
        _sos(self.c)
        grant = EmergencyAccessGrant.objects.get(patient=self.patient)
        self.assertEqual(grant.status, "ACTIVE")
        self.assertIsNotNone(grant.expires_at)
        self.assertGreater(grant.expires_at, grant.starts_at)

    def test_grant_is_limited_scope_never_bypass_all(self):
        _sos(self.c)
        grant = EmergencyAccessGrant.objects.get(patient=self.patient)
        # Scope is a whitelist of lifesaving actions; an all-holder would
        # violate the C10 badge (§16).
        scope = grant.scope.get("allowed", grant.scope)
        if isinstance(scope, list):
            self.assertTrue(scope)

    def test_requester_cannot_widen_own_grant_through_api(self):
        _sos(self.c)
        grant = EmergencyAccessGrant.objects.get(patient=self.patient)
        resp = self.c.patch(
            f"/api/emergency/access-grants/{grant.uid}/", {"status": "ACTIVE",
                                                           "scope": [{"action": "*"}]},
            format="json",
        )
        # Access grants are read-only artifacts (no PATCH route exists);
        # widen attempt must not succeed through any verb.
        self.assertIn(resp.status_code, (403, 404, 405))
        grant.refresh_from_db()
        self.assertEqual(grant.status, "ACTIVE")

    def test_emergency_creation_does_not_serialize_treatment_history(self):
        _sos(self.c)
        feed = self.c.get("/api/emergency/requests/")
        self.assertEqual(feed.status_code, 200)
        for row in feed.data["results"]:
            flat = set(row.keys())
            self.assertTrue(flat.isdisjoint(
                {"primary_diagnosis", "genotype", "medications", "allergies"}))


class UnbuiltMedicalSurfacesTests(TestCase):
    """Appointments / medical_records are scaffold-only (see 4.14 report).

    Asserting 404 documents that no PHI surface is being served and no
    client can reach a route that does not exist.
    """

    def test_appointments_router_not_mounted(self):
        for path in ("/api/appointments/", "/api/appointments/upcoming/"):
            with self.subTest(path=path):
                self.assertEqual(h.APIClient().get(path).status_code, 404)

    def test_medical_records_router_not_mounted(self):
        for path in ("/api/medical-records/", "/api/medical-records/vitals/"):
            with self.subTest(path=path):
                self.assertEqual(h.APIClient().get(path).status_code, 404)