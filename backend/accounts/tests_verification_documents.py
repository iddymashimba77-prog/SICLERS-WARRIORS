"""C5 verification-pipeline tests (open registration + mandatory documents).

Covers the expanded self-registration (patients/caregivers/blood donors plus
care professionals and facilities) and the document-verification flow:

* register responses carry the correct ``verification_required`` hint;
* the document-upload endpoint accepts real PDFs and re-encoded JPEG scans and
  rejects anything else, requiring authentication;
* doctors/health-professionals and facilities cannot appear in the review queue
  without their mandatory document bundle (education certificate + NIDA for
  professionals; facility registration + NIDA for facilities);
* approved filings land PENDING in their review queue with PENDING documents.
"""

import io

import PIL.Image

from django.test import TestCase, override_settings
from django.core.files.uploadedfile import SimpleUploadedFile

from rest_framework.test import APIClient
from rest_framework_simplejwt.tokens import RefreshToken

from accounts.models import Role, User, UserRole, VerificationDocument
from facilities.models import Facility

_PASSWORD = "Str0ng!Pass9"

_PDF_BYTES = b"%PDF-1.4\n1 0 obj<<>>endobj\ntrailer<<>>\n%%EOF"


def _jpeg_bytes():
    buffer = io.BytesIO()
    PIL.Image.new("RGB", (64, 64), (255, 255, 255)).save(buffer, format="JPEG")
    return buffer.getvalue()


def _register(role, email_suffix="doc"):
    import uuid

    client = APIClient()
    resp = client.post(
        "/api/auth/register/",
        {
            "email": f"{role.lower()}-{email_suffix}-{uuid.uuid4().hex[:8]}@example.com",
            "password": _PASSWORD,
            "first_name": "Test",
            "last_name": role.title(),
            "role_code": role,
        },
        format="json",
    )
    return client, resp


def _upload(client, doc_type, content, content_type, filename):
    return client.post(
        "/api/auth/verification/documents/upload/",
        {
            "doc_type": doc_type,
            "file": SimpleUploadedFile(filename, content, content_type=content_type),
        },
        format="multipart",
    )


class VerificationRegistrationHintTests(TestCase):
    def test_registration_hints_verification_required(self):
        cases = {
            "BLOOD_DONOR": False,
            "PATIENT": False,
            "CAREGIVER": False,
            "DOCTOR": True,
            "PSYCHOLOGIST": True,
            "SOCIAL_SUPPORT": True,
            "HOSPITAL": True,
            "CLINIC": True,
            "ORGANIZATION": True,
        }
        for role, expected in cases.items():
            with self.subTest(role=role):
                _, resp = _register(role, email_suffix="hint")
                self.assertEqual(resp.status_code, 201, resp.data)
                self.assertEqual(resp.data["verification_required"], expected)
                self.assertEqual(resp.data["user"]["role_codes"], [role])

    def test_admin_roles_never_self_registerable(self):
        for role in ("SUPER_ADMIN", "ADMIN", "VERIFICATION_OFFICER", "MODERATOR"):
            with self.subTest(role=role):
                _, resp = _register(role, email_suffix="admin")
                self.assertEqual(resp.status_code, 400)

    def test_clinic_role_exists_and_mirrors_hospital(self):
        """CLINIC exists and its operators hold exactly HOSPITAL's bundle."""
        clinic_role = Role.objects.get(code="CLINIC")
        self.assertEqual(clinic_role.name, "Clinic")
        clinic_user = User.objects.create_user(
            email="clinic-alias@example.com", password=_PASSWORD, first_name="Clinic",
        )
        UserRole.objects.create(user=clinic_user, role=clinic_role)
        hospital_user = User.objects.create_user(
            email="hospital-alias@example.com", password=_PASSWORD, first_name="Hospital",
        )
        UserRole.objects.create(user=hospital_user, role=Role.objects.get(code="HOSPITAL"))
        # Permission-codes equality is the meaningful statement: both labels
        # exercise the same operating surface (grant alias, not a snapshot).
        self.assertEqual(clinic_user.permission_codes(), hospital_user.permission_codes())
        self.assertTrue(clinic_user.has_perm_code("facilities.self_manage"))
        # The alias keeps identity-gated checks working both ways.
        self.assertTrue(clinic_user._has_active_role("CLINIC"))
        self.assertTrue(clinic_user._has_active_role("HOSPITAL"))


