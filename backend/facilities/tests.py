"""Backend tests for the Stage 4.8 facility directory API.

Run::

    venv/bin/python manage.py test facilities --settings=config.settings.ephemeral_test

Covers: public verified-only directory, verified-only detail + auth,
HOSPITAL operator self surface, and VO/ADM verification (reason required on
reject). Facility verification gates blood-request venue selection.
"""

import uuid as _uuid

from django.test import TestCase
from rest_framework.test import APIClient
from rest_framework_simplejwt.tokens import RefreshToken

from accounts.models import Role, User, UserRole
from facilities.models import Facility


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
    client = APIClient()
    client.credentials(HTTP_AUTHORIZATION=f"Bearer {RefreshToken.for_user(user).access_token}")
    return client


def _register(role):
    client = APIClient()
    resp = client.post(
        "/api/auth/register/",
        {
            "email": f"{role.lower()}-{_uuid.uuid4().hex[:10]}@example.com",
            "password": _PASSWORD,
            "first_name": "Test",
            "last_name": "User",
            "role_code": role,
        },
        format="json",
    )
    client.credentials(HTTP_AUTHORIZATION=f"Bearer {resp.data['access']}")
    return client


class FacilityApiTests(TestCase):
    def setUp(self):
        self.operator = _orm_user("HOSPITAL")
        self.facility = Facility.objects.create(
            name="Accra General Hospital", facility_type="HOSPITAL",
            region="Greater Accra", city="Accra", is_verified=True,
            operator=self.operator,
        )
        self.unverified = Facility.objects.create(
            name="Pending Clinic", facility_type="CLINIC", is_verified=False,
        )
        self.vo = _client(_orm_user("VERIFICATION_OFFICER"))
        self.admin = _client(_orm_user("SUPER_ADMIN"))
        self.patient = _register("PATIENT")

    def test_public_directory_verified_only(self):
        anon = APIClient()
        resp = anon.get("/api/facilities/")
        self.assertEqual(resp.status_code, 200)
        names = {f["name"] for f in resp.data["results"]}
        self.assertEqual(names, {"Accra General Hospital"})

    def test_detail_requires_auth_and_verified(self):
        anon = APIClient()
        self.assertEqual(anon.get(f"/api/facilities/{self.facility.uid}/").status_code, 401)
        self.assertEqual(self.patient.get(f"/api/facilities/{self.facility.uid}/").status_code, 200)
        self.assertEqual(self.patient.get(f"/api/facilities/{self.unverified.uid}/").status_code, 404)

    def test_me_requires_hospital_operator(self):
        self.assertEqual(self.patient.get("/api/facilities/me/").status_code, 403)
        mine = _client(self.operator).get("/api/facilities/me/")
        self.assertEqual(mine.status_code, 200)
        self.assertEqual(mine.data["uid"], str(self.facility.uid))

    def test_me_patch_updates_own_facility(self):
        resp = _client(self.operator).patch(
            "/api/facilities/me/", {"address": "1 Hospital Road"}, format="json"
        )
        self.assertEqual(resp.status_code, 200)
        self.facility.refresh_from_db()
        self.assertEqual(self.facility.address, "1 Hospital Road")

    def test_me_not_found_without_linked_facility(self):
        orphan = _orm_user("HOSPITAL")
        self.assertEqual(_client(orphan).get("/api/facilities/me/").status_code, 404)

    def test_verify_flow_and_permissions(self):
        target = Facility.objects.create(name="New Lab", facility_type="LABORATORY")
        self.assertEqual(
            self.patient.post(f"/api/admin/facilities/{target.uid}/verify", {"approve": True}, format="json").status_code,
            403,
        )
        approved = self.vo.post(
            f"/api/admin/facilities/{target.uid}/verify", {"approve": True}, format="json"
        )
        self.assertEqual(approved.status_code, 200)
        target.refresh_from_db()
        self.assertTrue(target.is_verified)
        self.assertIsNotNone(target.verified_at)

        # Rejection requires a reason.
        other = Facility.objects.create(name="Other", facility_type="OTHER")
        no_reason = self.vo.post(
            f"/api/admin/facilities/{other.uid}/verify", {"approve": False}, format="json"
        )
        self.assertEqual(no_reason.status_code, 400)
        rejected = self.vo.post(
            f"/api/admin/facilities/{other.uid}/verify",
            {"approve": False, "reason": "Documents incomplete"},
            format="json",
        )
        self.assertEqual(rejected.status_code, 200)
        other.refresh_from_db()
        self.assertFalse(other.is_verified)
        self.assertIsNone(other.verified_at)

    def test_verify_audit_recorded(self):
        from audit.models import AuditLog

        target = Facility.objects.create(name="Audit Lab", facility_type="LABORATORY")
        self.admin.post(f"/api/admin/facilities/{target.uid}/verify", {"approve": True}, format="json")
        self.assertEqual(AuditLog.objects.filter(action_code="facilities.verify").count(), 1)


class FacilityAdminListTests(TestCase):
    """ADMIN-3: review directory (`facilities.verify`)."""

    def setUp(self):
        self.operator = _orm_user("HOSPITAL")
        self.verified = Facility.objects.create(
            name="Mount Sinai", facility_type="HOSPITAL",
            region="Arusha", city="Arusha", is_verified=True,
            operator=self.operator,
        )
        self.pending = Facility.objects.create(
            name="Shinyanga Clinic", facility_type="CLINIC", is_verified=False,
        )
        self.vo = _client(_orm_user("VERIFICATION_OFFICER"))
        self.admin = _client(_orm_user("SUPER_ADMIN"))
        self.patient = _register("PATIENT")

    def _rows(self, response):
        return response.json()["data"]["results"]

    def test_list_allowed_for_verify_holders(self):
        for client in (self.vo, self.admin):
            resp = client.get("/api/admin/facilities/")
            self.assertEqual(resp.status_code, 200)
            uids = {row["uid"] for row in self._rows(resp)}
            self.assertIn(str(self.verified.uid), uids)
            self.assertIn(str(self.pending.uid), uids)

    def test_list_denied_for_patient_and_anon(self):
        resp = self.patient.get("/api/admin/facilities/")
        self.assertEqual(resp.status_code, 403)
        anon = APIClient().get("/api/admin/facilities/")
        self.assertEqual(anon.status_code, 401)

    def test_status_filter(self):
        verified = self.vo.get("/api/admin/facilities/", {"status": "verified"})
        self.assertEqual(len(self._rows(verified)), 1)
        self.assertEqual(self._rows(verified)[0]["uid"], str(self.verified.uid))
        pending = self.vo.get("/api/admin/facilities/", {"status": "pending"})
        self.assertEqual(self._rows(pending)[0]["uid"], str(self.pending.uid))
        bogus = self.vo.get("/api/admin/facilities/", {"status": "bogus"})
        self.assertEqual(bogus.status_code, 400)

    def test_search_filter(self):
        resp = self.vo.get("/api/admin/facilities/", {"q": "Shinyanga"})
        self.assertEqual(len(self._rows(resp)), 1)
        self.assertEqual(self._rows(resp)[0]["name"], "Shinyanga Clinic")

    def test_admin_row_includes_operator_identity_only(self):
        row = self._rows(self.vo.get("/api/admin/facilities/", {"status": "verified"}))[0]
        self.assertEqual(row["operator_email"], self.operator.email)
        self.assertNotIn("password", row)
        self.assertNotIn("mfa_secret", row)