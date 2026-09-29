"""Backend tests for the Stage 4.8 emergency request API.

Run::

    venv/bin/python manage.py test emergencies --settings=config.settings.ephemeral_test

Covers: create + mandatory C10 grant, anti-spam throttle (3/hour → 429),
server-side idempotency (409), C14-self rule, owner/responder visibility,
respond → RESPONDING, escalate → ESCALATED, resolve → RESOLVED (+grant expiry),
cancel → CANCELLED (+grant revoke), admin monitoring (SUP/ADM only, C4), and
audit/security-event/notification recording.

Stage 4.9 additions (``EmergencyStage49Tests``): validate → VALIDATING (manage
only) + re-validate 400, scoped/anonymous denial, audited detail read with a
PII-free responder timeline, and location payload validation.
"""

import uuid as _uuid

from django.core.cache import cache
from django.test import TestCase
from rest_framework.test import APIClient
from rest_framework_simplejwt.tokens import RefreshToken

from accounts.models import Role, User, UserRole
from emergencies.models import EmergencyAccessGrant, EmergencyRequest
from notifications.models import Notification


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


def _register(role, email=None):
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


class EmergencyApiTests(TestCase):
    def setUp(self):
        # The locmem throttle cache is process-wide and survives TestCase DB
        # resets (user PKs restart at 1), so clear it to keep BR-009 counting
        # per-test rather than per-run.
        cache.clear()
        self.patient, self.patient_user = _register("PATIENT")
        _, self.other_patient = _register("PATIENT")
        self.hospital = _client(_orm_user("HOSPITAL"))
        self.admin = _client(_orm_user("SUPER_ADMIN"))
        self.caregiver, _ = _register("CAREGIVER")
        self.payload = {
            "severity": "CRITICAL",
            "type": "PAIN_CRISIS",
            "location": {"region": "Greater Accra", "city": "Accra"},
            "description": "Severe chest pain",
        }

    def _create(self, client=None, **overrides):
        body = {**self.payload, **overrides}
        return (client or self.patient).post("/api/emergency/requests/", body, format="json")

    def test_create_creates_grant_and_notification(self):
        created = self._create()
        self.assertEqual(created.status_code, 201)
        uid = created.data["uid"]
        self.assertEqual(created.data["status"], "CREATED")
        grant = EmergencyAccessGrant.objects.get(
            request__uid=uid, patient=self.patient_user, status="ACTIVE"
        )
        self.assertEqual(grant.grantee_id, self.patient_user.id)
        self.assertTrue(grant.expires_at)
        self.assertTrue(
            Notification.objects.filter(
                recipient=self.patient_user, type="EMERGENCY",
                delivery_key=f"emergency:created:{uid}:{self.patient_user.id}",
            ).exists()
        )

    def test_idempotency_duplicate_is_409(self):
        self.assertEqual(self._create(idempotency_key="emg-1").status_code, 201)
        dup = self._create(idempotency_key="emg-1")
        self.assertEqual(dup.status_code, 409)

    def test_anti_spam_throttle_429(self):
        for i in range(3):
            self.assertEqual(self._create().status_code, 201)
        blocked = self._create()
        self.assertEqual(blocked.status_code, 429)

    def test_caregiver_create_denied(self):
        self.assertEqual(self._create(client=self.caregiver).status_code, 403)

    def test_patient_cannot_report_another(self):
        self.assertEqual(
            self._create(patient_uid=str(self.other_patient.uid)).status_code, 403
        )

    def test_staff_reports_known_patient(self):
        staff = _client(_orm_user("HEALTHCARE_STAFF"))
        created = self._create(client=staff, patient_uid=str(self.other_patient.uid))
        self.assertEqual(created.status_code, 201)
        row = EmergencyRequest.objects.get(uid=created.data["uid"])
        self.assertEqual(row.patient_id, self.other_patient.id)
        grant = EmergencyAccessGrant.objects.get(patient=self.other_patient, status="ACTIVE")
        self.assertEqual(grant.scope["patient_basics"], True)

    def test_visibility_owner_only(self):
        created = self._create()
        uid = created.data["uid"]
        stranger, _ = _register("PATIENT")
        self.assertEqual(stranger.get("/api/emergency/requests/{}/".format(uid)).status_code, 404)
        self.assertEqual(stranger.get("/api/emergency/requests/").data["count"], 0)
        self.assertEqual(self.patient.get("/api/emergency/requests/{}/".format(uid)).status_code, 200)

    def test_respond_escalate_resolve_hospital(self):
        created = self._create()
        uid = created.data["uid"]

        doctor = _client(_orm_user("DOCTOR"))
        # Deny-by-default: a doctor with no part-of/role scope cannot reach it.
        self.assertEqual(
            doctor.post(f"/api/emergency/requests/{uid}/respond/", {"role": "STAFF"}, format="json").status_code,
            404,
        )
        responded = self.hospital.post(
            f"/api/emergency/requests/{uid}/respond/", {"role": "ADMIN"}, format="json"
        )
        self.assertEqual(responded.status_code, 200)
        self.assertEqual(responded.data["status"], "RESPONDING")

        escalated = self.hospital.post(f"/api/emergency/requests/{uid}/escalate/", {}, format="json")
        self.assertEqual(escalated.status_code, 200)
        self.assertEqual(escalated.data["status"], "ESCALATED")

        resolved = self.hospital.post(f"/api/emergency/requests/{uid}/resolve/", {}, format="json")
        self.assertEqual(resolved.status_code, 200)
        self.assertEqual(resolved.data["status"], "RESOLVED")
        row = EmergencyRequest.objects.get(uid=uid)
        self.assertTrue(row.resolved_at)
        grant = EmergencyAccessGrant.objects.get(request=row)
        self.assertEqual(grant.status, "EXPIRED")

    def test_cancel_owner_and_grant_revoked(self):
        created = self._create()
        uid = created.data["uid"]
        cancelled = self.patient.post(f"/api/emergency/requests/{uid}/cancel/", {}, format="json")
        self.assertEqual(cancelled.status_code, 200)
        self.assertEqual(cancelled.data["status"], "CANCELLED")
        grant = EmergencyAccessGrant.objects.get(request__uid=uid)
        self.assertEqual(grant.status, "REVOKED")

    def test_hospital_admin_monitoring(self):
        self._create()
        hospital_view = self.hospital.get("/api/admin/emergency/")
        self.assertEqual(hospital_view.status_code, 403)
        feed = self.admin.get("/api/admin/emergency/")
        self.assertEqual(feed.status_code, 200)
        self.assertGreaterEqual(feed.data["meta"]["count"], 1)

    def test_audit_and_security_event_written(self):
        from accounts.models import SecurityEvent
        from audit.models import AuditLog

        self._create()
        self.assertEqual(
            AuditLog.objects.filter(action_code="emergency_requests.create").count(), 1
        )
        self.assertTrue(SecurityEvent.objects.filter(event_type="EMERGENCY_CREATED").exists())


