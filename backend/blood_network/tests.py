"""Backend tests for the Stage 4.8 blood donation & matching API.

Run::

    venv/bin/python manage.py test blood_network --settings=config.settings.ephemeral_test

Covers: donor self-management (BLD), verified-only public directory, request
creation + idempotency 409, verify/reject workflow, owner/donor isolation (C8/C9),
matching engine + notifications, donor match response, donation-event recording
(STA/HOS) fulfilling a request, and audit/security-event recording.

BLOOD_DONOR is not self-registerable (account role policy) — donor users are
created via the ORM exactly like the stage gate would.
"""

import uuid as _uuid

from django.test import TestCase
from django.utils import timezone
from rest_framework.test import APIClient
from rest_framework_simplejwt.tokens import RefreshToken

from accounts.models import Role, User, UserRole
from blood_network.models import (
    BLOOD_GROUPS,
    BloodDonationEvent,
    BloodDonor,
    BloodMatch,
    BloodRequest,
)
from facilities.models import Facility


_PASSWORD = "Str0ng!Pass9"


def _orm_user(role_code, email=None, **extra):
    user = User.objects.create_user(
        email=email or f"{role_code.lower()}-{_uuid.uuid4().hex[:10]}@example.com",
        password=_PASSWORD,
        first_name="Test",
        last_name=role_code.title(),
        account_status="ACTIVE",
        **extra,
    )
    UserRole.objects.create(user=user, role=Role.objects.get(code=role_code))
    return user


def _client(user):
    client = APIClient()
    client.credentials(HTTP_AUTHORIZATION=f"Bearer {RefreshToken.for_user(user).access_token}")
    return client


def _register(role="PATIENT", email=None):
    client = APIClient()
    resp = client.post(
        "/api/auth/register/",
        {
            "email": email or f"{role.lower()}-{_uuid.uuid4().hex[:10]}@example.com",
            "password": _PASSWORD,
            "first_name": "Test",
            "last_name": "User",
            "role_code": role,
        },
        format="json",
    )
    user = User.objects.get(uid=resp.data["user"]["uid"])
    client.credentials(HTTP_AUTHORIZATION=f"Bearer {resp.data['access']}")
    return client, user


def _donor(user, blood_group="O+", verified=True, available=True, city="Accra"):
    return BloodDonor.objects.create(
        user=user,
        blood_group=blood_group,
        region="Greater Accra",
        city=city,
        is_available=available,
        is_verified=verified,
    )


class BloodDonorApiTests(TestCase):
    def setUp(self):
        self.donor_user = _orm_user("BLOOD_DONOR")
        self.client = _client(self.donor_user)

    def test_create_read_update_own_profile(self):
        resp = self.client.patch(
            "/api/blood/donors/me/",
            {"blood_group": "O-", "region": "Accra", "city": "Accra"},
            format="json",
        )
        self.assertEqual(resp.status_code, 200)
        self.assertEqual(resp.data["blood_group"], "O-")
        self.assertIs(resp.data["is_verified"], False)
        pid = resp.data["id"]
        got = self.client.get("/api/blood/donors/me/")
        self.assertEqual(got.status_code, 200)
        self.assertEqual(got.data["id"], pid)
        upd = self.client.patch("/api/blood/donors/me/", {"is_available": False}, format="json")
        self.assertEqual(upd.status_code, 200)
        self.assertIs(upd.data["is_available"], False)

    def test_self_service_cannot_verify(self):
        resp = self.client.patch(
            "/api/blood/donors/me/",
            {"blood_group": "A+", "is_verified": True},
            format="json",
        )
        self.assertEqual(resp.status_code, 200)
        profile = BloodDonor.objects.get(user=self.donor_user)
        self.assertIs(profile.is_verified, False)

    def test_non_donor_denied_and_anon_401(self):
        other, _ = _register("PATIENT")
        self.assertEqual(other.get("/api/blood/donors/me/").status_code, 403)
        anon = APIClient()
        self.assertEqual(anon.get("/api/blood/donors/me/").status_code, 401)
        self.assertEqual(
            anon.patch("/api/blood/donors/me/", {"blood_group": "O+"}, format="json").status_code,
            401,
        )

    def test_directory_verified_only_and_filters(self):
        donor_a = _donor(self.donor_user, blood_group="O-", verified=True, city="Kumasi")
        donor_u = _orm_user("BLOOD_DONOR")
        donor_b = _donor(donor_u, blood_group="A+", verified=False)
        admin = _client(_orm_user("SUPER_ADMIN"))
        resp = admin.get("/api/blood/donors/")
        self.assertEqual(resp.status_code, 200)
        groups = {d["blood_group"] for d in resp.data["results"]}
        self.assertEqual(groups, {"O-"})
        resp2 = admin.get("/api/blood/donors/?group_blood=A%2B")
        self.assertEqual(resp2.status_code, 200)
        donor_a.delete()
        donor_b.delete()

    def test_directory_requires_blood_donors_view(self):
        _donor(self.donor_user, verified=True)
        patient, _ = _register("PATIENT")
        self.assertEqual(patient.get("/api/blood/donors/").status_code, 403)


