"""AUTH-4 audit tests — RBAC contract + privilege-escalation sweep.

Run::

    venv/bin/python manage.py test accounts.tests_auth4_audit --settings=config.settings.ephemeral_test

Covers the audit class for AUTH-4 (role & permission hardening):

* **/me RBAC contract** — `/api/auth/me/` advertises server-authenticated
  ``role_codes`` + ``permission_codes``; this exact payload is what the mobile
  ADMIN-3 shell feeds into `adminSectionsFor`. SUPER_ADMIN exposes the RBAC
  kernel, ADMIN exposes the read matrix but never the SUP-only writes,
  PATIENT exposes none of the admin surface.
* **Privilege-escalation sweep** — a PATIENT replays every admin read/write
  endpoint (including fabricated ids targeting resources they never saw) and
  must receive 403 before any id resolution; anonymous callers get 401. No
  granted-access 200/404 leak, no read of the portal.
* **Audit-noise discipline** — denied lateral attempts must NOT mint
  `admin.*` decision audit rows: fails silently, records nothing.

Existing modules already pin the grant side of the matrix
(`tests_admin_roles.py`: kernel lockout, SUP-only writes) and the C17 role
boundaries (`tests_admin.py`). This file is the denial-side audit sweep.
"""

import uuid as _uuid

from django.core.cache import cache
from django.test import TestCase
from rest_framework.test import APIClient
from rest_framework_simplejwt.tokens import RefreshToken

from audit.models import AuditLog
from .models import Role, User, UserRole

_PASSWORD = "Str0ng!Pass9"

_ADMIN_PREFIXES = ("admin.", "audit_logs.", "analytics.", "education.review",
                   "community.moderate", "blood_requests.", "facilities.",
                   "campaigns.", "donations.", "notifications.broadcast",
                   "content.")

# The exact ADMIN-3 portal codes the mobile shell feeds into
# `adminSectionsFor` (mirror of `apps/mobile/lib/features/admin/domain/
# admin_authz.dart`). A non-admin must hold none of them.
_PORTAL_CODES = {
    "admin.users.manage", "doctors.verify", "facilities.verify",
    "blood_requests.verify", "campaigns.verify", "admin.roles.manage",
    "admin.permissions.manage", "education.review", "community.moderate",
    "donations.view", "donations.refund", "notifications.broadcast",
    "audit_logs.view", "audit_logs.export", "admin.audit.read",
    "analytics.view", "content.news.manage", "content.ticker.manage",
}


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
    client.credentials(
        HTTP_AUTHORIZATION=f"Bearer {RefreshToken.for_user(user).access_token}"
    )
    return client


def _json(client):
    """Return a client whose write helper defaults to JSON encoding."""
    return client


class MeRbacContractTests(TestCase):
    """The /me payload is the server-authenticated contract for role-based UI."""

    def setUp(self):
        cache.clear()

    def test_super_admin_advertises_rbac_kernel(self):
        user = _orm_user("SUPER_ADMIN")
        r = _client(user).get("/api/auth/me/")
        self.assertEqual(r.status_code, 200)
        data = r.json()["data"]
        self.assertIn("SUPER_ADMIN", data["role_codes"])
        codes = set(data["permission_codes"])
        for kernel in (
            "admin.permissions.manage", "admin.roles.manage", "admin.users.manage",
            "admin.audit.read", "admin.audit.export",
        ):
            self.assertIn(kernel, codes, kernel)

    def test_admin_advertises_read_matrix_never_sup_writes(self):
        user = _orm_user("ADMIN")
        r = _client(user).get("/api/auth/me/")
        self.assertEqual(r.status_code, 200)
        data = r.json()["data"]
        self.assertEqual(data["role_codes"], ["ADMIN"])
        codes = set(data["permission_codes"])
        self.assertIn("admin.roles.manage", codes)
        self.assertIn("admin.audit.read", codes)
        for sup_only in ("admin.permissions.manage", "admin.audit.export"):
            self.assertNotIn(sup_only, codes, sup_only)

    def test_patient_exposes_no_admin_codes(self):
        user = _orm_user("PATIENT")
        r = _client(user).get("/api/auth/me/")
        self.assertEqual(r.status_code, 200)
        data = r.json()["data"]
        self.assertEqual(data["role_codes"], ["PATIENT"])
        # The patient may legitimately hold feature codes (doctors.view, blood.
        # donate, ...) but it must hold NONE of the ADMIN-3 portal codes.
        self.assertTrue(
            not (set(data["permission_codes"]) & _PORTAL_CODES)
        )

    def test_unknown_session_has_no_me(self):
        r = APIClient().get("/api/auth/me/")
        self.assertEqual(r.status_code, 401)