class EmergencyStage49Tests(TestCase):
    """Stage 4.9: validate transition, view audit, responder timeline, location."""

    def setUp(self):
        cache.clear()
        self.patient, self.patient_user = _register("PATIENT")
        self.hospital = _client(_orm_user("HOSPITAL"))
        self.payload = {
            "severity": "CRITICAL",
            "type": "PAIN_CRISIS",
            "location": {"region": "Greater Accra", "city": "Accra"},
            "description": "Severe chest pain",
        }

    def _create(self, client=None, **overrides):
        body = {**self.payload, **overrides}
        return (client or self.patient).post("/api/emergency/requests/", body, format="json")

    def test_validate_transitions_to_validating(self):
        from accounts.models import SecurityEvent
        from audit.models import AuditLog

        uid = self._create().data["uid"]
        # The owner holds view but not manage, so cannot self-validate.
        self.assertEqual(
            self.patient.post(f"/api/emergency/requests/{uid}/validate/", {}, format="json").status_code,
            403,
        )
        validated = self.hospital.post(
            f"/api/emergency/requests/{uid}/validate/", {}, format="json"
        )
        self.assertEqual(validated.status_code, 200)
        self.assertEqual(validated.data["status"], "VALIDATING")
        # Re-validating a non-CREATED request is rejected by the service.
        again = self.hospital.post(
            f"/api/emergency/requests/{uid}/validate/", {}, format="json"
        )
        self.assertEqual(again.status_code, 400)
        self.assertTrue(SecurityEvent.objects.filter(event_type="EMERGENCY_VALIDATED").exists())
        self.assertEqual(
            AuditLog.objects.filter(action_code="emergency_requests.validate").count(), 1
        )

    def test_validate_scoped_and_anonymous(self):
        uid = self._create().data["uid"]
        stranger, _ = _register("PATIENT")
        self.assertEqual(
            stranger.post(f"/api/emergency/requests/{uid}/validate/", {}, format="json").status_code,
            403,
        )
        self.assertEqual(
            APIClient().post(f"/api/emergency/requests/{uid}/validate/", {}, format="json").status_code,
            401,
        )

    def test_retrieve_audits_and_exposes_responder_timeline(self):
        from audit.models import AuditLog

        uid = self._create().data["uid"]
        self.hospital.post(
            f"/api/emergency/requests/{uid}/respond/", {"role": "ADMIN"}, format="json"
        )
        detail = self.patient.get(f"/api/emergency/requests/{uid}/")
        self.assertEqual(detail.status_code, 200)
        self.assertEqual(len(detail.data["responders"]), 1)
        responder = detail.data["responders"][0]
        self.assertEqual(responder["status"], "ACKNOWLEDGED")
        self.assertNotIn("responder_email", responder)
        self.assertTrue(
            AuditLog.objects.filter(action_code="emergency_requests.view").exists()
        )

    def test_location_payload_validation(self):
        self.assertEqual(self._create(location={"latitude": 100, "longitude": 0}).status_code, 400)
        self.assertEqual(self._create(location={"latitude": 5.6}).status_code, 400)
        ok = self._create(location={"latitude": 5.6, "longitude": -0.2, "text": "Hostel B"})
        self.assertEqual(ok.status_code, 201)
        self.assertEqual(ok.data["location"]["latitude"], 5.6)

    def test_escalate_allowed_from_validating(self):
        uid = self._create().data["uid"]
        self.hospital.post(f"/api/emergency/requests/{uid}/validate/", {}, format="json")
        escalated = self.hospital.post(
            f"/api/emergency/requests/{uid}/escalate/", {}, format="json"
        )
        self.assertEqual(escalated.status_code, 200)
        self.assertEqual(escalated.data["status"], "ESCALATED")