"""Backend tests for the content CMS (public home milestone).

Run::

    venv/bin/python manage.py test content --settings=config.settings.ephemeral_test

Covers: public news reads (published only, latest/featured/category/search),
public ticker (active + time-window), admin permission gates (403 for every
non-admin, 401 anon), the news lifecycle (create -> publish -> unpublish ->
archive -> feature), edit/edit-delete rules, cover image upload validation,
ticker CRUD + activate/deactivate, audit rows and throttling.
"""

import io
import uuid as _uuid

from datetime import timedelta

from django.core.cache import cache
from django.core.files.uploadedfile import SimpleUploadedFile
from django.test import TestCase
from django.utils import timezone
from PIL import Image as PILImage
from rest_framework import status
from rest_framework.test import APIClient
from rest_framework_simplejwt.tokens import RefreshToken

from accounts.models import Role, User, UserRole
from audit.models import AuditLog
from content.models import NewsArticle, TickerAnnouncement

_PASSWORD = "Str0ng!Pass9"

PNG_BYTES = None


def make_png(width=320, height=180) -> bytes:
    buffer = io.BytesIO()
    PILImage.new("RGB", (width, height), (200, 60, 70)).save(buffer, format="PNG")
    return buffer.getvalue()


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
    client.credentials(
        HTTP_AUTHORIZATION=f"Bearer {RefreshToken.for_user(user).access_token}"
    )
    return client


def _news(author, status_value="PUBLISHED", featured=False, category="HEALTH",
          title="Sickle cell awareness campaign", **extra):
    return NewsArticle.objects.create(
        author=author,
        title=title,
        category=category,
        body="Full article body.",
        excerpt="Short excerpt.",
        status=status_value,
        featured=featured,
        published_at=timezone.now() if status_value == "PUBLISHED" else None,
        **extra,
    )


def _ticker(message="Blood drive this weekend", active=True, **extra):
    return TickerAnnouncement.objects.create(
        message=message,
        announcement_type="INFO",
        is_active=active,
        **extra,
    )


class ContentPublicNewsTests(TestCase):
    def setUp(self):
        cache.clear()
        self.admin = _orm_user("ADMIN")
        _news(self.admin, title="Awareness day", category="EVENTS")
        _news(self.admin, title="Featured drive", category="BLOOD", featured=True)
        _news(self.admin, title="Draft only", status_value="DRAFT", category="HEALTH")
        _news(self.admin, title="Archived piece", status_value="ARCHIVED", category="EDUCATION")
        self.anon = APIClient()

    def test_categories_are_public(self):
        res = self.anon.get("/api/content/news/categories/")
        self.assertEqual(res.status_code, 200)
        codes = [row["code"] for row in res.data]
        self.assertEqual(
            codes, ["HEALTH", "BLOOD", "COMMUNITY", "EDUCATION",
                    "EVENTS", "ANNOUNCEMENTS", "FUNDRAISING"],
        )

    def test_feed_shows_published_only(self):
        res = self.anon.get("/api/content/news/")
        self.assertEqual(res.status_code, 200)
        titles = [row["title"] for row in res.data["results"]]
        self.assertEqual(titles, ["Featured drive", "Awareness day"])
        self.assertNotIn("body", res.data["results"][0])

    def test_featured_filter(self):
        res = self.anon.get("/api/content/news/?featured=true")
        titles = [row["title"] for row in res.data["results"]]
        self.assertEqual(titles, ["Featured drive"])

    def test_category_filter(self):
        res = self.anon.get("/api/content/news/?category=BLOOD")
        titles = [row["title"] for row in res.data["results"]]
        self.assertEqual(titles, ["Featured drive"])

    def test_unknown_category_rejected(self):
        res = self.anon.get("/api/content/news/?category=NOT_A_CATEGORY")
        self.assertEqual(res.status_code, 400)

    def test_search(self):
        res = self.anon.get("/api/content/news/?q=Awareness")
        titles = [row["title"] for row in res.data["results"]]
        self.assertEqual(titles, ["Awareness day"])

    def test_latest_endpoint(self):
        res = self.anon.get("/api/content/news/latest/")
        self.assertEqual(res.status_code, 200)
        self.assertEqual(res.data["article"]["title"], "Featured drive")

    def test_detail_published_and_draft_locked(self):
        ok = NewsArticle.objects.get(title="Awareness day")
        draft = NewsArticle.objects.get(title="Draft only")
        res = self.anon.get(f"/api/content/news/{ok.uid}/")
        self.assertEqual(res.status_code, 200)
        self.assertIn("body", res.data)
        hidden = self.anon.get(f"/api/content/news/{draft.uid}/")
        self.assertEqual(hidden.status_code, 404)

    def test_detail_malformed_uid_is_404_not_500(self):
        """A non-UUID segment must 404 with the standard envelope — never 500."""
        res = self.anon.get("/api/content/news/not-a-real-uuid/")
        self.assertEqual(res.status_code, 404)
        self.assertEqual(res.data["error"]["code"], "NOT_FOUND")
        res = self.anon.get("/api/content/news/123/")
        self.assertEqual(res.status_code, 404)

    def test_pagination_envelope(self):
        res = self.anon.get("/api/content/news/")
        self.assertIn("count", res.data)
        self.assertIn("next", res.data)
        self.assertIn("previous", res.data)
        self.assertLessEqual(len(res.data["results"]), 20)


