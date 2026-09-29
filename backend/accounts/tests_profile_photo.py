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
        self.assertEqual(user.profile_photo_url, data["profile_photo_url"])

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