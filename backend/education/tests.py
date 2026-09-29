"""Backend tests for the Stage 4.11 education API.

Run::

    venv/bin/python manage.py test education --settings=config.settings.ephemeral_test

Covers: public read surface (published only, drafts locked), sanitisation,
author-only edit/delete (IDOR), the review workflow (DRAFT -> IN_REVIEW ->
PUBLISHED/REJECTED, C12), admin review permission (education.review),
search/category filters, pagination, audit rows, write throttling, and the
data boundary (no author email/PHI leakage).
"""

import uuid as _uuid

from django.core.cache import cache
from django.test import TestCase
from rest_framework.test import APIClient
from rest_framework_simplejwt.tokens import RefreshToken

from accounts.models import Role, User, UserRole
from audit.models import AuditLog
from education.models import EducationCategory, EducationalContent

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


def _content(author, category=None, status="PUBLISHED", title="How sickle cell works", **extra):
    return EducationalContent.objects.create(
        author=author,
        category=category or EducationCategory.objects.get(code="SICKLE_BASICS"),
        title=title,
        body="Educational body.",
        status=status,
        **extra,
    )


class EducationApiTests(TestCase):
    @classmethod
    def setUpTestData(cls):
        cls.category = EducationCategory.objects.get(code="NUTRITION")

    def setUp(self):
        cache.clear()
        self.patient = _orm_user("PATIENT")
        self.doctor = _orm_user("DOCTOR")
        self.admin = _orm_user("ADMIN")
        self.patient_client = _client(self.patient)
        self.doctor_client = _client(self.doctor)
        self.admin_client = _client(self.admin)

    # --- public read surface -------------------------------------------------
    def test_categories_are_public(self):
        anon = APIClient().get("/api/education/categories/")
        self.assertEqual(anon.status_code, 200)
        codes = [c["code"] for c in anon.data["results"]]
        self.assertEqual(codes, ["SICKLE_BASICS", "CRISIS_PREVENTION", "NUTRITION", "EXERCISE",
                                 "CAREERS_FAMILY", "LIVING_WELL"])

    def test_public_feed_shows_published_only(self):
        _content(self.doctor)
        _content(self.doctor, status="DRAFT")
        anon = APIClient().get("/api/education/content/")
        self.assertEqual(anon.status_code, 200)
        self.assertEqual(anon.data["count"], 1)
        # Draft is locked from a non-author member too.
        member = self.patient_client.get("/api/education/content/")
        self.assertEqual(member.data["count"], 1)

    def test_draft_locked_from_non_author(self):
        draft = _content(self.doctor, status="DRAFT")
        other = self.patient_client.get(f"/api/education/content/{draft.uid}/")
        self.assertEqual(other.status_code, 404)
        mine = self.doctor_client.get(f"/api/education/content/{draft.uid}/")
        self.assertEqual(mine.status_code, 200)
        anon = APIClient().get(f"/api/education/content/{draft.uid}/")
        self.assertEqual(anon.status_code, 404)

    def test_author_projection_hides_private_fields(self):
        content = _content(self.doctor, title="Public title")
        resp = self.patient_client.get(f"/api/education/content/{content.uid}/")
        self.assertEqual(resp.status_code, 200)
        self.assertEqual(set(resp.data["author"].keys()), {"uid", "display_name"})
        self.assertNotIn("email", resp.data)
        self.assertNotIn("reviewed_by", resp.data)
        self.assertNotIn("rejection_reason", resp.data)
        self.assertEqual(resp.data["status"], "PUBLISHED")

    def test_search_and_category_filter(self):
        _content(self.doctor, title="Diet for warriors", category=EducationCategory.objects.get(code="NUTRITION"))
        _content(self.doctor, title="Safe exercise routine", category=EducationCategory.objects.get(code="EXERCISE"))
        q = self.patient_client.get("/api/education/content/?q=diet")
        self.assertEqual(q.data["count"], 1)
        s = self.patient_client.get("/api/education/content/?search=exercise")
        self.assertEqual(s.data["count"], 1)
        cat = self.patient_client.get("/api/education/content/?category=EXERCISE")
        self.assertEqual(cat.data["count"], 1)
        bad = self.patient_client.get("/api/education/content/?category=NOPE")
        self.assertEqual(bad.status_code, 400)

    # --- authoring / write surface ------------------------------------------
    def test_create_requires_publish_permission(self):
        denied = self.patient_client.post(
            "/api/education/content/",
            {"title": "Draft", "body": "Body", "category": "NUTRITION"},
            format="json",
        )
        self.assertEqual(denied.status_code, 403)
        created = self.doctor_client.post(
            "/api/education/content/",
            {"title": "Draft", "body": "Body", "category": "NUTRITION"},
            format="json",
        )
        self.assertEqual(created.status_code, 201)
        self.assertEqual(created.data["status"], "DRAFT")
        self.assertTrue(created.data["is_author"])
        self.assertTrue(
            AuditLog.objects.filter(action_code="education.content.create").exists()
        )

    def test_create_sanitizes_html(self):
        created = self.doctor_client.post(
            "/api/education/content/",
            {"title": "<script>alert(1)</script>Title", "body": "Hello <b>world</b>", "category": "NUTRITION"},
            format="json",
        )
        self.assertEqual(created.status_code, 201)
        self.assertNotIn("<script", created.data["title"])
        self.assertIn("<b>world</b>", created.data["body"])

    def test_create_unknown_category_rejected(self):
        resp = self.doctor_client.post(
            "/api/education/content/",
            {"title": "x", "body": "y", "category": "NOPE"},
            format="json",
        )
        self.assertEqual(resp.status_code, 400)

    def test_edit_delete_ownership(self):
        draft = _content(self.doctor, status="DRAFT")
        hijack = self.patient_client.patch(
            f"/api/education/content/{draft.uid}/", {"body": "hijacked"}, format="json",
        )
        self.assertEqual(hijack.status_code, 403)
        ok = self.doctor_client.patch(
            f"/api/education/content/{draft.uid}/", {"body": "edited"}, format="json",
        )
        self.assertEqual(ok.status_code, 200)
        self.assertEqual(ok.data["body"], "edited")
        deleted = self.doctor_client.delete(f"/api/education/content/{draft.uid}/")
        self.assertEqual(deleted.status_code, 204)
        self.assertFalse(EducationalContent.objects.filter(uid=draft.uid).exists())

    def test_edit_locked_once_published(self):
        published = _content(self.doctor)
        resp = self.doctor_client.patch(
            f"/api/education/content/{published.uid}/", {"body": "x"}, format="json",
        )
        self.assertEqual(resp.status_code, 400)
        resp = self.doctor_client.delete(f"/api/education/content/{published.uid}/")
        self.assertEqual(resp.status_code, 400)

    # --- review workflow (C12) ----------------------------------------------
    def test_submit_and_admin_review_flow(self):
        draft = _content(self.doctor, status="DRAFT")
        uid = str(draft.uid)
        # Only the author can submit.
        other_submit = self.patient_client.post(f"/api/education/content/{uid}/submit/")
        self.assertEqual(other_submit.status_code, 403)
        submitted = self.doctor_client.post(f"/api/education/content/{uid}/submit/")
        self.assertEqual(submitted.status_code, 200)
        self.assertEqual(submitted.data["status"], "IN_REVIEW")
        self.assertTrue(
            AuditLog.objects.filter(action_code="education.content.submit").exists()
        )
        # Non-review roles cannot approve.
        denied = self.doctor_client.post(
            f"/api/admin/education/content/{uid}/review/",
            {"decision": "approve"},
            format="json",
        )
        self.assertEqual(denied.status_code, 403)
        approved = self.admin_client.post(
            f"/api/admin/education/content/{uid}/review/",
            {"decision": "approve"},
            format="json",
        )
        self.assertEqual(approved.status_code, 200)
        draft.refresh_from_db()
        self.assertEqual(draft.status, "PUBLISHED")
        self.assertIsNotNone(draft.published_at)
        self.assertEqual(draft.reviewed_by_id, self.admin.pk)
        self.assertTrue(
            AuditLog.objects.filter(action_code="education.content.review").exists()
        )

    def test_submit_from_published_rejected(self):
        published = _content(self.doctor)
        resp = self.doctor_client.post(f"/api/education/content/{published.uid}/submit/")
        self.assertEqual(resp.status_code, 400)

    def test_reject_requires_reason_and_allows_resubmission(self):
        draft = _content(self.doctor, status="DRAFT")
        uid = str(draft.uid)
        self.doctor_client.post(f"/api/education/content/{uid}/submit/")
        no_reason = self.admin_client.post(
            f"/api/admin/education/content/{uid}/review/",
            {"decision": "reject"},
            format="json",
        )
        self.assertEqual(no_reason.status_code, 400)
        rejected = self.admin_client.post(
            f"/api/admin/education/content/{uid}/review/",
            {"decision": "reject", "reason": "Needs citations"},
            format="json",
        )
        self.assertEqual(rejected.status_code, 200)
        draft.refresh_from_db()
        self.assertEqual(draft.status, "REJECTED")
        self.assertEqual(draft.rejection_reason, "Needs citations")
        # Author revises and resubmits.
        self.doctor_client.patch(f"/api/education/content/{uid}/", {"body": "revised"})
        resubmit = self.doctor_client.post(f"/api/education/content/{uid}/submit/")
        self.assertEqual(resubmit.status_code, 200)
        self.assertEqual(resubmit.data["status"], "IN_REVIEW")

    def test_review_only_for_pending_content(self):
        published = _content(self.doctor)
        resp = self.admin_client.post(
            f"/api/admin/education/content/{published.uid}/review/",
            {"decision": "approve"},
            format="json",
        )
        self.assertEqual(resp.status_code, 400)

    def test_admin_list_shows_all_statuses(self):
        _content(self.doctor)
        _content(self.doctor, status="DRAFT")
        _content(self.doctor, status="IN_REVIEW")
        denied = self.patient_client.get("/api/admin/education/content/")
        self.assertEqual(denied.status_code, 403)
        listing = self.admin_client.get("/api/admin/education/content/")
        self.assertEqual(listing.status_code, 200)
        self.assertEqual(listing.data["count"], 3)
        pending = self.admin_client.get("/api/admin/education/content/?status=IN_REVIEW")
        self.assertEqual(pending.data["count"], 1)

    # --- abuse / audit -------------------------------------------------------
    def test_write_throttle_429(self):
        for i in range(30):
            self.doctor_client.post(
                "/api/education/content/",
                {"title": f"t{i}", "body": "b", "category": "NUTRITION"},
                format="json",
            )
        blocked = self.doctor_client.post(
            "/api/education/content/",
            {"title": "x", "body": "y", "category": "NUTRITION"},
            format="json",
        )
        self.assertEqual(blocked.status_code, 429)

    def test_verification_officer_cannot_publish(self):
        vo = _orm_user("VERIFICATION_OFFICER")
        resp = _client(vo).post(
            "/api/education/content/",
            {"title": "x", "body": "y", "category": "NUTRITION"},
            format="json",
        )
        self.assertEqual(resp.status_code, 403)

    # --- admin CMS (create/edit/delete/publish) -----------------------------
    def test_admin_create_and_publish_draft(self):
        draft = self.admin_client.post(
            "/api/admin/education/content/",
            {"title": "Admin first aid", "body": "<p>Instructions</p>", "category": "SICKLE_BASICS"},
            format="json",
        )
        self.assertEqual(draft.status_code, 201)
        self.assertEqual(draft.data["status"], "DRAFT")
        uid = draft.data["uid"]
        # A draft is not visible on the public library yet.
        anon = APIClient().get("/api/education/content/")
        self.assertNotIn(uid, [r["uid"] for r in anon.data["results"]])
        # One-step admin publish takes it live.
        published = self.admin_client.post(f"/api/admin/education/content/{uid}/publish/")
        self.assertEqual(published.status_code, 200)
        self.assertEqual(published.data["status"], "PUBLISHED")
        self.assertIsNotNone(published.data["published_at"])
        anon = APIClient().get("/api/education/content/")
        self.assertIn(uid, [r["uid"] for r in anon.data["results"]])
        # Publishing again is rejected.
        again = self.admin_client.post(f"/api/admin/education/content/{uid}/publish/")
        self.assertEqual(again.status_code, 400)
        # Audit trails the admin write.
        self.assertTrue(
            AuditLog.objects.filter(
                action_code="education.content.publish",
                resource_type="educational_content",
                resource_id=EducationalContent.objects.get(uid=uid).pk,
            ).exists(),
        )

    def test_admin_edit_and_delete_draft(self):
        created = self.admin_client.post(
            "/api/admin/education/content/",
            {"title": "Draft to edit", "body": "b", "category": "NUTRITION"},
            format="json",
        )
        uid = created.data["uid"]
        updated = self.admin_client.patch(
            f"/api/admin/education/content/{uid}/",
            {"title": "Edited title", "body": "updated"},
            format="json",
        )
        self.assertEqual(updated.status_code, 200)
        self.assertEqual(updated.data["title"], "Edited title")
        # Editing a published item is rejected.
        published = self.admin_client.post(f"/api/admin/education/content/{uid}/publish/")
        self.assertEqual(published.data["status"], "PUBLISHED")
        locked = self.admin_client.patch(
            f"/api/admin/education/content/{uid}/", {"title": "nope"}, format="json",
        )
        self.assertEqual(locked.status_code, 400)
        # Only never-published drafts can be deleted.
        self.assertEqual(self.admin_client.delete(f"/api/admin/education/content/{uid}/").status_code, 400)
        deleted_draft = self.admin_client.post(
            "/api/admin/education/content/",
            {"title": "Doomed", "body": "b", "category": "NUTRITION"},
            format="json",
        )
        uid2 = deleted_draft.data["uid"]
        self.assertEqual(self.admin_client.delete(f"/api/admin/education/content/{uid2}/").status_code, 204)

    def test_admin_cms_gated_to_reviewers(self):
        # A DOCTOR (education.publish but no education.review) cannot use the
        # admin CMS surface; only SUPER_ADMIN/ADMIN reviewers may.
        denied = self.doctor_client.post(
            "/api/admin/education/content/",
            {"title": "x", "body": "y", "category": "NUTRITION"},
            format="json",
        )
        self.assertEqual(denied.status_code, 403)