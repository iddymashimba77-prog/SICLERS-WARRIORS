"""Stage 4.31 — Admin Branding (app_branding) tests.

Run::

    venv/bin/python manage.py test core.tests_branding --settings=config.settings.ephemeral_test

Covers: public brand read, public logo file serving (404 when unset),
deny-by-default admin gating (401 anonymous / 403 for ADMIN without
``admin.branding.manage``), SUPER_ADMIN alt-text update + logo upload/remove,
server-side image re-encode (invalid payloads 400), and audit persistence.
"""

import io
import uuid as _uuid

from django.test import TestCase
from django.test.utils import override_settings
from PIL import Image
from rest_framework.test import APIClient
from rest_framework_simplejwt.tokens import RefreshToken

from audit.models import AuditLog
from accounts.models import Role, User, UserRole

_PASSWORD = "Str0ng!Pass9"


def _jpeg_bytes(color=(120, 30, 60), size=(64, 64)):
    buffer = io.BytesIO()
    Image.new("RGB", size, color).save(buffer, format="JPEG")
    return buffer.getvalue()


def _orm_user(role_code, email=None):
    user = User.objects.create_user(
        email=email or f"branding-{role_code.lower()}-{_uuid.uuid4().hex[:10]}@example.com",
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


@override_settings(
    MEDIA_URL="media/",
    STORAGES={
        "default": {"BACKEND": "django.core.files.storage.InMemoryStorage"},
        "staticfiles": {"BACKEND": "django.contrib.staticfiles.storage.StaticFilesStorage"},
    },
)
class BrandingTests(TestCase):
    def setUp(self):
        self.anon = APIClient()
        self.super = _client(_orm_user("SUPER_ADMIN"))
        self.admin = _client(_orm_user("ADMIN"))
        self.patient = _client(_orm_user("PATIENT"))

    # ------------------------------------------------------------- public read
    def test_public_branding_reads_unset_default(self):
        resp = self.anon.get("/api/branding/")
        self.assertEqual(resp.status_code, 200)
        data = resp.json()["data"]
        self.assertFalse(data["has_logo"])
        self.assertEqual(data["logo_url"], "/api/branding/logo/")
        self.assertEqual(data["logo_alt"], "")

    def test_public_logo_file_404_when_unset(self):
        self.assertEqual(self.anon.get("/api/branding/logo/").status_code, 404)

    def test_public_endpoints_never_require_auth(self):
        self.assertEqual(self.anon.get("/api/branding/").status_code, 200)
        self.assertEqual(self.anon.get("/api/branding/logo/").status_code, 404)

    # ------------------------------------------------------------- deny by default
    def test_anonymous_write_denied(self):
        self.assertEqual(self.anon.patch("/api/admin/branding/", {"logo_alt": "x"}, format="json").status_code, 401)
        self.assertEqual(self.anon.post("/api/admin/branding/logo/", {}).status_code, 401)
        self.assertEqual(self.anon.delete("/api/admin/branding/logo/").status_code, 401)
        self.assertEqual(self.anon.get("/api/admin/branding/").status_code, 401)

    def test_admin_role_cannot_manage_branding(self):
        self.assertEqual(self.admin.get("/api/admin/branding/").status_code, 403)
        self.assertEqual(self.admin.patch("/api/admin/branding/", {"logo_alt": "x"}, format="json").status_code, 403)
        self.assertEqual(self.admin.post("/api/admin/branding/logo/", {}).status_code, 403)
        self.assertEqual(self.admin.delete("/api/admin/branding/logo/").status_code, 403)

    def test_patient_cannot_manage_branding(self):
        self.assertEqual(self.patient.get("/api/admin/branding/").status_code, 403)

    # ------------------------------------------------------------- super admin write
    def test_super_reads_branding_provenance(self):
        resp = self.super.get("/api/admin/branding/")
        self.assertEqual(resp.status_code, 200)
        data = resp.json()["data"]
        self.assertIn("updated_at", data)
        self.assertIsNone(data["updated_by"])
        self.assertEqual(data["logo_alt"], "")

    def test_super_updates_alt_text_and_audits(self):
        resp = self.super.patch("/api/admin/branding/", {"logo_alt": "Sickler's Warriors"}, format="json")
        self.assertEqual(resp.status_code, 200)
        self.assertEqual(resp.json()["data"]["logo_alt"], "Sickler's Warriors")
        self.assertTrue(
            AuditLog.objects.filter(action_code="branding.alt_update", result="SUCCESS").exists()
        )

    def test_alt_text_too_long_rejected(self):
        resp = self.super.patch("/api/admin/branding/", {"logo_alt": "x" * 161}, format="json")
        self.assertEqual(resp.status_code, 400)

    def test_super_uploads_logo_then_public_serves_it(self):
        from django.core.files.uploadedfile import SimpleUploadedFile
        from django.urls import reverse

        upload = SimpleUploadedFile("logo.jpg", _jpeg_bytes(), content_type="image/jpeg")
        resp = self.super.post("/api/admin/branding/logo/", {"image": upload, "alt": "Sicklers logo"}, format="multipart")
        self.assertEqual(resp.status_code, 200, resp.content)
        data = resp.json()["data"]
        self.assertTrue(data["has_logo"])
        self.assertEqual(data["logo_alt"], "Sicklers logo")

        served = self.anon.get("/api/branding/logo/")
        self.assertEqual(served.status_code, 200)
        self.assertEqual(served["Content-Type"], "image/jpeg")

        admin = self.super.get("/api/admin/branding/")
        self.assertEqual(admin.json()["data"]["updated_by"]["full_name"], "Test Super_Admin")
        self.assertTrue(
            AuditLog.objects.filter(action_code="branding.logo_update", result="SUCCESS").exists()
        )

    def test_logo_survives_ephemeral_filesystem_wipe(self):
        """Render free tier keeps the DB volume but wipes local files: the
        public endpoint must still serve the uploaded logo afterwards."""
        from django.core.files import storage as files_storage
        from django.core.files.uploadedfile import SimpleUploadedFile

        upload = SimpleUploadedFile("logo.jpg", _jpeg_bytes(), content_type="image/jpeg")
        resp = self.super.post("/api/admin/branding/logo/", {"image": upload}, format="multipart")
        self.assertEqual(resp.status_code, 200, resp.content)

        from core.models import AppBranding

        branding = AppBranding.objects.get(pk=1)
        if branding.logo:
            files_storage.default_storage.delete(branding.logo.name)

        served = self.anon.get("/api/branding/logo/")
        self.assertEqual(served.status_code, 200)
        self.assertEqual(served["Content-Type"], "image/jpeg")
        self.assertTrue(self.anon.get("/api/branding/").json()["data"]["has_logo"])

    def test_super_removes_logo(self):
        from django.core.files.uploadedfile import SimpleUploadedFile

        upload = SimpleUploadedFile("logo.jpg", _jpeg_bytes(), content_type="image/jpeg")
        self.super.post("/api/admin/branding/logo/", {"image": upload, "alt": "x"}, format="multipart")

        resp = self.super.delete("/api/admin/branding/logo/")
        self.assertEqual(resp.status_code, 200)
        self.assertTrue(resp.json()["data"]["removed"])
        self.assertEqual(self.anon.get("/api/branding/logo/").status_code, 404)
        public = self.anon.get("/api/branding/").json()["data"]
        self.assertFalse(public["has_logo"])
        self.assertTrue(
            AuditLog.objects.filter(action_code="branding.logo_remove", result="SUCCESS").exists()
        )

    def test_invalid_upload_rejected(self):
        from django.core.files.uploadedfile import SimpleUploadedFile

        bad = SimpleUploadedFile("logo.txt", b"not an image", content_type="text/plain")
        resp = self.super.post("/api/admin/branding/logo/", {"image": bad}, format="multipart")
        self.assertEqual(resp.status_code, 400)
        self.assertFalse(
            self.anon.get("/api/branding/").json()["data"]["has_logo"]
        )

    def test_upload_requires_image_field(self):
        resp = self.super.post("/api/admin/branding/logo/", {"alt": "x"}, format="multipart")
        self.assertEqual(resp.status_code, 400)