"""Backend tests for the Stage 4.10 community API.

Run::

    venv/bin/python manage.py test community --settings=config.settings.ephemeral_test

Covers: post create/sanitize, visibility (author/moderator), ownership
isolation, soft delete, reactions toggle, comments, reports (dedupe, spoiler
metadata), hide-first moderation, audit rows, rate-limit 429, and the data
boundary (no author email/PHI leakage).
"""

import uuid as _uuid

from django.core.cache import cache
from django.test import TestCase
from rest_framework.test import APIClient
from rest_framework_simplejwt.tokens import RefreshToken

from accounts.models import Role, User, UserRole
from audit.models import AuditLog
from community.models import Comment, CommunityPost, Reaction, Report

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


class CommunityApiTests(TestCase):
    def setUp(self):
        cache.clear()
        self.patient = _orm_user("PATIENT")
        self.other = _orm_user("PATIENT")
        self.moderator = _orm_user("MODERATOR")
        self.doctor = _orm_user("DOCTOR")
        self.patient_client = _client(self.patient)
        self.other_client = _client(self.other)
        self.moderator_client = _client(self.moderator)
        self.doctor_client = _client(self.doctor)

    def _post(self, client=None, **overrides):
        body = {"title": "Hello", "content": "A support message", "category": "SUPPORT", **overrides}
        return (client or self.patient_client).post("/api/community/posts/", body, format="json")

    # --- posts ---------------------------------------------------------------
    def test_create_post_requires_auth_and_permission(self):
        anon = APIClient().post("/api/community/posts/", {"content": "hi"}, format="json")
        self.assertEqual(anon.status_code, 401)
        created = self._post()
        self.assertEqual(created.status_code, 201)
        self.assertEqual(created.data["category"], "SUPPORT")
        self.assertEqual(created.data["status"], "PUBLISHED")
        self.assertTrue(created.data["is_author"])
        self.assertTrue(
            AuditLog.objects.filter(action_code="community_posts.create").exists()
        )

    def test_create_post_sanitizes_html(self):
        created = self._post(content='<script>alert("x")</script>Hello <b>world</b>')
        self.assertEqual(created.status_code, 201)
        self.assertNotIn("<script", created.data["content"])
        self.assertIn("<b>world</b>", created.data["content"])

    def test_author_projection_hides_private_fields(self):
        created = self._post()
        author = created.data["author"]
        self.assertEqual(set(author.keys()), {"uid", "display_name"})
        self.assertNotIn("email", created.data)
        self.assertNotIn("phone", created.data)

    def test_visibility_of_hidden_post(self):
        post = CommunityPost.objects.create(
            author=self.patient, content="hidden body", status="HIDDEN",
        )
        # Author still sees own hidden post.
        mine = self.patient_client.get(f"/api/community/posts/{post.uid}/")
        self.assertEqual(mine.status_code, 200)
        # Another member does not.
        other = self.other_client.get(f"/api/community/posts/{post.uid}/")
        self.assertEqual(other.status_code, 404)
        # Moderator sees it.
        mod = self.moderator_client.get(f"/api/community/posts/{post.uid}/")
        self.assertEqual(mod.status_code, 200)

    def test_update_delete_ownership(self):
        created = self._post()
        uid = created.data["uid"]
        denied = self.other_client.patch(
            f"/api/community/posts/{uid}/", {"content": "hijack"}, format="json",
        )
        self.assertEqual(denied.status_code, 403)
        ok = self.patient_client.patch(
            f"/api/community/posts/{uid}/", {"content": "edited"}, format="json",
        )
        self.assertEqual(ok.status_code, 200)
        self.assertEqual(ok.data["content"], "edited")
        deleted = self.patient_client.delete(f"/api/community/posts/{uid}/")
        self.assertEqual(deleted.status_code, 204)
        post = CommunityPost.objects.get(uid=uid)
        self.assertIsNotNone(post.deleted_at)
        self.assertEqual(post.status, "REMOVED")
        self.assertEqual(self.patient_client.get(f"/api/community/posts/{uid}/").status_code, 404)

    def test_list_filters_by_category_and_mine(self):
        self._post(category="SUPPORT")
        self._post(category="GENERAL")
        self._post(client=self.other_client, category="GENERAL")
        general = self.patient_client.get("/api/community/posts/?category=GENERAL")
        self.assertEqual(general.data["count"], 2)
        mine = self.patient_client.get("/api/community/posts/?author=me")
        self.assertEqual(mine.data["count"], 2)

    # --- reactions -----------------------------------------------------------
    def test_reaction_toggle(self):
        uid = self._post().data["uid"]
        on = self.patient_client.post(
            f"/api/community/posts/{uid}/reactions/", {"reaction_type": "LIKE"}, format="json",
        )
        self.assertEqual(on.status_code, 200)
        self.assertTrue(on.data["reacted"])
        self.assertEqual(on.data["reaction_count"], 1)
        # Idempotent create (no duplicate row).
        self.patient_client.post(
            f"/api/community/posts/{uid}/reactions/", {"reaction_type": "LIKE"}, format="json",
        )
        self.assertEqual(Reaction.objects.filter(post__uid=uid).count(), 1)
        off = self.patient_client.delete(
            f"/api/community/posts/{uid}/reactions/", {"reaction_type": "LIKE"}, format="json",
        )
        self.assertEqual(off.status_code, 200)
        self.assertFalse(off.data["reacted"])

    # --- comments ------------------------------------------------------------
    def test_comment_create_and_isolation(self):
        uid = self._post().data["uid"]
        created = self.other_client.post(
            f"/api/community/posts/{uid}/comments/", {"content": "Nice"}, format="json",
        )
        self.assertEqual(created.status_code, 201)
        listing = self.patient_client.get(f"/api/community/posts/{uid}/comments/")
        self.assertEqual(listing.data["count"], 1)
        cid = created.data["id"]
        denied = self.patient_client.patch(
            f"/api/community/posts/{uid}/comments/{cid}/", {"content": "x"}, format="json",
        )
        self.assertEqual(denied.status_code, 403)
        ok = self.other_client.patch(
            f"/api/community/posts/{uid}/comments/{cid}/", {"content": "updated"}, format="json",
        )
        self.assertEqual(ok.status_code, 200)

    def test_comment_on_hidden_post_rejected(self):
        post = CommunityPost.objects.create(author=self.patient, content="x", status="HIDDEN")
        resp = self.other_client.post(
            f"/api/community/posts/{post.uid}/comments/", {"content": "x"}, format="json",
        )
        self.assertEqual(resp.status_code, 400)

    # --- reports -------------------------------------------------------------
    def test_report_create_dedupe_and_validation(self):
        uid = self._post().data["uid"]
        post = CommunityPost.objects.get(uid=uid)
        ok = self.other_client.post(
            "/api/community/reports/",
            {"target_type": "POST", "target_id": post.pk, "reason": "spam"},
            format="json",
        )
        self.assertEqual(ok.status_code, 201)
        dup = self.other_client.post(
            "/api/community/reports/",
            {"target_type": "POST", "target_id": post.pk, "reason": "spam again"},
            format="json",
        )
        self.assertEqual(dup.status_code, 400)
        missing = self.other_client.post(
            "/api/community/reports/",
            {"target_type": "POST", "target_id": 999999, "reason": "x"},
            format="json",
        )
        self.assertEqual(missing.status_code, 404)

    # --- moderation ----------------------------------------------------------
    def test_admin_reports_permission_and_hide_first(self):
        uid = self._post().data["uid"]
        post = CommunityPost.objects.get(uid=uid)
        self.other_client.post(
            "/api/community/reports/",
            {"target_type": "POST", "target_id": post.pk, "reason": "abuse"},
            format="json",
        )
        report = Report.objects.get(target_id=post.pk)
        denied_list = self.doctor_client.get("/api/admin/community/reports/")
        self.assertEqual(denied_list.status_code, 403)
        listing = self.moderator_client.get("/api/admin/community/reports/")
        self.assertEqual(listing.status_code, 200)
        self.assertEqual(listing.data["count"], 1)
        # Hide requires a reason.
        bad = self.moderator_client.post(
            f"/api/admin/community/reports/{report.pk}/resolve/",
            {"status": "RESOLVED", "action": "HIDE"},
            format="json",
        )
        self.assertEqual(bad.status_code, 400)
        resolved = self.moderator_client.post(
            f"/api/admin/community/reports/{report.pk}/resolve/",
            {"status": "RESOLVED", "action": "HIDE", "review_notes": "policy breach"},
            format="json",
        )
        self.assertEqual(resolved.status_code, 200)
        post.refresh_from_db()
        self.assertEqual(post.status, "HIDDEN")
        self.assertEqual(post.moderated_by_id, self.moderator.pk)
        self.assertTrue(AuditLog.objects.filter(action_code="community.moderate").exists())

    def test_moderator_can_moderate_comment(self):
        uid = self._post().data["uid"]
        comment = Comment.objects.create(
            post=CommunityPost.objects.get(uid=uid), author=self.other, content="bad",
        )
        report = Report.objects.create(
            reporter=self.patient, target_type="COMMENT", target_id=comment.pk, reason="abuse",
        )
        resp = self.moderator_client.post(
            f"/api/admin/community/reports/{report.pk}/resolve/",
            {"status": "RESOLVED", "action": "REMOVE", "review_notes": "removed"},
            format="json",
        )
        self.assertEqual(resp.status_code, 200)
        comment.refresh_from_db()
        self.assertEqual(comment.status, "REMOVED")

    def test_reaction_throttle_429(self):
        uid = self._post().data["uid"]
        for _ in range(30):
            self.patient_client.post(
                f"/api/community/posts/{uid}/reactions/", {"reaction_type": "LIKE"}, format="json",
            )
        blocked = self.patient_client.post(
            f"/api/community/posts/{uid}/reactions/", {"reaction_type": "LIKE"}, format="json",
        )
        self.assertEqual(blocked.status_code, 429)
