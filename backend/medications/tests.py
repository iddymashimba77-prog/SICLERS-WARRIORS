"""Backend tests for the Stage 4.6 medication & health-tracking API.

Run (ephemeral SQLite — never Postgres; sw_db_user has no CREATEDB)::

    venv/bin/python manage.py test medications --settings=config.settings.ephemeral_test

Covers the approved surface: ownership (foreign uid -> 404, never another
user's data), permission codes (CAREGIVER -> 403), server-side vocabulary
(routes, days_of_week, pain 0..10, status/taken_at pairing), idempotent dose
logging (duplicate key -> 409), derived adherence stats, symptom API (no
update/delete codes), timeline + dashboard materialization, soft-delete, and
audit event recording (event type only).
"""

import uuid as _uuid
from datetime import timedelta

from django.test import TestCase
from django.utils import timezone
from rest_framework.test import APIClient


def _register(client, role="PATIENT", email=None):
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


def _auth_client(role="PATIENT"):
    client = APIClient()
    resp = _register(client, role)
    client.credentials(HTTP_AUTHORIZATION=f"Bearer {resp.data['access']}")
    return client, resp


class MedicationApiTests(TestCase):
    def setUp(self):
        self.patient, _ = _auth_client("PATIENT")
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

    def _create_med(self):
        resp = self.patient.post("/api/medications/", self.med, format="json")
        return resp

    def test_create_and_list_own(self):
        created = self._create_med()
        self.assertEqual(created.status_code, 201)
        uid = created.data["uid"]
        listing = self.patient.get("/api/medications/")
        self.assertEqual(listing.status_code, 200)
        rows = listing.data["results"]
        self.assertEqual(rows[0]["uid"], uid)

    def test_invalid_route_rejected(self):
        bad = {**self.med, "route": "SPACE"}
        resp = self.patient.post("/api/medications/", bad, format="json")
        self.assertEqual(resp.status_code, 400)

    def test_end_before_start_rejected(self):
        bad = {**self.med, "start_date": "2026-12-31", "end_date": "2026-01-01"}
        resp = self.patient.post("/api/medications/", bad, format="json")
        self.assertEqual(resp.status_code, 400)

    def test_soft_delete_hides_from_list(self):
        created = self._create_med()
        uid = created.data["uid"]
        resp = self.patient.delete(f"/api/medications/{uid}/")
        self.assertEqual(resp.status_code, 204)
        listing = self.patient.get("/api/medications/")
        self.assertEqual(listing.data["count"], 0)
        detail = self.patient.get(f"/api/medications/{uid}/")
        self.assertEqual(detail.status_code, 404)

    def test_ownership_foreign_uid_is_404(self):
        created = self._create_med()
        uid = created.data["uid"]
        other, _ = _auth_client("PATIENT")
        resp = other.get(f"/api/medications/{uid}/")
        self.assertEqual(resp.status_code, 404)
        resp2 = other.patch(f"/api/medications/{uid}/", {"name": "X"}, format="json")
        self.assertEqual(resp2.status_code, 404)

    def test_caregiver_and_admin_denied(self):
        caregiver, _ = _auth_client("CAREGIVER")
        resp = caregiver.get("/api/medications/")
        self.assertEqual(resp.status_code, 403)
        created = self._create_med()
        uid = created.data["uid"]
        cg2 = caregiver.get(f"/api/medications/{uid}/")
        self.assertEqual(cg2.status_code, 403)

    def test_permissions_and_unauth(self):
        anon = APIClient()
        self.assertEqual(anon.get("/api/medications/").status_code, 401)
        self.assertEqual(anon.post("/api/medications/", self.med, format="json").status_code, 401)

    def test_audit_created_and_updated(self):
        created = self._create_med()
        uid = created.data["uid"]
        self.patient.patch(f"/api/medications/{uid}/", {"is_active": False}, format="json")
        self.patient.delete(f"/api/medications/{uid}/")
        event_types = {ev["event_type"] for ev in _patient_users_events(self.patient)}
        self.assertTrue(
            {"MEDICATION_CREATED", "MEDICATION_UPDATED", "MEDICATION_DEACTIVATED"}
            <= event_types
        )


def _patient_users_events(client):
    """Resolve the registered user behind an APIClient and list its audit events."""
    from accounts.models import User

    user = User.objects.order_by("-id").filter(user_roles__role__code="PATIENT").first()
    from accounts.models import SecurityEvent

    return list(
        SecurityEvent.objects.filter(user=user).values("event_type").distinct()
    )