@override_settings(EMAIL_BACKEND="django.core.mail.backends.locmem.EmailBackend")
class VerificationDocumentUploadTests(TestCase):
    def test_upload_pdf_returns_storage_key(self):
        _, reg = _register("DOCTOR")
        client = APIClient()
        client.credentials(HTTP_AUTHORIZATION=f"Bearer {reg.data['access']}")
        resp = _upload(
            client, "CERTIFICATE", _PDF_BYTES, "application/pdf", "degree.pdf"
        )
        self.assertEqual(resp.status_code, 201, resp.data)
        self.assertEqual(resp.data["doc_type"], "CERTIFICATE")
        self.assertTrue(resp.data["file_url"].startswith("/media/certification_verification/"))
        self.assertEqual(resp.data["content_type"], "application/pdf")
        doc = VerificationDocument.objects.filter(
            user__email=reg.data["user"]["email"]
        ).first()
        self.assertIsNone(doc, "upload alone must not create a submission row")

    def test_upload_jpeg_scan_is_reencoded(self):
        _, reg = _register("HOSPITAL")
        client = APIClient()
        client.credentials(HTTP_AUTHORIZATION=f"Bearer {reg.data['access']}")
        resp = _upload(
            client, "NATIONAL_ID", _jpeg_bytes(), "image/png", "nida.png"
        )
        self.assertEqual(resp.status_code, 201, resp.data)
        self.assertTrue(resp.data["file_url"].endswith(".jpg"))
        self.assertEqual(resp.data["content_type"], "image/jpeg")

    def test_upload_rejects_non_document(self):
        _, reg = _register("DOCTOR")
        client = APIClient()
        client.credentials(HTTP_AUTHORIZATION=f"Bearer {reg.data['access']}")
        resp = _upload(
            client, "OTHER", b"<html>not a document</html>", "text/html", "evil.html"
        )
        self.assertEqual(resp.status_code, 400)

    def test_upload_rejects_bad_doc_type(self):
        _, reg = _register("DOCTOR")
        client = APIClient()
        client.credentials(HTTP_AUTHORIZATION=f"Bearer {reg.data['access']}")
        resp = _upload(client, "PASSPORT", _PDF_BYTES, "application/pdf", "a.pdf")
        self.assertEqual(resp.status_code, 400)

    def test_upload_requires_authentication(self):
        resp = _upload(
            APIClient(), "CERTIFICATE", _PDF_BYTES, "application/pdf", "a.pdf"
        )
        self.assertIn(resp.status_code, (401, 403))


@override_settings(EMAIL_BACKEND="django.core.mail.backends.locmem.EmailBackend")
class ProfessionalVerificationSubmitTests(TestCase):
    def _doctor_client(self):
        _, reg = _register("DOCTOR")
        client = APIClient()
        client.credentials(HTTP_AUTHORIZATION=f"Bearer {reg.data['access']}")

        def _key(doc_type, upload):
            up = _upload(client, doc_type, *upload)
            self.assertEqual(up.status_code, 201, up.data)
            return up.data["file_url"]

        return client, {
            "cert": _key("CERTIFICATE", (_PDF_BYTES, "application/pdf", "cert.pdf")),
            "id": _key("NATIONAL_ID", (_jpeg_bytes(), "image/jpeg", "nida.jpg")),
        }

    def test_submit_without_id_is_rejected(self):
        client, keys = self._doctor_client()
        resp = client.post(
            "/api/doctors/me/verification/",
            {
                "professional_type": "DOCTOR",
                "documents": [{"doc_type": "CERTIFICATE", "file_url": keys["cert"]}],
            },
            format="json",
        )
        self.assertEqual(resp.status_code, 400)
        self.assertIn("National ID", str(resp.data))

    def test_submit_without_certificate_is_rejected(self):
        client, keys = self._doctor_client()
        resp = client.post(
            "/api/doctors/me/verification/",
            {
                "professional_type": "DOCTOR",
                "documents": [{"doc_type": "NATIONAL_ID", "file_url": keys["id"]}],
            },
            format="json",
        )
        self.assertEqual(resp.status_code, 400)
        self.assertIn("certificate", str(resp.data).lower())

    def test_submit_with_mandatory_bundle_lands_in_review_queue(self):
        client, keys = self._doctor_client()
        resp = client.post(
            "/api/doctors/me/verification/",
            {
                "professional_type": "DOCTOR",
                "documents": [
                    {"doc_type": "CERTIFICATE", "file_url": keys["cert"]},
                    {"doc_type": "NATIONAL_ID", "file_url": keys["id"]},
                ],
            },
            format="json",
        )
        self.assertEqual(resp.status_code, 200, resp.data)
        self.assertEqual(resp.data["verification_status"], "PENDING")
        user = User.objects.get(uid=resp.data["uid"])
        self.assertEqual(
            set(user.verification_documents.values_list("doc_type", flat=True)),
            {"CERTIFICATE", "NATIONAL_ID"},
        )
        self.assertEqual(
            set(user.verification_documents.values_list("status", flat=True)), {"PENDING"}
        )