class BloodRequestFlowTests(TestCase):
    def setUp(self):
        self.patient, self.patient_user = _register("PATIENT")
        _, self.other_patient = _register("PATIENT")
        self.donor_user = _orm_user("BLOOD_DONOR")
        self.donor = _donor(self.donor_user, blood_group="O+", verified=True)
        self.vo = _client(_orm_user("VERIFICATION_OFFICER"))
        self.admin = _client(_orm_user("SUPER_ADMIN"))
        self.staff = _client(_orm_user("HEALTHCARE_STAFF"))
        self.facility = Facility.objects.create(
            name="Test Clinic", facility_type="CLINIC", city="Accra", is_verified=True,
        )
        self.payload = {
            "blood_group_needed": "O+",
            "units": 1,
            "urgency": "URGENT",
            "facility_uid": str(self.facility.uid),
            "location": {"region": "Greater Accra", "city": "Accra"},
        }

    def _create(self, client=None, **overrides):
        body = {**self.payload, **overrides}
        return (client or self.patient).post("/api/blood/requests/", body, format="json")

    def test_create_is_pending_and_idempotency_conflict(self):
        created = self._create(idempotency_key="req-1")
        self.assertEqual(created.status_code, 201)
        self.assertEqual(created.data["status"], "PENDING_VERIFICATION")
        dup = self._create(idempotency_key="req-1")
        self.assertEqual(dup.status_code, 409)
        second = self._create()
        self.assertEqual(second.status_code, 201)
        self.assertEqual(BloodRequest.objects.filter(created_by=self.patient_user).count(), 2)

    def test_non_patient_create_denied(self):
        donor_resp = self._create(client=_client(self.donor_user), idempotency_key="d1")
        self.assertEqual(donor_resp.status_code, 403)
        anon = APIClient()
        self.assertEqual(anon.post("/api/blood/requests/", self.payload, format="json").status_code, 401)

    def test_verify_and_reject_flow(self):
        pending = self._create()
        other_pending = self._create()
        unverified_fac = Facility.objects.create(name="Ghost", facility_type="OTHER", is_verified=False)
        self.assertEqual(self._create(facility_uid=str(unverified_fac.uid)).status_code, 400)

        patient_verify = self.patient.post(f"/api/admin/blood/requests/{pending.data['uid']}/verify/")
        self.assertEqual(patient_verify.status_code, 403)

        reject_no_reason = self.vo.post(
            f"/api/admin/blood/requests/{other_pending.data['uid']}/reject/", {}, format="json"
        )
        self.assertEqual(reject_no_reason.status_code, 400)

        rejected = self.vo.post(
            f"/api/admin/blood/requests/{other_pending.data['uid']}/reject/",
            {"reason": "Urgency not clinically confirmed"},
            format="json",
        )
        self.assertEqual(rejected.status_code, 200)
        self.assertEqual(rejected.data["status"], "REJECTED")
        self.assertTrue(rejected.data["rejection_reason"])

        verified = self.vo.post(f"/api/admin/blood/requests/{pending.data['uid']}/verify/")
        self.assertEqual(verified.status_code, 200)
        self.assertEqual(verified.data["status"], "ACTIVE")

        # Re-verifying a non-pending request is refused.
        again = self.vo.post(f"/api/admin/blood/requests/{pending.data['uid']}/verify/")
        self.assertEqual(again.status_code, 400)

    def test_owner_isolated_from_other_patients(self):
        created = self._create()
        uid = created.data["uid"]
        other_client, _ = _register("PATIENT")
        other_list = other_client.get("/api/blood/requests/")
        self.assertEqual(other_list.status_code, 200)
        self.assertEqual(other_list.data["count"], 0)
        self.assertEqual(other_client.get(f"/api/blood/requests/{uid}/").status_code, 404)

    def test_donor_sees_only_eligible_requests(self):
        pending = self._create()
        uid = pending.data["uid"]
        self.vo.post(f"/api/admin/blood/requests/{uid}/verify/")
        donor_client = _client(self.donor_user)
        listing = donor_client.get("/api/blood/requests/")
        self.assertIn(uid, [r["uid"] for r in listing.data["results"]])

        # A request needing A- needs {A-, O-}; this O+ donor is out of reach.
        ab = self._create(blood_group_needed="A-")
        self.vo.post(f"/api/admin/blood/requests/{ab.data['uid']}/verify/")
        listing2 = donor_client.get("/api/blood/requests/")
        self.assertNotIn(ab.data["uid"], [r["uid"] for r in listing2.data["results"]])

    def test_donor_detail_is_public_subset_no_pii(self):
        created = self._create()
        uid = created.data["uid"]
        self.vo.post(f"/api/admin/blood/requests/{uid}/verify/")
        detail = _client(self.donor_user).get(f"/api/blood/requests/{uid}/")
        self.assertEqual(detail.status_code, 200)
        self.assertNotIn("creator_email", detail.data)
        self.assertNotIn("created_by", detail.data)

    def test_run_matching_notifies_and_fulfills_flow(self):
        created = self._create()
        uid = created.data["uid"]
        self.vo.post(f"/api/admin/blood/requests/{uid}/verify/")

        staff_run = self.staff.post("/api/admin/blood/run-matching/", {}, format="json")
        self.assertEqual(staff_run.status_code, 403)

        run = self.admin.post(
            "/api/admin/blood/run-matching/", {"request_uid": uid}, format="json"
        )
        self.assertEqual(run.status_code, 200)
        self.assertEqual(run.data["created"][uid], 1)

        matches = self.patient.get(f"/api/blood/requests/{uid}/matches/")
        self.assertEqual(matches.status_code, 200)
        self.assertEqual(matches.data["count"], 1)
        match_id = matches.data["results"][0]["id"]
        self.assertEqual(matches.data["results"][0]["status"], "SUGGESTED")

        from notifications.models import Notification

        self.assertTrue(
            Notification.objects.filter(
                recipient=self.donor_user, type="BLOOD", delivery_key=f"blood:match:{match_id}"
            ).exists()
        )

        re_run = self.admin.post(
            "/api/admin/blood/run-matching/", {"request_uid": uid}, format="json"
        )
        self.assertEqual(re_run.data["created"][uid], 0)
        req = BloodRequest.objects.get(uid=uid)
        self.assertEqual(req.status, "MATCHING")

    def _accept(self, match_id):
        return _client(self.donor_user).post(
            f"/api/blood/matches/{match_id}/respond/", {"action": "ACCEPT"}, format="json"
        )

    def test_donor_respond_own_match_only(self):
        created = self._create()
        uid = created.data["uid"]
        self.vo.post(f"/api/admin/blood/requests/{uid}/verify/")
        self.admin.post("/api/admin/blood/run-matching/", {"request_uid": uid}, format="json")

        donor_client = _client(self.donor_user)
        mine = donor_client.get(f"/api/blood/requests/{uid}/matches/")
        match_id = mine.data["results"][0]["id"]

        other_donor = _client(_orm_user("BLOOD_DONOR"))
        stolen = other_donor.post(f"/api/blood/matches/{match_id}/respond/", {"action": "ACCEPT"}, format="json")
        self.assertEqual(stolen.status_code, 403)

        accepted = donor_client.post(
            f"/api/blood/matches/{match_id}/respond/", {"action": "ACCEPT"}, format="json"
        )
        self.assertEqual(accepted.status_code, 200)
        self.assertEqual(accepted.data["status"], "ACCEPTED")
        req = BloodRequest.objects.get(uid=uid)
        self.assertEqual(req.status, "MATCHED")

        from notifications.models import Notification

        self.assertTrue(
            Notification.objects.filter(
                delivery_key=f"blood:accepted:{match_id}"
            ).exists()
        )

        # The request is now closed to responses: previous donor responses fail.
        again = donor_client.post(
            f"/api/blood/matches/{match_id}/respond/", {"action": "DECLINE"}, format="json"
        )
        self.assertIn(again.status_code, (400,))

    def test_donation_event_recording_staff_and_privacy(self):
        created = self._create()
        uid = created.data["uid"]
        self.vo.post(f"/api/admin/blood/requests/{uid}/verify/")
        self.admin.post("/api/admin/blood/run-matching/", {"request_uid": uid}, format="json")
        donor_client = _client(self.donor_user)
        mine = donor_client.get(f"/api/blood/requests/{uid}/matches/")
        match_id = mine.data["results"][0]["id"]
        donor_client.post(f"/api/blood/matches/{match_id}/respond/", {"action": "ACCEPT"}, format="json")

        payload = {
            "donor_id": self.donor.id,
            "facility_uid": str(self.facility.uid),
            "units": 1,
            "donated_at": timezone.now().isoformat(),
            "outcome": "COMPLETED",
        }
        denied = self.patient.post(f"/api/blood/requests/{uid}/donation-events/", payload, format="json")
        self.assertEqual(denied.status_code, 403)

        recorded = self.staff.post(f"/api/blood/requests/{uid}/donation-events/", payload, format="json")
        self.assertEqual(recorded.status_code, 201)
        self.assertEqual(recorded.data["donation_serial"], f"BLD-{timezone.now():%Y%m%d}-{self.donor.id}-1")
        event = BloodDonationEvent.objects.get(pk=recorded.data["id"])
        self.assertEqual(event.outcome, "COMPLETED")

        req = BloodRequest.objects.get(uid=uid)
        self.assertEqual(req.status, "FULFILLED")
        self.assertEqual(req.matches.get(id=match_id).status, "FULFILLED")
        self.donor.refresh_from_db()
        self.assertEqual(self.donor.donation_count, 1)

        # Immutable history: no update/delete routes exist (405).
        self.assertEqual(self.staff.patch(f"/api/blood/requests/{uid}/donation-events/").status_code, 405)

    def test_verification_queue_visibility(self):
        pending = self._create()
        active = self._create()
        self.vo.post(f"/api/admin/blood/requests/{active.data['uid']}/verify/")
        queue = self.vo.get("/api/blood/requests/verification-queue/")
        self.assertEqual(queue.status_code, 200)
        uids = {r["uid"] for r in queue.data["results"]}
        self.assertEqual(uids, {pending.data["uid"]})
        self.assertEqual(self.patient.get("/api/blood/requests/verification-queue/").status_code, 403)

    def test_cancel_owner_only(self):
        created = self._create()
        uid = created.data["uid"]
        other, _ = _register("PATIENT")
        self.assertEqual(other.post(f"/api/blood/requests/{uid}/cancel/", {}, format="json").status_code, 404)
        cancelled = self.patient.post(f"/api/blood/requests/{uid}/cancel/", {"reason": "no longer needed"}, format="json")
        self.assertEqual(cancelled.status_code, 200)
        self.assertEqual(cancelled.data["status"], "CANCELLED")
        self.assertEqual(
            self.patient.post(f"/api/blood/requests/{uid}/cancel/", {}, format="json").status_code,
            400,
        )

    def test_audit_and_security_event_written(self):
        from accounts.models import SecurityEvent
        from audit.models import AuditLog

        created = self._create()
        self.assertEqual(AuditLog.objects.filter(action_code="blood_requests.create").count(), 1)
        self.assertTrue(
            SecurityEvent.objects.filter(event_type="BLOOD_REQUEST_CREATED").exists()
        )
        self.assertIsNotNone(created.data.get("uid"))