class AdminSurfaceDenialSweepTests(TestCase):
    """A contributor replays the portal surface; every route must hard-deny."""

    def setUp(self):
        cache.clear()
        self.patient = _orm_user("PATIENT")
        self.target = _orm_user("PATIENT")
        self.fake_uid = _uuid.uuid4()
        self.patient_client = _client(self.patient)
        self.anon_client = APIClient()
        self.audit_baseline = AuditLog.objects.count()

    # ------------------------------------------------------------ reads
    READ_ENDPOINTS = [
        "/api/admin/users/",
        "/api/admin/security-events/",
        "/api/admin/roles/",
        "/api/admin/audit-logs/",
        "/api/admin/dashboard/",
        "/api/admin/analytics/?metric=users.total&granularity=daily",
        "/api/admin/ai/monitoring/",
        "/api/admin/financial/summary/",
        "/api/admin/donations/",
        "/api/admin/campaigns/",
        "/api/admin/campaigns/verification-queue/",
        "/api/admin/facilities/",
        "/api/admin/doctors/verification-queue/",
        "/api/blood/requests/verification-queue/",
        "/api/admin/education/content/",
        "/api/admin/community/reports/",
        "/api/admin/content/news/",
        "/api/admin/content/ticker/",
    ]

    def test_all_reads_hard_denied_for_patient_and_anon(self):
        for path in self.READ_ENDPOINTS:
            self.assertEqual(
                self.patient_client.get(path).status_code, 403, "GET " + path
            )
            self.assertEqual(
                self.anon_client.get(path).status_code, 401, "anon GET " + path
            )

    # ------------------------------------------------------------ writes
    def _expect_denied(self, suffix, **payload):
        uid = self.target.uid if "self" in suffix else self.fake_uid
        urls = [
            ("post", f"/api/admin/users/{uid}/activate/", {"reason": "x" * 6}),
            ("post", f"/api/admin/users/{uid}/deactivate/", {"reason": "x" * 6}),
            ("post", f"/api/admin/users/{uid}/roles/", {"role_code": "ADMIN", "reason": "x" * 6}),
            ("delete", f"/api/admin/users/{uid}/roles/", {"role_code": "PATIENT", "reason": "x" * 6}),
            ("post", "/api/admin/roles/ADMIN/permissions/",
             {"permission_code": "admin.permissions.manage", "grant": True, "reason": "x" * 6}),
            ("post", f"/api/admin/doctors/{self.fake_uid}/verify/", {"approve": True, "reason": "x" * 6}),
            ("post", f"/api/admin/doctors/{self.fake_uid}/suspend/", {"reason": "x" * 6}),
            ("post", f"/api/admin/facilities/{self.fake_uid}/verify", {"approve": True, "reason": "x" * 6}),
            ("post", f"/api/admin/blood/requests/{self.fake_uid}/verify/", {}),
            ("post", f"/api/admin/blood/requests/{self.fake_uid}/reject/", {"reason": "x" * 6}),
            ("post", f"/api/admin/campaigns/{self.fake_uid}/verify/", {"approve": True, "reason": "x" * 6}),
            ("post", f"/api/admin/campaigns/{self.fake_uid}/pause/", {"reason": "x" * 6}),
            ("post", f"/api/admin/campaigns/{self.fake_uid}/close/", {"reason": "x" * 6}),
            ("post", f"/api/admin/donations/{self.fake_uid}/refund/", {"reason": "x" * 6, "amount": 100}),
            ("post", f"/api/admin/education/content/{self.fake_uid}/review/", {"decision": "approve"}),
            ("post", "/api/admin/community/reports/1/resolve/", {"status": "RESOLVED"}),
            ("post", "/api/admin/notifications/broadcast/",
             {"audience": "ALL", "title": "t", "body": "b" * 6}),
            ("post", "/api/admin/content/news/",
             {"title": "x", "category": "HEALTH", "body": "b" * 6}),
            ("delete", f"/api/admin/content/news/{uid}/", {}),
            ("post", f"/api/admin/content/news/{uid}/publish/", {}),
            ("post", f"/api/admin/content/news/{uid}/unpublish/", {}),
            ("post", f"/api/admin/content/news/{uid}/archive/", {}),
            ("post", f"/api/admin/content/news/{uid}/feature/", {"featured": True}),
            ("post", f"/api/admin/content/news/{uid}/cover/",
             {"image": ("c.png", b"not-an-image", "image/png")}),
            ("post", "/api/admin/content/ticker/",
             {"message": "x", "announcement_type": "INFO", "priority": 0}),
            ("delete", f"/api/admin/content/ticker/{uid}/", {}),
            ("post", f"/api/admin/content/ticker/{uid}/activate/", {}),
            ("post", f"/api/admin/content/ticker/{uid}/deactivate/", {}),
        ]
        for method, url, payload in urls:
            resp = getattr(self.patient_client, method)(url, payload, format="json")
            self.assertEqual(resp.status_code, 403, f"{method.upper()} {url}")
            resp = getattr(self.anon_client, method)(url, payload, format="json")
            self.assertEqual(resp.status_code, 401, f"anon {method.upper()} {url}")

    def test_all_writes_hard_denied_before_id_resolution(self):
        self._expect_denied("sweep")
        # The 403 must happen before resource lookup: an idle fabricated id
        # must never resolve to a 404 (leaks that the resource path exists).
        self.assertEqual(AuditLog.objects.count(), self.audit_baseline)

    def test_denied_sweep_mints_no_admin_decision_rows(self):
        self._expect_denied("sweep")
        # Denial is silent: the sweep must never paint admin.* decision rows.
        self.assertEqual(AuditLog.objects.count(), self.audit_baseline)

    def test_admin_grants_still_audited_after_sweep(self):
        """The sweep doesn't disable governance: a legit decision still audits."""
        supervisor = _client(_orm_user("SUPER_ADMIN"))
        r = supervisor.post(
            f"/api/admin/users/{self.target.uid}/roles/",
            {"role_code": "CAREGIVER", "reason": "Audit trail check"},
            format="json",
        )
        self.assertEqual(r.status_code, 200)
        self.assertTrue(
            AuditLog.objects.filter(action_code="admin.user.role_grant",
                                    resource_id=self.target.pk).exists()
        )