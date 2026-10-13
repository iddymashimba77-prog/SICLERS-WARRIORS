"""Backend tests for the Stage 4.11 education API.

Run::

    venv/bin/python manage.py test education --settings=config.settings.ephemeral_test

Covers: public read surface (published only, drafts locked), sanitisation,
author-only edit/delete (IDOR), the review workflow (DRAFT -> IN_REVIEW ->
PUBLISHED/REJECTED, C12), admin review permission (education.review),
search/category filters, pagination, audit rows, write throttling, and the
data boundary (no author email/PHI leakage).
"""

import io
import os
import shutil
import tempfile
import uuid as _uuid

from django.core.cache import cache
from django.core.files.uploadedfile import SimpleUploadedFile
from django.test import TestCase, override_settings
from django.utils import timezone
from PIL import Image
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
        super().setUp()
        cache.clear()
        # Keep any upload in this class off the real media directory.
        media_root = tempfile.mkdtemp(prefix="sw-edu-test-")
        media_settings = override_settings(MEDIA_ROOT=media_root)
        media_settings.enable()
        self.addCleanup(media_settings.disable)
        self.addCleanup(shutil.rmtree, media_root, True)

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

    def test_admin_editor_can_attach_a_document_to_any_draft(self):
        """The CMS is an editorial surface: an editor works on anyone's draft."""
        draft = _content(self.doctor, status="DRAFT", title="Doctor's draft")
        res = self.admin_client.post(
            f"/api/admin/education/content/{draft.uid}/document/",
            {"document": _upload("cms.pdf")}, format="multipart",
        )
        self.assertEqual(res.status_code, 200, res.data)
        draft.refresh_from_db()
        self.assertEqual(draft.document_name, "cms.pdf")
        # The admin projection carries the review fields and the attachment.
        self.assertEqual(res.data["document_name"], "cms.pdf")
        self.assertIn("reviewed_by", res.data)

    def test_admin_cms_document_still_refuses_published_content(self):
        published = _content(self.doctor, status="PUBLISHED", title="Live")
        res = self.admin_client.post(
            f"/api/admin/education/content/{published.uid}/document/",
            {"document": _upload()}, format="multipart",
        )
        self.assertEqual(res.status_code, 400)

    def test_admin_cms_document_needs_the_review_gate(self):
        draft = _content(self.doctor, status="DRAFT", title="Not mine to edit")
        res = self.doctor_client.post(
            f"/api/admin/education/content/{draft.uid}/document/",
            {"document": _upload()}, format="multipart",
        )
        self.assertEqual(res.status_code, 403)

    def test_author_workspace_lists_own_content_of_any_status(self):
        """``?mine=1`` is what a doctor's "My articles" screen reads."""
        _content(self.doctor, status="DRAFT", title="Mine draft")
        _content(self.doctor, status="IN_REVIEW", title="Mine pending")
        _content(self.patient, status="DRAFT", title="Someone else's draft")
        res = self.doctor_client.get("/api/education/content/?mine=1")
        self.assertEqual(res.status_code, 200)
        titles = {r["title"] for r in res.data["results"]}
        self.assertEqual(titles, {"Mine draft", "Mine pending"})

    def test_author_workspace_is_scoped_to_the_caller(self):
        """One doctor must never see another doctor's drafts."""
        _content(self.patient, status="DRAFT", title="Patient draft")
        res = self.doctor_client.get("/api/education/content/?mine=1")
        self.assertEqual(res.data["count"], 0)

    def test_author_workspace_needs_authentication(self):
        self.assertEqual(
            APIClient().get("/api/education/content/?mine=1").status_code, 401
        )

    def test_author_workspace_carries_document_metadata(self):
        """The management surface needs the handout; the public feed does not."""
        draft = _content(self.doctor, status="DRAFT", title="With a handout")
        self.doctor_client.post(
            f"/api/education/content/{draft.uid}/document/",
            {"document": _upload()}, format="multipart",
        )
        row = self.doctor_client.get("/api/education/content/?mine=1").data["results"][0]
        self.assertEqual(row["document_name"], "handout.pdf")
        self.assertIn("/media/education/", row["document_url"])

    def test_public_feed_stays_published_only_when_mine_is_absent(self):
        """Adding ?mine must not have loosened the default public query."""
        _content(self.doctor, status="DRAFT", title="Mine draft")
        anon = APIClient().get("/api/education/content/")
        self.assertEqual(anon.data["count"], 0)
        _content(self.doctor, status="PUBLISHED", title="Public")
        anon = APIClient().get("/api/education/content/")
        self.assertEqual(anon.data["count"], 1)

    def test_author_workspace_rejects_an_unknown_status_filter(self):
        self.assertEqual(
            self.doctor_client.get("/api/education/content/?mine=1&status=NOPE").status_code,
            400,
        )

    def test_admin_cms_gated_to_reviewers(self):
        # A DOCTOR (education.publish but no education.review) cannot use the
        # admin CMS surface; only SUPER_ADMIN/ADMIN reviewers may.
        denied = self.doctor_client.post(
            "/api/admin/education/content/",
            {"title": "x", "body": "y", "category": "NUTRITION"},
            format="json",
        )
        self.assertEqual(denied.status_code, 403)