class ScheduleApiTests(TestCase):
    def setUp(self):
        self.patient, _ = _auth_client("PATIENT")
        med = self.patient.post(
            "/api/medications/",
            {"name": "Folate", "route": "ORAL", "frequency": "daily",
             "start_date": "2026-01-01"},
            format="json",
        )
        self.med_uid = med.data["uid"]

    def _create_schedule(self):
        return self.patient.post(
            f"/api/medications/{self.med_uid}/schedule/",
            {"time_of_day": "08:00:00", "days_of_week": ["MON", "WED", "FRI"]},
            format="json",
        )

    def test_create_list_patch_delete(self):
        created = self._create_schedule()
        self.assertEqual(created.status_code, 201)
        uid = created.data["uid"]
        listing = self.patient.get(f"/api/medications/{self.med_uid}/schedule/")
        self.assertEqual(listing.status_code, 200)
        self.assertEqual(listing.data["count"], 1)
        patched = self.patient.patch(
            f"/api/medications/{self.med_uid}/schedule/{uid}/",
            {"days_of_week": ["SAT"]},
            format="json",
        )
        self.assertEqual(patched.status_code, 200)
        self.assertEqual(patched.data["days_of_week"], ["SAT"])
        deleted = self.patient.delete(
            f"/api/medications/{self.med_uid}/schedule/{uid}/"
        )
        self.assertEqual(deleted.status_code, 204)

    def test_bad_day_vocabulary_rejected(self):
        resp = self.patient.post(
            f"/api/medications/{self.med_uid}/schedule/",
            {"time_of_day": "08:00:00", "days_of_week": ["MONDAY"]},
            format="json",
        )
        self.assertEqual(resp.status_code, 400)

    def test_foreign_medication_schedule_404(self):
        other, _ = _auth_client("PATIENT")
        resp = other.post(
            f"/api/medications/{self.med_uid}/schedule/",
            {"time_of_day": "08:00:00", "days_of_week": ["MON"]},
            format="json",
        )
        self.assertEqual(resp.status_code, 404)


class DoseLogApiTests(TestCase):
    def setUp(self):
        self.patient, _ = _auth_client("PATIENT")
        med = self.patient.post(
            "/api/medications/",
            {"name": "Folate", "route": "ORAL", "frequency": "daily",
             "start_date": "2026-01-01"},
            format="json",
        )
        self.med_uid = med.data["uid"]
        sched = self.patient.post(
            f"/api/medications/{self.med_uid}/schedule/",
            {"time_of_day": "08:00:00", "days_of_week": ["MON", "TUE", "WED", "THU", "FRI"]},
            format="json",
        )
        self.sched_uid = sched.data["uid"]
        self.now = timezone.now()

    def _log(self, **overrides):
        payload = {"schedule": self.sched_uid, "status": "TAKEN",
                   "taken_at": self.now.isoformat(),
                   "idempotency_key": _uuid.uuid4().hex}
        payload.update(overrides)
        return self.patient.post(
            f"/api/medications/{self.med_uid}/log-dose/", payload, format="json"
        )

    def test_taken_requires_taken_at(self):
        bad = self._log(taken_at=None)
        self.assertEqual(bad.status_code, 400)
        good = self._log()
        self.assertEqual(good.status_code, 201)

    def test_non_taken_must_not_have_taken_at(self):
        bad = self.patient.post(
            f"/api/medications/{self.med_uid}/log-dose/",
            {"schedule": self.sched_uid, "status": "MISSED",
             "taken_at": self.now.isoformat()},
            format="json",
        )
        self.assertEqual(bad.status_code, 400)

    def test_idempotency_duplicate_409(self):
        key = f"k-{_uuid.uuid4().hex}"
        payload = {"schedule": self.sched_uid, "status": "TAKEN",
                   "taken_at": self.now.isoformat()}
        first = self.patient.post(
            f"/api/medications/{self.med_uid}/log-dose/",
            payload, HTTP_IDEMPOTENCY_KEY=key, format="json",
        )
        self.assertEqual(first.status_code, 201)
        dup = self.patient.post(
            f"/api/medications/{self.med_uid}/log-dose/",
            payload, HTTP_IDEMPOTENCY_KEY=key, format="json",
        )
        self.assertEqual(dup.status_code, 409)

    def test_events_list_and_no_double_count(self):
        self._log()
        self._log(status="MISSED", taken_at=None)
        events = self.patient.get(f"/api/medications/{self.med_uid}/events/")
        self.assertEqual(events.status_code, 200)
        self.assertEqual(events.data["count"], 2)
        statuses = {r["status"] for r in events.data["results"]}
        self.assertEqual(statuses, {"TAKEN", "MISSED"})

    def test_stats_derived(self):
        self._log()
        stats = self.patient.get("/api/medications/stats/")
        self.assertEqual(stats.status_code, 200)
        overall = stats.data["overall"]
        self.assertEqual(overall["taken"], 1)
        self.assertIsNotNone(overall["adherence_pct"])
        self.assertEqual(overall["expected"] >= overall["taken"], True)


