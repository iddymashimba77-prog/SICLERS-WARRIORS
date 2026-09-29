"""P1/P2 gaps — emergency access-grants + admin monitoring APIs were untested.

Verifies (Stage 4.19 / §10, §11, §6):
* GET /api/emergency/access-grants/ — participant-scoped list (patient or
  grantee); a non-participant sees an empty list, never others' grants.
* Detail is 404 for non-participants (no IDOR).
* Admins (IsAdmin) see the full grant set; regular roles never bypass.
* GET /api/admin/emergency/ — SUP/ADM-only live feed with its meta.count.
* Creation is idempotent under a same Idempotency-Key (409, single row).
* The anti-spam create throttle (3/hour/user) returns 429.
"""

from django.core.cache import cache
from django.test import TestCase

from emergencies.models import EmergencyAccessGrant, EmergencyRequest

from . import qa_helpers as h


def _sos(client, severity="CRITICAL", type_="PAIN_CRISIS", key=None):
    kwargs = {}
    if key:
        kwargs["HTTP_IDEMPOTENCY_KEY"] = key
    return client.post(
        "/api/emergency/requests/",
        {"severity": severity, "type": type_,
         "location": {"region": "Greater Accra", "city": "Accra"},
         "description": "Severe pain crisis."},
        format="json", **kwargs,
    )


class EmergencyAccessGrantApiTests(TestCase):
    def setUp(self):
        cache.clear()
        self.patient_a = h.orm_user("PATIENT")
        self.patient_b = h.orm_user("PATIENT")
        self.admin = h.orm_user("ADMIN")
        # A creates an emergency -> an auto C10 grant is created.
        _sos(h.client(self.patient_a))
        self.grant = EmergencyAccessGrant.objects.get(patient=self.patient_a)

    def test_owner_sees_own_grants(self):
        resp = h.client(self.patient_a).get("/api/emergency/access-grants/")
        self.assertEqual(resp.status_code, 200)
        uids = [g["uid"] for g in resp.data["results"]]
        self.assertIn(str(self.grant.uid), uids)

    def test_non_participant_sees_empty_list(self):
        resp = h.client(self.patient_b).get("/api/emergency/access-grants/")
        self.assertEqual(resp.status_code, 200)
        self.assertEqual(resp.data["count"], 0)

    def test_non_participant_detail_is_404(self):
        resp = h.client(self.patient_b).get(f"/api/emergency/access-grants/{self.grant.uid}/")
        self.assertEqual(resp.status_code, 404)

    def test_admin_sees_every_grant(self):
        resp = h.client(self.admin).get("/api/emergency/access-grants/")
        self.assertEqual(resp.status_code, 200)
        uids = [g["uid"] for g in resp.data["results"]]
        self.assertIn(str(self.grant.uid), uids)

    def test_anonymous_denied(self):
        self.assertEqual(h.APIClient().get("/api/emergency/access-grants/").status_code, 401)


class EmergencyAdminMonitoringTests(TestCase):
    def setUp(self):
        cache.clear()
        self.super_admin = h.orm_user("SUPER_ADMIN")
        self.admin = h.orm_user("ADMIN")
        self.patient = h.orm_user("PATIENT")
        _sos(h.client(self.patient))

    def test_admin_feeds_live_queue_with_meta_count(self):
        for who in (self.super_admin, self.admin):
            resp = h.client(who).get("/api/admin/emergency/")
            self.assertEqual(resp.status_code, 200)
            self.assertGreaterEqual(resp.data["meta"]["count"], 1)
            self.assertTrue(resp.data["data"])

    def test_non_admin_denied(self):
        self.assertEqual(h.client(self.patient).get("/api/admin/emergency/").status_code, 403)
        self.assertEqual(h.APIClient().get("/api/admin/emergency/").status_code, 401)


class EmergencyLifecycleTests(TestCase):
    def setUp(self):
        cache.clear()
        self.patient = h.orm_user("PATIENT")
        self.client_user = h.client(self.patient)

    def test_duplicate_idempotency_key_returns_409_once(self):
        first = _sos(self.client_user, key="sos-419")
        self.assertEqual(first.status_code, 201)
        duplicate = _sos(self.client_user, key="sos-419")
        self.assertEqual(duplicate.status_code, 409)
        self.assertEqual(
            EmergencyRequest.objects.filter(requester=self.patient, idempotency_key="sos-419").count(),
            1,
        )

    def test_create_throttle_returns_429_after_quota(self):
        # The view class sets rate = "3/hour" on the throttle itself.
        statuses = []
        for i in range(4):
            statuses.append(_sos(self.client_user, key=f"sos-throttle-{i}").status_code)
        self.assertEqual([201, 201, 201, 429], statuses)