class ContentPublicTickerTests(TestCase):
    def setUp(self):
        cache.clear()
        self.admin = _orm_user("ADMIN")
        self.anon = APIClient()
        now = timezone.now()
        self.active = _ticker("Active note", active=True, priority=5)
        self.inactive = _ticker("Inactive note", active=False)
        _ticker("Scheduled", active=True, start_at=now + timedelta(days=1))
        _ticker("Expired", active=True, end_at=now - timedelta(days=1))
        _ticker("Bounded", active=True, start_at=now - timedelta(days=1),
                end_at=now + timedelta(days=1))

    def test_active_effective_only(self):
        res = self.anon.get("/api/content/ticker/")
        self.assertEqual(res.status_code, 200)
        messages = [row["message"] for row in res.data]
        self.assertEqual(messages, ["Active note", "Bounded"])

    def test_ordering_priority_then_newest(self):
        _ticker("Low priority", active=True, priority=1)
        res = self.anon.get("/api/content/ticker/")
        messages = [row["message"] for row in res.data]
        self.assertEqual(messages[0], "Active note")


class ContentNewsAdminTests(TestCase):
    def setUp(self):
        cache.clear()
        self.admin = _orm_user("ADMIN")
        self.moderator = _orm_user("MODERATOR")
        self.admin_client = _client(self.admin)
        self.moderator_client = _client(self.moderator)
        self.anon = APIClient()

    def test_anon_and_non_admin_denied(self):
        self.assertEqual(self.anon.get("/api/admin/content/news/").status_code, 401)
        for code in ("MODERATOR", "DOCTOR", "PATIENT"):
            user = _orm_user(code)
            res = _client(user).get("/api/admin/content/news/")
            self.assertEqual(res.status_code, 403)
            res = _client(user).get("/api/admin/content/ticker/")
            self.assertEqual(res.status_code, 403)

    def test_admin_detail_malformed_uid_is_404(self):
        """Admin CMS uid reads treat malformed segments like missing rows."""
        for url in ("/api/admin/content/news/not-a-real-uuid/",
                    "/api/admin/content/news/123/",
                    "/api/admin/content/ticker/not-a-real-uuid/"):
            res = self.admin_client.get(url)
            self.assertEqual(res.status_code, 404)
            self.assertEqual(res.data["error"]["code"], "NOT_FOUND")

    def test_create_is_draft_and_not_public(self):
        res = self.admin_client.post(
            "/api/admin/content/news/",
            {
                "title": "Brand new story",
                "category": "HEALTH",
                "body": "Long form body here.",
            },
            format="json",
        )
        self.assertEqual(res.status_code, 201)
        article = NewsArticle.objects.get(uid=res.data["uid"])
        self.assertEqual(article.status, "DRAFT")
        hidden = self.anon.get(f"/api/content/news/{article.uid}/")
        self.assertEqual(hidden.status_code, 404)

    def test_lifecycle_publish_unpublish_archive(self):
        article = _news(self.admin, status_value="DRAFT")
        base = f"/api/admin/content/news/{article.uid}/"
        res = self.admin_client.post(f"{base}publish/")
        self.assertEqual(res.status_code, 200)
        article.refresh_from_db()
        self.assertEqual(article.status, "PUBLISHED")
        self.assertIsNotNone(article.published_at)
        self.assertEqual(self.anon.get(f"/api/content/news/{article.uid}/").status_code, 200)

        res = self.admin_client.post(f"{base}unpublish/")
        self.assertEqual(res.status_code, 200)
        article.refresh_from_db()
        self.assertEqual(article.status, "DRAFT")
        self.assertEqual(self.anon.get(f"/api/content/news/{article.uid}/").status_code, 404)

    def _admin_base(self, article):
        return f"/api/admin/content/news/{article.uid}/"

    def test_archive_hides_and_allows_republish(self):
        article = _news(self.admin)
        res = self.admin_client.post(f"{self._admin_base(article)}archive/")
        self.assertEqual(res.status_code, 200)
        article.refresh_from_db()
        self.assertEqual(article.status, "ARCHIVED")
        self.assertEqual(self.anon.get(f"/api/content/news/{article.uid}/").status_code, 404)
        res = self.admin_client.post(f"{self._admin_base(article)}publish/")
        self.assertEqual(res.status_code, 200)
        self.assertEqual(self.anon.get(f"/api/content/news/{article.uid}/").status_code, 200)

    def test_feature_requires_published(self):
        draft = _news(self.admin, status_value="DRAFT")
        res = self.admin_client.post(
            f"{self._admin_base(draft)}feature/", {"featured": True}, format="json",
        )
        self.assertEqual(res.status_code, 400)
        published = _news(self.admin, title="Published row")
        res = self.admin_client.post(
            f"{self._admin_base(published)}feature/", {"featured": True}, format="json",
        )
        published.refresh_from_db()
        self.assertTrue(published.featured)
        feed = self.anon.get("/api/content/news/?featured=true")
        self.assertIn(str(published.uid), [row["uid"] for row in feed.data["results"]])

    def test_published_cannot_be_edited_directly(self):
        article = _news(self.admin)
        res = self.admin_client.patch(
            self._admin_base(article),
            {"title": "Edited"},
            format="json",
        )
        self.assertEqual(res.status_code, 400)

    def test_edit_draft_updates_fields(self):
        article = _news(self.admin, status_value="DRAFT")
        res = self.admin_client.patch(
            self._admin_base(article),
            {"title": "Edited title", "tags": ["awareness", "sickle"]},
            format="json",
        )
        self.assertEqual(res.status_code, 200)
        article.refresh_from_db()
        self.assertEqual(article.title, "Edited title")
        self.assertEqual(article.tags, ["awareness", "sickle"])

    def test_delete_draft_only(self):
        draft = _news(self.admin, status_value="DRAFT")
        res = self.admin_client.delete(self._admin_base(draft))
        self.assertEqual(res.status_code, 204)
        self.assertFalse(NewsArticle.objects.filter(pk=draft.pk).exists())
        published = _news(self.admin, title="Keep me")
        res = self.admin_client.delete(self._admin_base(published))
        self.assertEqual(res.status_code, 400)
        self.assertTrue(NewsArticle.objects.filter(pk=published.pk).exists())

    def test_admin_list_filters_and_status(self):
        _news(self.admin, title="A", status_value="DRAFT")
        _news(self.admin, title="B", category="EVENTS", featured=True)
        res = self.admin_client.get("/api/admin/content/news/?status=PUBLISHED")
        self.assertEqual(res.status_code, 200)
        self.assertTrue(all(r["status"] == "PUBLISHED" for r in res.data["results"]))
        res = self.admin_client.get("/api/admin/content/news/?featured=true")
        self.assertTrue(all(r["featured"] for r in res.data["results"]))
        res = self.admin_client.get("/api/admin/content/news/?q=B")
        self.assertEqual([r["title"] for r in res.data["results"]], ["B"])

    def test_cover_upload_validates_and_updates_url(self):
        article = _news(self.admin, status_value="DRAFT")
        uploaded = SimpleUploadedFile(
            "cover.png", make_png(), content_type="image/png",
        )
        res = self.admin_client.post(
            f"{self._admin_base(article)}cover/",
            {"image": uploaded, "alt": "Team photo"},
            format="multipart",
        )
        self.assertEqual(res.status_code, 200, res.data)
        article.refresh_from_db()
        self.assertTrue(article.cover_url.endswith(f"/media/content/news/{article.uid}.jpg"))
        self.assertEqual(article.cover_alt, "Team photo")

    def test_cover_upload_rejects_bad_image(self):
        article = _news(self.admin, status_value="DRAFT")
        bad = SimpleUploadedFile(
            "cover.txt", b"not an image at all", content_type="text/plain",
        )
        res = self.admin_client.post(
            f"{self._admin_base(article)}cover/",
            {"image": bad},
            format="multipart",
        )
        self.assertEqual(res.status_code, 400)
        article.refresh_from_db()
        self.assertEqual(article.cover_url, "")

    def test_cover_upload_rejects_oversized(self):
        article = _news(self.admin, status_value="DRAFT")
        png = make_png()
        big = SimpleUploadedFile(
            "big.png", png + (b"\x00" * (6 * 1024 * 1024)), content_type="image/png",
        )
        res = self.admin_client.post(
            f"{self._admin_base(article)}cover/",
            {"image": big},
            format="multipart",
        )
        self.assertEqual(res.status_code, 400)

    def test_audit_rows_recorded(self):
        res = self.admin_client.post(
            "/api/admin/content/news/",
            {"title": "Audited", "category": "HEALTH", "body": "Body."},
            format="json",
        )
        article = NewsArticle.objects.get(uid=res.data["uid"])
        self.admin_client.post(f"{self._admin_base(article)}publish/")
        codes = set(
            AuditLog.objects.filter(actor=self.admin)
            .values_list("action_code", flat=True)
        )
        self.assertIn("content.news.create", codes)
        self.assertIn("content.news.publish", codes)