@override_settings(EMAIL_BACKEND="django.core.mail.backends.locmem.EmailBackend")
class FacilityVerificationSubmitTests(TestCase):
    def _facility_client(self):
        _, reg = _register("HOSPITAL")
        client = APIClient()
        client.credentials(HTTP_AUTHORIZATION=f"Bearer {reg.data['access']}")

        def _key(doc_type, upload):
            up = _upload(client, doc_type, *upload)
            self.assertEqual(up.status_code, 201, up.data)
            return up.data["file_url"]

        return client, {
            "reg": _key("FACILITY_REGISTRATION", (_PDF_BYTES, "application/pdf", "reg.pdf")),
            "id": _key("NATIONAL_ID", (_jpeg_bytes(), "image/jpeg", "nida.jpg")),
        }

    def test_submit_creates_unverified_facility_with_documents(self):
        client, keys = self._facility_client()
        resp = client.post(
            "/api/facilities/me/verification/",
            {
                "facility_type": "HOSPITAL",
                "name": "UMC Mwanza",
                "city": "Mwanza",
                "registration_number": "REG-2026-0001",
                "documents": [
                    {"doc_type": "FACILITY_REGISTRATION", "file_url": keys["reg"]},
                    {"doc_type": "NATIONAL_ID", "file_url": keys["id"]},
                ],
            },
            format="json",
        )
        self.assertEqual(resp.status_code, 200, resp.data)
        facility = Facility.objects.get(name="UMC Mwanza")
        self.assertFalse(facility.is_verified)
        self.assertEqual(
            set(facility.operator.verification_documents.values_list("doc_type", flat=True)),
            {"FACILITY_REGISTRATION", "NATIONAL_ID"},
        )

    def test_submit_without_registration_is_rejected(self):
        client, keys = self._facility_client()
        resp = client.post(
            "/api/facilities/me/verification/",
            {
                "facility_type": "HOSPITAL",
                "name": "UMC Mwanza",
                "documents": [{"doc_type": "NATIONAL_ID", "file_url": keys["id"]}],
            },
            format="json",
        )
        # Mandatory enforcement should reject the bare National ID filing.
        self.assertEqual(resp.status_code, 400)

    def test_submit_only_for_facility_operators(self):
        _, reg = _register("PATIENT")
        client = APIClient()
        client.credentials(HTTP_AUTHORIZATION=f"Bearer {reg.data['access']}")
        resp = client.post(
            "/api/facilities/me/verification/",
            {
                "facility_type": "HOSPITAL",
                "name": "Not Allowed",
                "documents": [],
            },
            format="json",
        )
        self.assertEqual(resp.status_code, 403)

    def test_admin_queue_exposes_document_summary(self):
        client, keys = self._facility_client()
        client.post(
            "/api/facilities/me/verification/",
            {
                "facility_type": "CLINIC",
                "name": "Mwanza Clinic",
                "city": "Mwanza",
                "documents": [
                    {"doc_type": "FACILITY_REGISTRATION", "file_url": keys["reg"]},
                    {"doc_type": "NATIONAL_ID", "file_url": keys["id"]},
                ],
            },
            format="json",
        )
        from rest_framework_simplejwt.tokens import RefreshToken

        admin = User.objects.create_user(
            email="vo-verify@example.com", password=_PASSWORD, first_name="VO",
        )
        UserRole.objects.create(user=admin, role=Role.objects.get(code="SUPER_ADMIN"))
        cadmin = APIClient()
        cadmin.credentials(HTTP_AUTHORIZATION=f"Bearer {RefreshToken.for_user(admin).access_token}")
        list_resp = cadmin.get("/api/admin/facilities/?status=pending")
        self.assertEqual(list_resp.status_code, 200)
        names = [f["name"] for f in list_resp.data["results"]]
        self.assertIn("Mwanza Clinic", names)
        row = next(f for f in list_resp.data["results"] if f["name"] == "Mwanza Clinic")
        self.assertEqual(
            {d["doc_type"] for d in row["verification_documents"]},
            {"FACILITY_REGISTRATION", "NATIONAL_ID"},
        )
        self.assertEqual(
            {d["status"] for d in row["verification_documents"]}, {"PENDING"}
        )


