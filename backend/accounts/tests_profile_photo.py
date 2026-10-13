"""Profile-photo upload tests (§ 35 / me/photo).

Run::

    venv/bin/python manage.py test accounts.tests_profile_photo --settings=config.settings.ephemeral_test

Covers:

* **Owner upload** — a PATIENT posts a valid PNG, receives the updated user
  summary with a ``profile_photo_url`` under ``/media/accounts/avatars/`` and
  the field is persisted.
* **Envelope + /me propagation** — the response and a follow-up ``GET /me``
  both advertise the new URL.
* **Rejection** — non-image bytes and oversized files are rejected with 400
  and never mutate the stored URL.
* **Authorization** — anonymous uploads are denied with 401.
"""

import io
import uuid as _uuid

from django.core.cache import cache
from django.core.files.uploadedfile import SimpleUploadedFile
from django.test import TestCase
from PIL import Image
from rest_framework.test import APIClient
from rest_framework_simplejwt.tokens import RefreshToken

from .models import User

_PASSWORD = "Str0ng!Pass9"


def _make_png(size=(8, 8), color=(214, 32, 68)):
    buf = io.BytesIO()
    Image.new("RGB", size, color).save(buf, format="PNG")
    return buf.getvalue()


def _orm_user():
    email = f"photo-{_uuid.uuid4().hex[:10]}@example.com"
    user = User.objects.create_user(
        email=email,
        password=_PASSWORD,
        first_name="Profile",
        last_name="Photo",
        account_status="ACTIVE",
    )
    return user


def _client(user):
    client = APIClient()
    client.credentials(
        HTTP_AUTHORIZATION=f"Bearer {RefreshToken.for_user(user).access_token}"
    )
    return client


class MeProfilePhotoTests(TestCase):
    def setUp(self):
        cache.clear()

    def test_owner_uploads_photo_and_me_propagates_it(self):
        user = _orm_user()
        client = _client(user)
        uploaded = SimpleUploadedFile(
            "face.png", _make_png(), content_type="image/png",
        )
        res = client.post(
            "/api/auth/me/photo/", {"image": uploaded}, format="multipart",
        )
        self.assertEqual(res.status_code, 200, res.data)
        data = res.json()["data"]
        self.assertTrue(
            data["profile_photo_url"].startswith(
                "http://testserver/media/accounts/avatars/"
            ),
            data["profile_photo_url"],
        )
        user.refresh_from_db()
        # The row stays backend-relative (no request Host pinned in); the API
        # serves it absolute against the caller's origin (core.media).
        self.assertTrue(
            user.profile_photo_url.startswith("/media/accounts/avatars/"),
            user.profile_photo_url,
        )
        self.assertEqual(
            data["profile_photo_url"],
            f"http://testserver{user.profile_photo_url}",
        )

        me = client.get("/api/auth/me/")
        self.assertEqual(me.status_code, 200)
        self.assertEqual(me.json()["data"]["profile_photo_url"], data["profile_photo_url"])

    def test_rejects_non_image_and_keeps_previous_url(self):
        user = _orm_user()
        client = _client(user)
        bad = SimpleUploadedFile(
            "face.txt", b"definitely not an image", content_type="text/plain",
        )
        res = client.post(
            "/api/auth/me/photo/", {"image": bad}, format="multipart",
        )
        self.assertEqual(res.status_code, 400)
        user.refresh_from_db()
        self.assertIsNone(user.profile_photo_url)

    def test_rejects_oversized_upload(self):
        user = _orm_user()
        client = _client(user)
        png = _make_png()
        big = SimpleUploadedFile(
            "face.png", png + (b"\x00" * (6 * 1024 * 1024)),
            content_type="image/png",
        )
        res = client.post(
            "/api/auth/me/photo/", {"image": big}, format="multipart",
        )
        self.assertEqual(res.status_code, 400)
        user.refresh_from_db()
        self.assertIsNone(user.profile_photo_url)

    def test_anonymous_upload_is_rejected(self):
        uploaded = SimpleUploadedFile(
            "face.png", _make_png(), content_type="image/png",
        )
        res = APIClient().post(
            "/api/auth/me/photo/", {"image": uploaded}, format="multipart",
        )
        self.assertEqual(res.status_code, 401)