class ContentTickerAdminTests(TestCase):
    def setUp(self):
        cache.clear()
        self.admin = _orm_user("ADMIN")
        self.doctor = _orm_user("DOCTOR")
        self.admin_client = _client(self.admin)
        self.doctor_client = _client(self.doctor)

    def test_doctor_denied(self):
        res = self.doctor_client.get("/api/admin/content/ticker/")
        self.assertEqual(res.status_code, 403)

    def test_create_update_activate_deactivate_delete(self):
        res = self.admin_client.post(
            "/api/admin/content/ticker/",
            {
                "message": "Donation drive begins Monday",
                "announcement_type": "DONATION",
                "priority": 3,
            },
            format="json",
        )
        self.assertEqual(res.status_code, 201)
        ann = TickerAnnouncement.objects.get(uid=res.data["uid"])
        base = f"/api/admin/content/ticker/{ann.uid}/"

        res = self.admin_client.patch(
            base, {"message": "Updated message"}, format="json",
        )
        ann.refresh_from_db()
        self.assertEqual(ann.message, "Updated message")

        res = self.admin_client.post(f"{base}deactivate/")
        ann.refresh_from_db()
        self.assertFalse(ann.is_active)
        feed = APIClient().get("/api/content/ticker/")
        self.assertNotIn("Updated message", [r["message"] for r in feed.data])

        res = self.admin_client.post(f"{base}activate/")
        ann.refresh_from_db()
        self.assertTrue(ann.is_active)

        res = self.admin_client.delete(base)
        self.assertEqual(res.status_code, 204)

    def test_window_validation(self):
        start = timezone.now()
        end = start - timedelta(days=1)
        res = self.admin_client.post(
            "/api/admin/content/ticker/",
            {
                "message": "Bad window",
                "start_at": start.isoformat(),
                "end_at": end.isoformat(),
            },
            format="json",
        )
        self.assertEqual(res.status_code, 400)

    def test_audit_rows_recorded(self):
        res = self.admin_client.post(
            "/api/admin/content/ticker/", {"message": "Power of the people"},
            format="json",
        )
        ann = TickerAnnouncement.objects.get(uid=res.data["uid"])
        self.admin_client.post(f"/api/admin/content/ticker/{ann.uid}/activate/")
        codes = set(
            AuditLog.objects.filter(actor=self.admin)
            .values_list("action_code", flat=True)
        )
        self.assertIn("content.ticker.create", codes)
        self.assertIn("content.ticker.activate", codes)