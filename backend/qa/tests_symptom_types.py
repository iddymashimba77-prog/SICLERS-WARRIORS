"""Reference-catalog + service-surface availability integration.

Stage 4.19 / §10: the "front door" guarantees clients depend on —
* /api/symptom-types/ is an authenticated, read-only catalog (never allowed
  anonymous), matching a pain-related code to its is_pain_related marker.
* Unknown symptom codes are rejected server-side.
* Public health endpoints behave as the ACL advertises (liveness public,
  ready checks the DB) — the same probes the perf/health tooling relies on.
"""

from django.test import TestCase

from . import qa_helpers as h


class SymptomTypeCatalogTests(TestCase):
    def test_anonymous_denied(self):
        self.assertIn(h.APIClient().get("/api/symptom-types/").status_code, (401, 403))

    def test_patient_reads_approved_catalog(self):
        resp = h.client(h.orm_user("PATIENT")).get("/api/symptom-types/")
        self.assertEqual(resp.status_code, 200)
        by_code = {row["code"]: row for row in resp.data}
        self.assertIn("pain_crisis", by_code)
        self.assertTrue(by_code["pain_crisis"]["is_pain_related"])
        # Catalog is flat (no pagination wrapper on a vocabulary).
        self.assertNotIn("results", resp.data)

    def test_unknown_symptom_code_rejected(self):
        patient = h.client(h.orm_user("PATIENT"))
        from django.utils import timezone
        now = timezone.now().isoformat()
        resp = patient.post(
            "/api/symptoms/",
            {"symptom_type_code": "not_in_catalog", "pain_level": 2,
             "recorded_at": now},
            format="json",
        )
        self.assertEqual(resp.status_code, 400)


class HealthEndpointSurfaceTests(TestCase):
    def test_liveness_is_public(self):
        anon = h.APIClient()
        live = anon.get("/api/v1/health/")
        self.assertEqual(live.status_code, 200)
        self.assertEqual(live.data["status"], "ok")

    def test_readiness_checks_database(self):
        ready = h.APIClient().get("/api/v1/health/ready/")
        self.assertEqual(ready.status_code, 200)
        self.assertEqual(ready.data["status"], "ok")