class MeProfilePhotoClientCompatibilityTests(TestCase):
    """The two failure modes that made profile pictures unusable in the app.

    1. The mobile client posts a multipart part with **no** declared type, so
       the part arrives as ``application/octet-stream``. That must still be
       accepted when the bytes really are an image.
    2. Re-uploading must **replace** the stored file, not orphan the previous
       one under a suffixed name while the user's URL points at the old file.
    """

    def setUp(self):
        cache.clear()
        self.user = _orm_user()
        self.client = _client(self.user)

    def test_octet_stream_part_from_the_mobile_client_is_accepted(self):
        # No content_type kwarg — exactly what MultipartFile.fromPath without
        # an explicit contentType produces.
        uploaded = SimpleUploadedFile("face.png", _make_png(), content_type="application/octet-stream")
        res = self.client.post(
            "/api/auth/me/photo/", {"image": uploaded}, format="multipart",
        )
        self.assertEqual(res.status_code, 200, res.json())
        self.assertTrue(
            res.json()["data"]["profile_photo_url"].endswith(".jpg"),
            res.json()["data"]["profile_photo_url"],
        )

    def test_reupload_replaces_the_same_storage_key(self):
        from django.core.files.storage import default_storage

        first = SimpleUploadedFile("a.png", _make_png(color=(10, 20, 30)), content_type="image/png")
        self.assertEqual(
            self.client.post("/api/auth/me/photo/", {"image": first}, format="multipart").status_code,
            200,
        )
        second = SimpleUploadedFile("b.png", _make_png(color=(200, 100, 50)), content_type="image/png")
        res = self.client.post("/api/auth/me/photo/", {"image": second}, format="multipart")
        self.assertEqual(res.status_code, 200, res.json())

        key = f"accounts/avatars/{self.user.uid}.jpg"
        # One stable object for this user: no suffixed leftovers from either
        # upload (other users' avatars in the shared media dir are unrelated).
        mine = [p for p in default_storage.listdir("accounts/avatars")[1] if str(self.user.uid) in p]
        self.assertEqual(mine, [f"{self.user.uid}.jpg"])
        self.assertTrue(res.json()["data"]["profile_photo_url"].endswith(key))

    def test_legacy_relative_media_url_is_normalised_on_reupload(self):
        from django.core.files.storage import default_storage
        from django.core.files.base import ContentFile

        # A row written while MEDIA_URL was the relative "media/".
        legacy = default_storage.save("accounts/avatars/legacy_avatar.jpg", ContentFile(b"x"))
        self.user.profile_photo_url = f"http://testserver/media/{legacy}"
        self.user.save(update_fields=["profile_photo_url"])
        uploaded = SimpleUploadedFile("c.png", _make_png(), content_type="image/png")
        res = self.client.post("/api/auth/me/photo/", {"image": uploaded}, format="multipart")
        self.assertEqual(res.status_code, 200, res.json())
        self.user.refresh_from_db()
        # Re-upload writes the host-free relative path.
        self.assertTrue(
            self.user.profile_photo_url.startswith("/media/accounts/avatars/"),
            self.user.profile_photo_url,
        )
        # ...and the *old* pinned absolute row still resolves correctly through
        # the response renderer (healed at read time, no data migration).
        from core.media import media_url
        self.assertEqual(media_url(f"http://testserver/media/{legacy}"), f"/media/{legacy}")

    def test_photo_change_is_audited_without_recording_the_image(self):
        from audit.models import AuditLog

        uploaded = SimpleUploadedFile("d.png", _make_png(), content_type="image/png")
        self.client.post("/api/auth/me/photo/", {"image": uploaded}, format="multipart")
        entry = AuditLog.objects.filter(
            actor=self.user, action_code="accounts.profile_photo_updated"
        ).latest("created_at")
        self.assertIsNotNone(entry)
        self.assertNotIn("image", entry.details)


class ProfileUploadValidationTests(TestCase):
    """The declared-type gate stays strict where it matters."""

    def setUp(self):
        self.user = _orm_user()
        self.client = _client(self.user)

    def _post(self, name, payload, content_type):
        return self.client.post(
            "/api/auth/me/photo/",
            {"image": SimpleUploadedFile(name, payload, content_type=content_type)},
            format="multipart",
        )

    def test_a_declared_non_image_type_is_rejected(self):
        res = self._post("notes.html", b"<html>nope</html>", "text/html")
        self.assertEqual(res.status_code, 400)

    def test_a_pdf_is_rejected(self):
        res = self._post("doc.pdf", b"%PDF-1.4", "application/pdf")
        self.assertEqual(res.status_code, 400)

    def test_octet_stream_bytes_that_are_not_an_image_are_rejected(self):
        res = self._post("blob.bin", b"not an image at all", "application/octet-stream")
        self.assertEqual(res.status_code, 400)

    def test_a_valid_image_larger_than_the_pixel_ceiling_is_rejected(self):
        # 9000x9000 = 81 MP, above the 40 MP decompression guard.
        huge = io.BytesIO()
        Image.new("RGB", (9000, 9000)).save(huge, format="PNG")
        res = self._post("huge.png", huge.getvalue(), "image/png")
        self.assertEqual(res.status_code, 400)

    def test_oversized_file_is_rejected(self):
        from content.upload_validation import MAX_IMAGE_BYTES

        big = _make_png() + b"\0" * (MAX_IMAGE_BYTES + 1024)
        res = self._post("big.png", big, "image/png")
        self.assertEqual(res.status_code, 400)