# ---------------------------------------------------------------------------
# Document attachments (FR-EDU-005: printable handout / slide deck download)
# ---------------------------------------------------------------------------

def _png_bytes(size=(8, 8), color=(200, 16, 46)):
    buf = io.BytesIO()
    Image.new("RGB", size, color).save(buf, format="PNG")
    return buf.getvalue()


_PDF_BYTES = b"%PDF-1.7\n1 0 obj<</Type/Catalog>>endobj\ntrailer<<>>\n%%EOF\n"


def _upload(name="handout.pdf", content_type="application/pdf", data=_PDF_BYTES):
    return SimpleUploadedFile(name, data, content_type=content_type)


class EducationDocumentUploadTests(TestCase):
    """Author-only attachment with server-side type/size/magic validation.

    Documents live under a per-run ``MEDIA_ROOT`` so the suite never writes
    into the real media directory and can assert on orphaned files.
    """

    def setUp(self):
        super().setUp()
        cache.clear()
        self._media_root = tempfile.mkdtemp(prefix="sw-edu-test-")
        self._settings = override_settings(MEDIA_ROOT=self._media_root)
        self._settings.enable()
        self.addCleanup(self._settings.disable)
        self.addCleanup(shutil.rmtree, self._media_root, True)

        self.doctor = _orm_user("DOCTOR")
        self.other_doctor = _orm_user("DOCTOR")
        self.admin = _orm_user("ADMIN")
        self.doctor_client = _client(self.doctor)
        self.other_client = _client(self.other_doctor)
        self.admin_client = _client(self.admin)
        self.draft = _content(self.doctor, status="DRAFT", title="Draft with handout")

    def _url(self, content=None):
        content = content or self.draft
        return f"/api/education/content/{content.uid}/document/"

    def _post(self, uploaded, content=None):
        return self.doctor_client.post(
            self._url(content), {"document": uploaded}, format="multipart",
        )

    def _stored(self, name) -> bool:
        """True when ``name`` still exists in the active storage backend."""
        from django.core.files.storage import default_storage

        if not name:
            return False
        return default_storage.exists(name)

    # --- happy path ----------------------------------------------------------
    def test_author_can_attach_a_pdf_to_a_draft(self):
        res = self._post(_upload())
        self.assertEqual(res.status_code, 200, res.data)
        self.draft.refresh_from_db()
        self.assertTrue(self.draft.document_file)
        self.assertEqual(self.draft.document_content_type, "application/pdf")
        self.assertEqual(self.draft.document_name, "handout.pdf")
        self.assertEqual(self.draft.document_size, len(_PDF_BYTES))
        self.assertEqual(self.draft.document_uploaded_by, self.doctor)
        self.assertIsNotNone(self.draft.document_uploaded_at)
        self.assertTrue(res.data["document_url"].startswith("http://testserver/media/"))

    def test_pptx_is_accepted_even_when_the_browser_sends_octet_stream(self):
        """Mobile pickers often report application/octet-stream for a deck."""
        zipped = b"PK\x03\x04rest-of-the-ooxml-package"
        res = self._post(_upload("session.pptx", "application/octet-stream", zipped))
        self.assertEqual(res.status_code, 200, res.data)
        self.draft.refresh_from_db()
        self.assertEqual(
            self.draft.document_content_type,
            "application/vnd.openxmlformats-officedocument.presentationml.presentation",
        )

    def test_docx_is_accepted(self):
        res = self._post(_upload("notes.docx", "application/octet-stream", b"PK\x03\x04body"))
        self.assertEqual(res.status_code, 200, res.data)

    def test_image_handout_is_accepted(self):
        """A photo of a clinic poster is a legitimate handout."""
        res = self._post(_upload("poster.png", "image/png", _png_bytes()))
        self.assertEqual(res.status_code, 200, res.data)
        self.draft.refresh_from_db()
        self.assertEqual(self.draft.document_content_type, "image/png")

    def test_document_is_replaced_and_the_old_file_deleted(self):
        self.assertEqual(self._post(_upload("first.pdf")).status_code, 200)
        self.draft.refresh_from_db()
        first = self.draft.document_file.name
        self.assertTrue(self._stored(first))

        self.assertEqual(self._post(_upload("second.pdf")).status_code, 200)
        self.draft.refresh_from_db()
        self.assertNotEqual(self.draft.document_file.name, first)
        self.assertEqual(self.draft.document_name, "second.pdf")
        self.assertTrue(self._stored(self.draft.document_file.name))
        # No orphan is left behind when the attachment is swapped.
        self.assertFalse(self._stored(first))

    def test_author_can_remove_the_document(self):
        self._post(_upload())
        self.draft.refresh_from_db()
        name = self.draft.document_file.name

        res = self.doctor_client.delete(self._url())
        self.assertEqual(res.status_code, 200, res.data)
        self.draft.refresh_from_db()
        self.assertFalse(self.draft.document_file)
        self.assertEqual(self.draft.document_name, "")
        self.assertIsNone(self.draft.document_size)
        self.assertIsNone(res.data["document_url"])
        self.assertFalse(self._stored(name))

    def test_removing_when_nothing_is_attached_is_a_400(self):
        res = self.doctor_client.delete(self._url())
        self.assertEqual(res.status_code, 400)

    # --- validation ----------------------------------------------------------
    def test_executable_is_refused_by_declared_type(self):
        res = self._post(_upload("payload.exe", "application/x-msdownload", b"MZ\x90\x00"))
        self.assertEqual(res.status_code, 400)
        self.assertIn("document", res.data["error"]["details"])
        self.draft.refresh_from_db()
        self.assertFalse(self.draft.document_file)

    def test_spoofed_extension_is_refused_by_magic_bytes(self):
        """A .pdf name with script bytes is rejected — bytes decide, not the name."""
        res = self._post(_upload("notes.pdf", "application/pdf", b"<?php echo 1; ?>"))
        self.assertEqual(res.status_code, 400)
        self.draft.refresh_from_db()
        self.assertFalse(self.draft.document_file)

    def test_a_valid_pdf_may_never_carry_a_script_extension(self):
        """Real PDF bytes under a .exe name is the classic double-extension.

        The bytes are harmless, but the *name* is what the browser saves and
        what a patient is shown — so the extension has to match the real type.
        """
        res = self._post(_upload("handout.pdf.exe", "application/pdf", _PDF_BYTES))
        self.assertEqual(res.status_code, 400)
        self.draft.refresh_from_db()
        self.assertFalse(self.draft.document_file)

    def test_path_traversal_in_the_filename_is_stripped(self):
        res = self._post(_upload("../../etc/passwd.pdf", "application/pdf", _PDF_BYTES))
        self.assertEqual(res.status_code, 200, res.data)
        self.draft.refresh_from_db()
        self.assertEqual(self.draft.document_name, "passwd.pdf")
        self.assertNotIn("..", self.draft.document_file.name)

    def test_oversized_document_is_refused(self):
        from education.services import DOCUMENT_MAX_BYTES

        huge = _upload("big.pdf", "application/pdf", b"%PDF-1.7" + b"0" * DOCUMENT_MAX_BYTES)
        res = self._post(huge)
        self.assertEqual(res.status_code, 400)
        self.draft.refresh_from_db()
        self.assertFalse(self.draft.document_file)

    def test_empty_document_is_refused(self):
        res = self._post(_upload("empty.pdf", "application/pdf", b""))
        self.assertEqual(res.status_code, 400)

    def test_missing_file_is_refused(self):
        res = self.doctor_client.post(self._url(), {}, format="multipart")
        self.assertEqual(res.status_code, 400)

    def test_upload_audits_without_the_file_contents(self):
        from audit.models import AuditLog

        self._post(_upload())
        row = AuditLog.objects.filter(action_code="education.content.document_upload").first()
        self.assertIsNotNone(row)
        self.assertEqual(row.details.get("document_name"), "handout.pdf")
        self.assertNotIn("0 obj", str(row.details))

    def test_remove_audits(self):
        from audit.models import AuditLog

        self._post(_upload())
        self.doctor_client.delete(self._url())
        self.assertTrue(
            AuditLog.objects.filter(action_code="education.content.document_remove").exists()
        )

    # --- authorization -------------------------------------------------------
    def test_another_author_cannot_attach_to_someone_elses_draft(self):
        res = self.other_client.post(self._url(), {"document": _upload()}, format="multipart")
        self.assertIn(res.status_code, (403, 404))
        self.draft.refresh_from_db()
        self.assertFalse(self.draft.document_file)

    def test_another_author_cannot_remove_a_document(self):
        self._post(_upload())
        res = self.other_client.delete(self._url())
        self.assertIn(res.status_code, (403, 404))
        self.draft.refresh_from_db()
        self.assertTrue(self.draft.document_file)

    def test_anonymous_upload_is_denied(self):
        res = APIClient().post(self._url(), {"document": _upload()}, format="multipart")
        self.assertIn(res.status_code, (401, 403))

    def test_published_content_cannot_gain_a_document(self):
        """Changing what the public downloads must go through review."""
        published = _content(self.doctor, status="PUBLISHED", title="Live article")
        res = self._post(_upload(), published)
        self.assertEqual(res.status_code, 400)
        published.refresh_from_db()
        self.assertFalse(published.document_file)

    def test_published_content_cannot_lose_a_document(self):
        published = _content(self.doctor, status="DRAFT", title="Going live")
        self._post(_upload(), published)
        published.status = "PUBLISHED"
        published.save(update_fields=["status"])
        res = self.doctor_client.delete(self._url(published))
        self.assertEqual(res.status_code, 400)
        published.refresh_from_db()
        self.assertTrue(published.document_file)

    def test_uploads_share_the_content_write_throttle(self):
        """A file upload must not become a way around the write rate limit."""
        from education.throttles import EducationContentThrottle

        rate = int(EducationContentThrottle.rate.split("/")[0])
        statuses = [self._post(_upload("f.pdf")).status_code for _ in range(rate + 2)]
        self.assertEqual(statuses[0], 200)
        self.assertEqual(statuses[-1], 429)

    # --- public projection ---------------------------------------------------
    def test_published_document_is_visible_to_the_public(self):
        # Attach while it is a draft (the only writable state), then publish it.
        published = _content(self.doctor, status="DRAFT", title="With handout")
        self._post(_upload("public.pdf"), published)
        published.status = "PUBLISHED"
        published.published_at = timezone.now()
        published.save(update_fields=["status", "published_at"])
        anon = APIClient().get(f"/api/education/content/{published.uid}/")
        self.assertEqual(anon.status_code, 200)
        self.assertEqual(anon.data["document_name"], "public.pdf")
        self.assertEqual(anon.data["document_content_type"], "application/pdf")
        self.assertIn("/media/education/", anon.data["document_url"])

    def test_article_without_a_document_reports_null(self):
        published = _content(self.doctor, status="PUBLISHED", title="No handout")
        anon = APIClient().get(f"/api/education/content/{published.uid}/")
        self.assertIsNone(anon.data["document_url"])
        self.assertEqual(anon.data["document_name"], "")

    def test_feed_projection_stays_lean(self):
        """The list endpoint must not carry document metadata for every row."""
        published = _content(self.doctor, status="DRAFT", title="Feed item")
        self._post(_upload(), published)
        published.status = "PUBLISHED"
        published.save(update_fields=["status"])
        anon = APIClient().get("/api/education/content/")
        row = anon.data["results"][0]
        self.assertNotIn("document_url", row)
        self.assertNotIn("document_size", row)