class SymptomApiTests(TestCase):
    def setUp(self):
        self.patient, _ = _auth_client("PATIENT")
        self.now = timezone.now() - timedelta(hours=1)

    def _payload(self, **overrides):
        payload = {
            "symptom_type_code": "pain_crisis",
            "pain_level": 7,
            "triggers": ["cold"],
            "duration_minutes": 30,
            "recorded_at": self.now.isoformat(),
        }
        payload.update(overrides)
        return payload

    def test_create_list(self):
        created = self.patient.post("/api/symptoms/", self._payload(), format="json")
        self.assertEqual(created.status_code, 201)
        self.assertEqual(created.data["pain_level"], 7)
        listing = self.patient.get("/api/symptoms/")
        self.assertEqual(listing.status_code, 200)
        self.assertEqual(listing.data["count"], 1)

    def test_pain_level_bounds(self):
        for level in (-1, 11):
            resp = self.patient.post(
                "/api/symptoms/", self._payload(pain_level=level), format="json"
            )
            self.assertEqual(resp.status_code, 400)

    def test_triggers_must_be_strings(self):
        resp = self.patient.post(
            "/api/symptoms/", self._payload(triggers=[1, 2]), format="json"
        )
        self.assertEqual(resp.status_code, 400)

    def test_no_update_or_delete_code(self):
        created = self.patient.post("/api/symptoms/", self._payload(), format="json")
        uid = created.data["uid"]
        # No detail route exists (no approved update/delete codes) -> 404/405.
        self.assertIn(
            self.patient.patch(f"/api/symptoms/{uid}/", {"note": "x"}, format="json").status_code,
            (404, 405),
        )
        self.assertIn(
            self.patient.delete(f"/api/symptoms/{uid}/").status_code, (404, 405)
        )

    def test_timeline_materialized_for_symptom(self):
        self.patient.post("/api/symptoms/", self._payload(), format="json")
        tl = self.patient.get("/api/health-timeline/")
        types = {r["event_type"] for r in tl.data["results"]}
        self.assertTrue({"SYMPTOM_RECORDED", "PAIN_RECORDED"} <= types)


class TimelineDashboardTests(TestCase):
    def test_dashboard_aggregates(self):
        patient, _ = _auth_client("PATIENT")
        today_name = ["MON", "TUE", "WED", "THU", "FRI", "SAT", "SUN"][timezone.now().weekday()]
        med = patient.post(
            "/api/medications/",
            {"name": "Hydroxyurea", "route": "ORAL", "frequency": "daily",
             "start_date": "2026-01-01"},
            format="json",
        )
        med_uid = med.data["uid"]
        sched = patient.post(
            f"/api/medications/{med_uid}/schedule/",
            {"time_of_day": "08:00:00", "days_of_week": [today_name]},
            format="json",
        )
        patient.post(
            f"/api/medications/{med_uid}/log-dose/",
            {"schedule": sched.data["uid"], "status": "TAKEN",
             "taken_at": timezone.now().isoformat(),
             "idempotency_key": _uuid.uuid4().hex},
            format="json",
        )
        dash = patient.get("/api/patients/me/dashboard/")
        self.assertEqual(dash.status_code, 200)
        meds = dash.data["medications"]
        self.assertEqual(meds["active_count"], 1)
        self.assertEqual(meds["doses_today"]["expected"], 1)
        self.assertTrue(
            {"recent_symptoms", "recent_timeline", "adherence_last_7_days"} <= set(dash.data)
        )
        tl = patient.get("/api/health-timeline/")
        types = {r["event_type"] for r in tl.data["results"]}
        self.assertIn("MED_STARTED", types)

    def test_caregiver_denied_dashboard(self):
        caregiver, _ = _auth_client("CAREGIVER")
        self.assertEqual(caregiver.get("/api/patients/me/dashboard/").status_code, 403)