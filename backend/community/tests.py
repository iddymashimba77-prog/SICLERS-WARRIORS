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
from community.models import Comment, CommunityPost, ForumCategory, Reaction, Report

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


class ForumExtensionApiTests(TestCase):
    """Forum categories, threading, moderation controls and scoped inbox."""

    def setUp(self):
        cache.clear()
        self.patient = _orm_user("PATIENT")
        self.other = _orm_user("PATIENT")
        self.doctor = _orm_user("DOCTOR")
        self.moderator = _orm_user("MODERATOR")
        self.admin = _orm_user("ADMIN")
        self.patient_client = _client(self.patient)
        self.other_client = _client(self.other)
        self.doctor_client = _client(self.doctor)
        self.moderator_client = _client(self.moderator)
        self.admin_client = _client(self.admin)

    def _post(self, client=None, **overrides):
        body = {"title": "Forum thread", "content": "A support message", "category": "SUPPORT", **overrides}
        return (client or self.patient_client).post("/api/community/posts/", body, format="json")

    def _comment(self, uid, client=None, content="A comment", parent_id=None):
        body = {"content": content}
        if parent_id is not None:
            body["parent_id"] = parent_id
        return (client or self.other_client).post(
            f"/api/community/posts/{uid}/comments/", body, format="json",
        )

    # --- admin boundary ------------------------------------------------------
    def test_admin_roles_are_denied_all_member_forum_surfaces(self):
        uid = self._post().data["uid"]
        endpoints = [
            ("get", "/api/community/posts/"),
            ("get", "/api/community/categories/"),
            ("get", "/api/community/notifications/"),
            ("get", "/api/community/notifications/unread-count/"),
            ("get", f"/api/community/posts/{uid}/comments/"),
            ("post", f"/api/community/posts/{uid}/comments/"),
        ]
        for method, url in endpoints:
            client_method = getattr(self.admin_client, method)
            kwargs = {"data": {"content": "x"}, "format": "json"} if method == "post" else {}
            resp = client_method(url, **kwargs)
            self.assertEqual(resp.status_code, 403, f"{method.upper()} {url}")
        created = self.admin_client.post(
            "/api/community/posts/", {"content": "admin post"}, format="json",
        )
        self.assertEqual(created.status_code, 403)

    def test_super_admin_is_denied(self):
        super_admin = _orm_user("SUPER_ADMIN")
        resp = _client(super_admin).get("/api/community/posts/")
        self.assertEqual(resp.status_code, 403)

    # --- categories ----------------------------------------------------------
    def test_categories_are_seeded_and_count_published_posts(self):
        first = self._post(category_slug="emotional-support")
        self.assertEqual(first.status_code, 201)
        self.assertEqual(first.data["category_slug"], "emotional-support")
        self.assertEqual(first.data["forum_category"]["slug"], "emotional-support")
        self.assertEqual(first.data["category"], "SUPPORT")
        self._post(client=self.other_client, category="GENERAL")
        resp = self.patient_client.get("/api/community/categories/")
        self.assertEqual(resp.status_code, 200)
        rows = {row["slug"]: row for row in resp.data["results"]}
        self.assertEqual(len(rows), 7)
        self.assertEqual(rows["emotional-support"]["post_count"], 1)
        self.assertEqual(rows["community-voices"]["post_count"], 1)
        self.assertEqual(rows["community-voices"]["legacy_code"], "GENERAL")

    def test_category_filter_and_validation(self):
        self._post(category_slug="pain-and-crises")
        self._post(client=self.other_client, category_slug="daily-living")
        resp = self.patient_client.get("/api/community/posts/?category=pain-and-crises")
        self.assertEqual(resp.data["count"], 1)
        bad = self.patient_client.get("/api/community/posts/?category=not-real")
        self.assertEqual(bad.status_code, 400)
        bad_create = self._post(category_slug="not-real")
        self.assertEqual(bad_create.status_code, 400)

    def test_search_sort_and_pinned_first(self):
        a = self._post(title="Zebra pain tips").data["uid"]
        b = self._post(client=self.other_client, title="Alpha care tips").data["uid"]
        pinned = self.moderator_client.post(
            f"/api/community/posts/{a}/pin/", {"is_pinned": True}, format="json",
        )
        self.assertEqual(pinned.status_code, 200)
        self.assertTrue(pinned.data["is_pinned"])
        newest = self.patient_client.get("/api/community/posts/?sort=newest")
        self.assertEqual(newest.data["results"][0]["uid"], a)
        search = self.patient_client.get("/api/community/posts/?search=Alpha")
        self.assertEqual(search.data["count"], 1)
        self.assertEqual(search.data["results"][0]["uid"], b)
        authored = self.patient_client.get("/api/community/posts/?author=me")
        self.assertEqual(authored.data["count"], 1)

    def test_post_list_pagination_and_category_filter(self):
        category = ForumCategory.objects.get(slug="community-voices")
        for index in range(25):
            CommunityPost.objects.create(
                author=self.patient,
                title=f"Paged post {index}",
                content="Body",
                category="GENERAL",
                forum_category=category,
                status="PUBLISHED",
            )
        first = self.patient_client.get("/api/community/posts/?page_size=10")
        self.assertEqual(first.status_code, 200)
        self.assertEqual(first.data["count"], 25)
        self.assertEqual(len(first.data["results"]), 10)
        self.assertIsNotNone(first.data["next"])
        second = self.patient_client.get("/api/community/posts/?page_size=10&page=2")
        self.assertEqual(len(second.data["results"]), 10)
        third = self.patient_client.get("/api/community/posts/?page_size=10&page=3")
        self.assertEqual(len(third.data["results"]), 5)
        self.assertIsNone(third.data["next"])
        filtered = self.patient_client.get(
            "/api/community/posts/?category=community-voices",
        )
        self.assertEqual(filtered.data["count"], 25)

    def test_comment_notifications_skip_self_and_are_deduplicated(self):
        from notifications.models import Notification

        from community import services

        uid = self._post().data["uid"]
        post = CommunityPost.objects.get(uid=uid)
        self._comment(uid, client=self.patient_client, content="My own update")
        self.assertFalse(self.patient.notifications.filter(type="COMMUNITY").exists())
        comment = post.comments.first()
        delivery_key = f"community:comment:{comment.pk}:{self.other.pk}"
        for _ in range(2):
            services._notify_recipient(
                recipient=self.other,
                post=post,
                title="New activity",
                body="Open the forum.",
                delivery_key=delivery_key,
                forum_type="POST_ACTIVITY",
                comment=comment,
            )
        self.assertEqual(
            Notification.objects.filter(
                recipient=self.other, delivery_key=delivery_key,
            ).count(),
            1,
        )

    def test_pin_and_lock_require_moderator(self):
        uid = self._post().data["uid"]
        denied = self.patient_client.post(
            f"/api/community/posts/{uid}/pin/", {"is_pinned": True}, format="json",
        )
        self.assertEqual(denied.status_code, 403)
        locked = self.moderator_client.post(
            f"/api/community/posts/{uid}/lock/", {"is_locked": True}, format="json",
        )
        self.assertEqual(locked.status_code, 200)
        self.assertTrue(locked.data["is_locked"])
        blocked = self._comment(uid)
        self.assertEqual(blocked.status_code, 400)
        unlocked = self.moderator_client.post(
            f"/api/community/posts/{uid}/lock/", {"is_locked": False}, format="json",
        )
        self.assertEqual(unlocked.status_code, 200)
        self.assertEqual(self._comment(uid).status_code, 201)

    def test_edit_flags_post_and_comment(self):
        uid = self._post().data["uid"]
        edited = self.patient_client.patch(
            f"/api/community/posts/{uid}/", {"content": "Edited body"}, format="json",
        )
        self.assertEqual(edited.status_code, 200)
        self.assertTrue(edited.data["is_edited"])
        comment = self._comment(uid).data
        updated = self.other_client.patch(
            f"/api/community/posts/{uid}/comments/{comment['id']}/",
            {"content": "Edited comment"}, format="json",
        )
        self.assertEqual(updated.status_code, 200)
        self.assertTrue(updated.data["is_edited"])

    # --- threading -----------------------------------------------------------
    def test_reply_threading_and_notifications(self):
        uid = self._post().data["uid"]
        root = self._comment(uid).data
        reply = self._comment(uid, client=self.doctor_client, content="A reply", parent_id=root["id"])
        self.assertEqual(reply.status_code, 201)
        self.assertEqual(reply.data["parent_id"], root["id"])
        self.assertEqual(reply.data["depth"], 2)
        listing = self.patient_client.get(f"/api/community/posts/{uid}/comments/")
        self.assertEqual(listing.data["count"], 2)
        self.assertEqual(listing.data["results"][0]["reply_count"], 1)
        # Post author is notified for both; root author additionally gets the reply.
        self.assertTrue(
            self.patient.notifications.filter(type="COMMUNITY", title="New reply to your post").exists()
        )
        self.assertTrue(
            self.other.notifications.filter(type="COMMUNITY", title="New reply to your comment").exists()
        )
        note = self.other.notifications.filter(type="COMMUNITY").first()
        self.assertEqual(note.related_resource_type, "community_post")
        self.assertEqual(note.related_resource_id, uid)
        self.assertEqual(note.data["route"], "community")
        self.assertEqual(note.data["post_uid"], uid)
        self.assertEqual(note.data["comment_id"], reply.data["id"])

    def test_reply_depth_limit(self):
        uid = self._post().data["uid"]
        root = self._comment(uid).data
        parent_id = root["id"]
        for depth in range(2, 6):
            resp = self._comment(uid, client=self.doctor_client, content=f"d{depth}", parent_id=parent_id)
            self.assertEqual(resp.status_code, 201)
            parent_id = resp.data["id"]
            self.assertEqual(resp.data["depth"], depth)
        blocked = self._comment(uid, client=self.doctor_client, content="too deep", parent_id=parent_id)
        self.assertEqual(blocked.status_code, 400)
        self.assertIn("depth", str(blocked.data))

    def test_reply_to_missing_or_other_post_parent_rejected(self):
        uid = self._post().data["uid"]
        uid2 = self._post(client=self.other_client).data["uid"]
        foreign = self._comment(uid2, content="elsewhere").data
        resp = self._comment(uid, parent_id=foreign["id"])
        self.assertEqual(resp.status_code, 400)
        missing = self._comment(uid, parent_id=999999)
        self.assertEqual(missing.status_code, 400)

    def test_deleted_parent_is_a_content_free_tombstone_when_replies_exist(self):
        uid = self._post().data["uid"]
        root = self._comment(uid).data
        self._comment(uid, client=self.doctor_client, parent_id=root["id"], content="still here")
        deleted = self.other_client.delete(
            f"/api/community/posts/{uid}/comments/{root['id']}/",
        )
        self.assertEqual(deleted.status_code, 204)
        listing = self.patient_client.get(f"/api/community/posts/{uid}/comments/")
        rows = {row["id"]: row for row in listing.data["results"]}
        self.assertIn(root["id"], rows)
        self.assertTrue(rows[root["id"]]["is_deleted"])
        self.assertEqual(rows[root["id"]]["content"], "")

    def test_comment_delete_ownership(self):
        uid = self._post().data["uid"]
        comment = self._comment(uid).data
        denied = self.patient_client.delete(
            f"/api/community/posts/{uid}/comments/{comment['id']}/",
        )
        self.assertEqual(denied.status_code, 403)
        ok = self.other_client.delete(
            f"/api/community/posts/{uid}/comments/{comment['id']}/",
        )
        self.assertEqual(ok.status_code, 204)
        # A childless tombstone is hidden from other members, but its author
        # can still see that the comment was removed (without content).
        own = self.other_client.get(f"/api/community/posts/{uid}/comments/")
        self.assertEqual(own.data["count"], 1)
        self.assertTrue(own.data["results"][0]["is_deleted"])
        self.assertEqual(own.data["results"][0]["content"], "")
        hidden = self.patient_client.get(f"/api/community/posts/{uid}/comments/")
        self.assertEqual(hidden.data["count"], 0)

    # --- scoped notifications ------------------------------------------------
    def test_forum_notifications_are_scoped_and_read_flow(self):
        uid = self._post().data["uid"]
        from notifications.models import Notification

        Notification.objects.create(
            recipient=self.patient, type="SYSTEM", title="System note", body="ignore me",
        )
        self._comment(uid)
        self._comment(uid, client=self.doctor_client, content="second")
        notes = self.patient_client.get("/api/community/notifications/")
        self.assertEqual(notes.status_code, 200)
        self.assertEqual(notes.data["count"], 2)
        self.assertTrue(all(row["type"] == "COMMUNITY" for row in notes.data["results"]))
        count = self.patient_client.get("/api/community/notifications/unread-count/")
        self.assertEqual(count.data["unread"], 2)
        first_id = notes.data["results"][0]["id"]
        read = self.patient_client.post(f"/api/community/notifications/{first_id}/read/")
        self.assertEqual(read.status_code, 200)
        self.assertEqual(read.data["status"], "READ")
        self.assertEqual(
            self.patient_client.get("/api/community/notifications/unread-count/").data["unread"], 1,
        )
        all_read = self.patient_client.post("/api/community/notifications/read-all/")
        self.assertEqual(all_read.status_code, 200)
        self.assertEqual(all_read.data["updated"], 1)
        self.assertEqual(
            self.patient_client.get("/api/community/notifications/unread-count/").data["unread"], 0,
        )
        self.assertTrue(
            Notification.objects.filter(recipient=self.patient, type="SYSTEM", status="PENDING").exists()
        )

    def test_forum_notifications_cannot_read_other_users_rows(self):
        uid = self._post().data["uid"]
        self._comment(uid)
        note = self.patient.notifications.filter(type="COMMUNITY").first()
        resp = self.other_client.post(f"/api/community/notifications/{note.pk}/read/")
        self.assertEqual(resp.status_code, 404)