@override_settings(EMAIL_BACKEND="django.core.mail.backends.locmem.EmailBackend")
class ReviewerOpensSubmittedDocumentTests(TestCase):
    """The reviewer must be able to OPEN the documents an applicant submitted
    before deciding (the queue exposes a summary + the ``id``; the audited
    endpoint streams the bytes)."""

    def _pending_doctor_with_docs(self):
        _, reg = _register("DOCTOR")
        client = APIClient()
        client.credentials(HTTP_AUTHORIZATION=f"Bearer {reg.data['access']}")

        def _key(doc_type, content, content_type, filename):
            up = _upload(client, doc_type, content, content_type, filename)
            self.assertEqual(up.status_code, 201, up.data)
            return up.data["file_url"]

        cert_key = _key("CERTIFICATE", _PDF_BYTES, "application/pdf", "cert.pdf")
        id_key = _key("NATIONAL_ID", _jpeg_bytes(), "image/jpeg", "nida.jpg")
        resp = client.post(
            "/api/doctors/me/verification/",
            {
                "professional_type": "DOCTOR",
                "documents": [
                    {"doc_type": "CERTIFICATE", "file_url": cert_key},
                    {"doc_type": "NATIONAL_ID", "file_url": id_key},
                ],
            },
            format="json",
        )
        self.assertEqual(resp.status_code, 200, resp.data)
        return resp.data["uid"]

    def _reviewer_client(self):
        admin = User.objects.create_user(
            email="reviewer-doc@example.com", password=_PASSWORD, first_name="Reviewer",
        )
        UserRole.objects.create(user=admin, role=Role.objects.get(code="SUPER_ADMIN"))
        client = APIClient()
        client.credentials(
            HTTP_AUTHORIZATION=f"Bearer {RefreshToken.for_user(admin).access_token}"
        )
        return client

    def test_doctor_queue_exposes_documents_to_open(self):
        self._pending_doctor_with_docs()
        queue = self._reviewer_client().get("/api/admin/doctors/verification-queue/")
        self.assertEqual(queue.status_code, 200)
        row = queue.data["results"][0]
        types = {d["doc_type"] for d in row["verification_documents"]}
        self.assertEqual(types, {"CERTIFICATE", "NATIONAL_ID"})
        for doc in row["verification_documents"]:
            self.assertIn("id", doc)
            self.assertTrue(doc["file_name"])

    def test_reviewer_can_stream_the_document(self):
        self._pending_doctor_with_docs()
        doc = VerificationDocument.objects.filter(doc_type="NATIONAL_ID").first()
        client = self._reviewer_client()
        resp = client.get(f"/api/admin/verification-documents/{doc.pk}/")
        self.assertEqual(resp.status_code, 200)
        self.assertEqual(resp["Content-Type"], "image/jpeg")
        self.assertIn("inline", resp["Content-Disposition"])
        self.assertGreater(len(b"".join(resp.streaming_content)), 0)
        from audit.models import AuditLog

        self.assertTrue(
            AuditLog.objects.filter(
                action_code="accounts.verification_document_viewed",
                resource_id=doc.pk,
            ).exists()
        )

    def test_non_reviewer_is_denied(self):
        self._pending_doctor_with_docs()
        doc = VerificationDocument.objects.first()
        _, reg = _register("PATIENT")
        patient = APIClient()
        patient.credentials(HTTP_AUTHORIZATION=f"Bearer {reg.data['access']}")
        self.assertEqual(
            patient.get(f"/api/admin/verification-documents/{doc.pk}/").status_code, 403
        )

    def test_anonymous_is_denied(self):
        self._pending_doctor_with_docs()
        doc = VerificationDocument.objects.first()
        resp = APIClient().get(f"/api/admin/verification-documents/{doc.pk}/")
        self.assertIn(resp.status_code, (401, 403))

    def test_missing_document_is_404(self):
        self.assertEqual(
            self._reviewer_client()
            .get("/api/admin/verification-documents/999999/")
            .status_code,
            404,
        )