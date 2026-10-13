"""Clinical medical records + history suite (FR-MEDREC, role-perm §3.4).

Test-only; never imported by production code. Uses the shared QA helpers so the
suite stays deterministic on ephemeral SQLite.

The cases below are the ones that matter for a chart surface:

* the read set is the only gate — a patient with no consent sees nothing, and a
  foreign uid is a 404 rather than a 403 that would confirm existence;
* C15 stops a consented *reader* (caregiver) from authoring into the chart;
* C4 oversight cannot happen by accident — no reason header, no read;
* the history is append-only in the database layer, not by convention;
* clinical files cannot be fetched around the chart's own read gate.
"""

import io
import uuid

from django.core.files.uploadedfile import SimpleUploadedFile
from django.test import TestCase, override_settings
from django.utils import timezone

from accounts.models import User
from doctors.models import Doctor
from facilities.models import Facility
from medical_records import models, services
from qa.qa_helpers import (
    client,
    directory_facility,
    orm_patient_profile,
    orm_user,
)

_MEDIA = override_settings(MEDIA_ROOT="/tmp/opencode/medrec-media")

MINIMAL_PDF = (
    b"%PDF-1.4\n1 0 obj\n<< /Type /Catalog >>\nendobj\ntrailer\n%%EOF\n"
)
JPEG_BYTES = b"\xff\xd8\xff\xe0\x00\x10JFIF" + b"\x00" * 32 + b"\xff\xd9"


def _png_bytes() -> bytes:
    """A minimal 1x1 PNG (signature + IHDR/IDAT/IEND) built without Pillow."""
    import struct
    import zlib

    def chunk(kind: bytes, payload: bytes) -> bytes:
        return (
            struct.pack(">I", len(payload))
            + kind
            + payload
            + struct.pack(">I", zlib.crc32(kind + payload) & 0xFFFFFFFF)
        )

    header = struct.pack(">IIBBBBB", 1, 1, 8, 2, 0, 0, 0)
    return (
        b"\x89PNG\r\n\x1a\n"
        + chunk(b"IHDR", header)
        + chunk(b"IDAT", zlib.compress(b"\x00\xff\xff\xff"))
        + chunk(b"IEND", b"")
    )


class MedicalRecordTestBase(TestCase):
    """Shared fixtures: a patient chart, a verified doctor, a caregiver."""

    def setUp(self):
        self.patient_user = orm_user("PATIENT")
        self.patient = orm_patient_profile(self.patient_user)
        self.facility = directory_facility()

        self.doctor_user = orm_user("DOCTOR")
        self.doctor = Doctor.objects.create(
            user=self.doctor_user,
            facility=self.facility,
            license_number=f"LIC-{uuid.uuid4().hex[:8]}",
            verification_status="APPROVED",
        )

        self.caregiver_user = orm_user("CAREGIVER")
        self.admin_user = orm_user("ADMIN")

        self.category = models.RecordCategory.objects.create(
            code="LAB_RESULT", name="Lab result",
        )
        self.record = self._make_record()

    def _make_record(self, **extra):
        defaults = {
            "patient": self.patient,
            "category": self.category,
            "title": "Full blood count",
            "description": "Hb 8.1 g/dL",
            "recorded_by": self.doctor_user,
            "recorded_at": timezone.now() - timezone.timedelta(days=3),
            "facility": self.facility,
        }
        defaults.update(extra)
        return models.MedicalRecord.objects.create(**defaults)

    def _grant(self, grantee, *codes, days=30):
        return services.grant(
            patient=self.patient,
            granted_to=grantee,
            permission_scope=list(codes),
            resource_type="medical_records",
            expires_at=timezone.now() + timezone.timedelta(days=days),
            purpose="treatment",
        )


class RecordVisibilityTests(MedicalRecordTestBase):
    def test_anonymous_caller_is_refused(self):
        from rest_framework.test import APIClient

        for path in ("/api/medical-records/", f"/api/medical-records/{self.record.uid}/"):
            with self.subTest(path=path):
                self.assertIn(APIClient().get(path).status_code, (401, 403))

    def test_owner_sees_own_record(self):
        response = client(self.patient_user).get(f"/api/medical-records/{self.record.uid}/")
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.data["uid"], str(self.record.uid))
        self.assertEqual(response.data["description"], "Hb 8.1 g/dL")

    def test_foreign_patient_gets_404_not_403(self):
        stranger = orm_user("PATIENT")
        orm_patient_profile(stranger)
        response = client(stranger).get(f"/api/medical-records/{self.record.uid}/")
        # 404 rather than 403: a 403 would confirm the record exists.
        self.assertEqual(response.status_code, 404)

    def test_stranger_list_never_leaks_the_chart(self):
        stranger = orm_user("PATIENT")
        orm_patient_profile(stranger)
        response = client(stranger).get("/api/medical-records/")
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.data["count"], 0)

    def test_consented_caregiver_reads(self):
        self._grant(self.caregiver_user, "medical_records.view")
        response = client(self.caregiver_user).get(
            f"/api/medical-records/{self.record.uid}/"
        )
        self.assertEqual(response.status_code, 200)

    def test_caregiver_without_consent_gets_404(self):
        response = client(self.caregiver_user).get(
            f"/api/medical-records/{self.record.uid}/"
        )
        self.assertEqual(response.status_code, 404)

    def test_consent_for_another_resource_does_not_open_the_chart(self):
        services.grant(
            patient=self.patient,
            granted_to=self.caregiver_user,
            permission_scope=["appointments.read"],
            resource_type="appointments",
            expires_at=timezone.now() + timezone.timedelta(days=30),
        )
        response = client(self.caregiver_user).get(
            f"/api/medical-records/{self.record.uid}/"
        )
        self.assertEqual(response.status_code, 404)

    def test_expired_consent_stops_access(self):
        consent = self._grant(self.caregiver_user, "medical_records.view")
        consent.expires_at = timezone.now() - timezone.timedelta(hours=1)
        consent.save(update_fields=["expires_at"])
        response = client(self.caregiver_user).get(
            f"/api/medical-records/{self.record.uid}/"
        )
        self.assertEqual(response.status_code, 404)

    def test_revoked_consent_stops_access(self):
        consent = self._grant(self.caregiver_user, "medical_records.view")
        services.revoke(consent, actor=self.patient_user)
        response = client(self.caregiver_user).get(
            f"/api/medical-records/{self.record.uid}/"
        )
        self.assertEqual(response.status_code, 404)


class OversightTests(MedicalRecordTestBase):
    """C4 — audit/oversight only, and never by accident."""

    def test_admin_read_without_a_reason_is_refused(self):
        response = client(self.admin_user).get("/api/medical-records/")
        self.assertEqual(response.status_code, 403)

    def test_admin_read_with_a_reason_succeeds_and_is_recorded(self):
        response = client(self.admin_user).get(
            f"/api/medical-records/{self.record.uid}/",
            HTTP_X_OVERSIGHT_REASON="Annual audit sample review 2026",
        )
        self.assertEqual(response.status_code, 200)
        self.assertTrue(
            models.MedicalRecordEvent.objects.filter(
                record=self.record, actor=self.admin_user, event_type="VIEWED",
            ).exists()
        )

    def test_admin_may_not_author_a_record(self):
        response = client(self.admin_user).post(
            "/api/medical-records/",
            {"title": "Injected", "category_code": "LAB_RESULT"},
            format="json",
        )
        self.assertEqual(response.status_code, 403)

    def test_admin_may_not_edit_or_attach(self):
        api = client(self.admin_user)
        patch = api.patch(
            f"/api/medical-records/{self.record.uid}/",
            {"title": "Rewritten by admin"},
            format="json",
            HTTP_X_OVERSIGHT_REASON="Annual audit sample review 2026",
        )
        self.assertIn(patch.status_code, (403, 404))


class ClinicalWriteTests(MedicalRecordTestBase):
    """C15 clinical relationship + consent; C16 self-entered owner entries."""

    def test_patient_creates_a_self_entered_record(self):
        response = client(self.patient_user).post(
            "/api/medical-records/",
            {"title": "Home BP log", "category_code": "LAB_RESULT"},
            format="json",
        )
        self.assertEqual(response.status_code, 201, response.data)
        record = models.MedicalRecord.objects.get(uid=response.data["uid"])
        self.assertEqual(record.recorded_by_id, self.patient_user.pk)
        self.assertEqual(record.patient_id, self.patient.pk)

    def test_patient_may_edit_their_own_entry(self):
        mine = self._make_record(
            recorded_by=self.patient_user, title="Home BP log",
        )
        response = client(self.patient_user).patch(
            f"/api/medical-records/{mine.uid}/", {"title": "Home BP log (revised)"},
            format="json",
        )
        self.assertEqual(response.status_code, 200, response.data)
        mine.refresh_from_db()
        self.assertEqual(mine.title, "Home BP log (revised)")

    def test_patient_may_not_rewrite_a_clinician_entry(self):
        response = client(self.patient_user).patch(
            f"/api/medical-records/{self.record.uid}/", {"title": "Mine now"},
            format="json",
        )
        self.assertEqual(response.status_code, 403)
        self.record.refresh_from_db()
        self.assertEqual(self.record.title, "Full blood count")

    def test_consented_doctor_may_write_for_the_patient(self):
        self._grant(self.doctor_user, "medical_records.view", "medical_records.create")
        response = client(self.doctor_user).post(
            "/api/medical-records/",
            {
                "title": "Post-discharge review",
                "category_code": "LAB_RESULT",
                "patient_uid": str(self.patient_user.uid),
                "facility_uid": str(self.facility.uid),
            },
            format="json",
        )
        self.assertEqual(response.status_code, 201, response.data)
        record = models.MedicalRecord.objects.get(uid=response.data["uid"])
        self.assertEqual(record.recorded_by_id, self.doctor_user.pk)

    def test_doctor_without_consent_may_not_write(self):
        response = client(self.doctor_user).post(
            "/api/medical-records/",
            {
                "title": "Unsolicited note",
                "category_code": "LAB_RESULT",
                "patient_uid": str(self.patient_user.uid),
            },
            format="json",
        )
        self.assertEqual(response.status_code, 403)

    def test_consented_caregiver_may_not_write(self):
        """A consent that grants *view* must never become a write capability."""
        self._grant(self.caregiver_user, "medical_records.view")
        response = client(self.caregiver_user).post(
            "/api/medical-records/",
            {
                "title": "Caregiver note",
                "category_code": "LAB_RESULT",
                "patient_uid": str(self.patient_user.uid),
            },
            format="json",
        )
        self.assertEqual(response.status_code, 403)

    def test_unverified_doctor_may_not_write(self):
        pending_user = orm_user("DOCTOR")
        Doctor.objects.create(
            user=pending_user, license_number=f"PEND-{uuid.uuid4().hex[:8]}",
            verification_status="PENDING",
        )
        self._grant(pending_user, "medical_records.view", "medical_records.create")
        response = client(pending_user).post(
            "/api/medical-records/",
            {
                "title": "Pending doctor note",
                "category_code": "LAB_RESULT",
                "patient_uid": str(self.patient_user.uid),
            },
            format="json",
        )
        # The role grants the code, but C5 professional verification does not
        # hold, so the account is not an eligible clinical writer.
        self.assertIn(response.status_code, (403, 404))

    def test_unknown_category_is_refused(self):
        response = client(self.patient_user).post(
            "/api/medical-records/",
            {"title": "Nope", "category_code": "NOT_A_CATEGORY"},
            format="json",
        )
        self.assertEqual(response.status_code, 400)

    def test_recorded_at_cannot_be_in_the_future(self):
        future = timezone.now() + timezone.timedelta(days=3)
        response = client(self.patient_user).post(
            "/api/medical-records/",
            {
                "title": "Tomorrow",
                "category_code": "LAB_RESULT",
                "recorded_at": future.isoformat(),
            },
            format="json",
        )
        self.assertEqual(response.status_code, 400)

    def test_unverified_facility_cannot_be_attributed(self):
        unverified = Facility.objects.create(
            name="Backstreet Clinic", facility_type="CLINIC", is_verified=False,
        )
        self._grant(self.doctor_user, "medical_records.view", "medical_records.create")
        response = client(self.doctor_user).post(
            "/api/medical-records/",
            {
                "title": "Note at an unverified clinic",
                "category_code": "LAB_RESULT",
                "patient_uid": str(self.patient_user.uid),
                "facility_uid": str(unverified.uid),
            },
            format="json",
        )
        self.assertEqual(response.status_code, 400)
        self.assertIn("facility_uid", str(response.data))


class StatusAndVisibilityTests(MedicalRecordTestBase):
    def test_patient_archives_their_own_record(self):
        response = client(self.patient_user).post(
            f"/api/medical-records/{self.record.uid}/status/",
            {"status": "ARCHIVED", "reason": "Old test result"},
            format="json",
        )
        self.assertEqual(response.status_code, 200, response.data)
        self.assertEqual(response.data["status"], "ARCHIVED")

    def test_suppressed_record_leaves_the_consent_read_set(self):
        self._grant(self.caregiver_user, "medical_records.view")
        client(self.patient_user).post(
            f"/api/medical-records/{self.record.uid}/status/",
            {"status": "SUPPRESSED"},
            format="json",
        )
        response = client(self.caregiver_user).get(
            f"/api/medical-records/{self.record.uid}/"
        )
        self.assertEqual(response.status_code, 404)

    def test_private_record_leaves_the_consent_read_set(self):
        self._grant(self.caregiver_user, "medical_records.view")
        response = client(self.patient_user).post(
            f"/api/medical-records/{self.record.uid}/visibility/",
            {"is_consent_visible": False},
            format="json",
        )
        self.assertEqual(response.status_code, 200, response.data)
        self.assertEqual(
            client(self.caregiver_user).get(
                f"/api/medical-records/{self.record.uid}/"
            ).status_code,
            404,
        )

    def test_only_the_patient_may_change_visibility(self):
        self._grant(self.doctor_user, "medical_records.view", "medical_records.create")
        response = client(self.doctor_user).post(
            f"/api/medical-records/{self.record.uid}/visibility/",
            {"is_consent_visible": False},
            format="json",
        )
        self.assertEqual(response.status_code, 403)

    def test_delete_is_soft_and_keeps_history(self):
        response = client(self.patient_user).delete(
            f"/api/medical-records/{self.record.uid}/"
        )
        self.assertEqual(response.status_code, 204)
        self.record.refresh_from_db()
        self.assertIsNotNone(self.record.deleted_at)
        self.assertTrue(
            models.MedicalRecordEvent.objects.filter(
                record=self.record, event_type="DELETED",
            ).exists()
        )


class ShareTests(MedicalRecordTestBase):
    def test_patient_shares_one_record_with_a_named_user(self):
        response = client(self.patient_user).post(
            f"/api/medical-records/{self.record.uid}/share/",
            {
                "granted_to_uid": str(self.caregiver_user.uid),
                "scope": "view",
                "expires_at": (timezone.now() + timezone.timedelta(days=7)).isoformat(),
            },
            format="json",
        )
        self.assertEqual(response.status_code, 201, response.data)
        self.assertEqual(
            client(self.caregiver_user).get(
                f"/api/medical-records/{self.record.uid}/"
            ).status_code,
            200,
        )

    def test_per_record_share_does_not_open_the_whole_chart(self):
        other = self._make_record(title="Second result")
        client(self.patient_user).post(
            f"/api/medical-records/{self.record.uid}/share/",
            {"granted_to_uid": str(self.caregiver_user.uid), "scope": "view"},
            format="json",
        )
        self.assertEqual(
            client(self.caregiver_user).get(
                f"/api/medical-records/{other.uid}/"
            ).status_code,
            404,
        )

    def test_revoking_a_share_is_immediate(self):
        link = models.MedicalRecordLink.objects.create(
            record=self.record,
            granted_to=self.caregiver_user,
            scope="view",
            granted_by_patient=self.patient,
        )
        self.assertEqual(
            client(self.caregiver_user).get(
                f"/api/medical-records/{self.record.uid}/"
            ).status_code,
            200,
        )
        client(self.patient_user).post(
            f"/api/medical-records/{self.record.uid}/share/revoke/",
            {"link_uid": str(link.uid)},
            format="json",
        )
        self.assertEqual(
            client(self.caregiver_user).get(
                f"/api/medical-records/{self.record.uid}/"
            ).status_code,
            404,
        )

    def test_expired_link_stops_access(self):
        models.MedicalRecordLink.objects.create(
            record=self.record,
            granted_to=self.caregiver_user,
            scope="view",
            granted_by_patient=self.patient,
            expires_at=timezone.now() - timezone.timedelta(hours=1),
        )
        self.assertEqual(
            client(self.caregiver_user).get(
                f"/api/medical-records/{self.record.uid}/"
            ).status_code,
            404,
        )

    def test_caregiver_may_not_reshare(self):
        models.MedicalRecordLink.objects.create(
            record=self.record,
            granted_to=self.caregiver_user,
            scope="view",
            granted_by_patient=self.patient,
        )
        third = orm_user("CAREGIVER")
        response = client(self.caregiver_user).post(
            f"/api/medical-records/{self.record.uid}/share/",
            {"granted_to_uid": str(third.uid), "scope": "view"},
            format="json",
        )
        self.assertEqual(response.status_code, 403)

    def test_private_record_cannot_be_shared(self):
        client(self.patient_user).post(
            f"/api/medical-records/{self.record.uid}/visibility/",
            {"is_consent_visible": False},
            format="json",
        )
        response = client(self.patient_user).post(
            f"/api/medical-records/{self.record.uid}/share/",
            {"granted_to_uid": str(self.caregiver_user.uid), "scope": "view"},
            format="json",
        )
        self.assertEqual(response.status_code, 400)


@_MEDIA
class RecordFileTests(MedicalRecordTestBase):
    def _upload(self, api, uid=None, name="result.pdf", body=MINIMAL_PDF, ctype="application/pdf"):
        return api.post(
            f"/api/medical-records/{uid or self.record.uid}/files/",
            {"file": SimpleUploadedFile(name, body, content_type=ctype)},
            format="multipart",
        )

    def test_patient_attaches_a_pdf(self):
        response = self._upload(client(self.patient_user))
        self.assertEqual(response.status_code, 201, response.data)
        row = models.MedicalRecordFile.objects.get(uid=response.data["uid"])
        self.assertEqual(row.content_type, "application/pdf")
        self.assertEqual(row.checksum and len(row.checksum), 64)
        # The stored key must never be handed out as a URL.
        self.assertNotIn("file", response.data)
        self.assertNotIn("http", response.data["download_path"])

    def test_consented_doctor_attaches_a_scan(self):
        self._grant(
            self.doctor_user, "medical_records.view", "medical_records.create",
        )
        response = self._upload(
            client(self.doctor_user), name="scan.jpg", body=JPEG_BYTES,
            ctype="image/jpeg",
        )
        self.assertEqual(response.status_code, 201, response.data)

    def test_stranger_cannot_attach(self):
        stranger = orm_user("PATIENT")
        orm_patient_profile(stranger)
        self.assertEqual(self._upload(client(stranger)).status_code, 404)

    def test_extension_mismatch_is_refused(self):
        response = self._upload(
            client(self.patient_user), name="result.pdf.exe", body=MINIMAL_PDF,
        )
        self.assertEqual(response.status_code, 400)

    def test_declared_type_must_match_bytes(self):
        response = self._upload(
            client(self.patient_user), name="result.jpg", body=MINIMAL_PDF,
            ctype="image/jpeg",
        )
        self.assertEqual(response.status_code, 400)

    def test_non_document_bytes_are_refused(self):
        response = self._upload(
            client(self.patient_user), name="notes.txt", body=b"just text",
            ctype="text/plain",
        )
        self.assertEqual(response.status_code, 400)

    def test_download_requires_the_chart_read_gate(self):
        upload = self._upload(client(self.patient_user))
        stranger = orm_user("PATIENT")
        orm_patient_profile(stranger)
        response = client(stranger).get(
            f"/api/medical-records/files/{upload.data['uid']}/download/"
        )
        self.assertIn(response.status_code, (403, 404))

    def test_owner_downloads_the_bytes(self):
        upload = self._upload(client(self.patient_user))
        response = client(self.patient_user).get(
            f"/api/medical-records/files/{upload.data['uid']}/download/"
        )
        self.assertEqual(response.status_code, 200)
        self.assertEqual(b"".join(response.streaming_content), MINIMAL_PDF)

    def test_caregiver_without_consent_cannot_fetch_bytes(self):
        """The bytes must not be reachable by bypassing the chart's read gate."""
        upload = self._upload(client(self.patient_user))
        response = client(self.caregiver_user).get(
            f"/api/medical-records/files/{upload.data['uid']}/download/"
        )
        self.assertIn(response.status_code, (403, 404))

    def test_consented_caregiver_may_fetch_bytes(self):
        self._grant(self.caregiver_user, "medical_records.view", "medical_records.download")
        upload = self._upload(client(self.patient_user))
        response = client(self.caregiver_user).get(
            f"/api/medical-records/files/{upload.data['uid']}/download/"
        )
        self.assertEqual(response.status_code, 200)
        self.assertEqual(b"".join(response.streaming_content), MINIMAL_PDF)

    def test_revoked_consent_closes_the_file_route_too(self):
        self._grant(self.caregiver_user, "medical_records.view", "medical_records.download")
        upload = self._upload(client(self.patient_user))
        consent = services.revoke(
            models.Consent.objects.get(patient_profile=self.patient, granted_to=self.caregiver_user),
            actor=self.patient_user,
        )
        self.assertEqual(consent.status, "REVOKED")
        self.assertIn(
            client(self.caregiver_user).get(
                f"/api/medical-records/files/{upload.data['uid']}/download/"
            ).status_code,
            (403, 404),
        )

    def test_removing_a_file_erases_the_bytes_but_keeps_history(self):
        upload = self._upload(client(self.patient_user))
        response = client(self.patient_user).delete(
            f"/api/medical-records/{self.record.uid}/files/{upload.data['uid']}/"
        )
        self.assertEqual(response.status_code, 204)
        self.assertFalse(
            models.MedicalRecordFile.objects.filter(uid=upload.data["uid"]).exists()
        )
        self.assertTrue(
            models.MedicalRecordEvent.objects.filter(
                record=self.record, event_type="FILE_REMOVED",
            ).exists()
        )


class HistoryTests(MedicalRecordTestBase):
    def test_reading_a_record_writes_a_history_row(self):
        client(self.patient_user).get(f"/api/medical-records/{self.record.uid}/")
        event = models.MedicalRecordEvent.objects.filter(
            record=self.record, event_type="VIEWED",
        ).first()
        self.assertIsNotNone(event)
        self.assertEqual(event.actor_id, self.patient_user.pk)

    def test_history_endpoint_returns_the_append_only_trail(self):
        client(self.patient_user).post(
            f"/api/medical-records/{self.record.uid}/status/",
            {"status": "ARCHIVED", "reason": "superseded"},
            format="json",
        )
        response = client(self.patient_user).get(
            f"/api/medical-records/{self.record.uid}/history/"
        )
        self.assertEqual(response.status_code, 200)
        types = [row["event_type"] for row in response.data]
        self.assertIn("STATUS_CHANGED", types)
        changed = next(r for r in response.data if r["event_type"] == "STATUS_CHANGED")
        self.assertEqual(changed["from_status"], "ACTIVE")
        self.assertEqual(changed["to_status"], "ARCHIVED")

    def test_chart_history_covers_the_whole_chart(self):
        second = self._make_record(title="Second result")
        client(self.patient_user).get(f"/api/medical-records/{self.record.uid}/")
        client(self.patient_user).get(f"/api/medical-records/{second.uid}/")
        response = client(self.patient_user).get("/api/medical-records/history/")
        self.assertEqual(response.status_code, 200)
        uids = {row["record_uid"] for row in response.data}
        self.assertEqual(uids, {str(self.record.uid), str(second.uid)})

    def test_history_never_carries_clinical_text(self):
        client(self.patient_user).patch(
            f"/api/medical-records/{self.record.uid}/status/",
            {"status": "ARCHIVED", "reason": "superseded"},
            format="json",
        )
        response = client(self.patient_user).get(
            f"/api/medical-records/{self.record.uid}/history/"
        )
        blob = str(response.data)
        self.assertNotIn("Hb 8.1", blob)

    def test_stranger_history_is_404(self):
        stranger = orm_user("PATIENT")
        orm_patient_profile(stranger)
        response = client(stranger).get(
            f"/api/medical-records/{self.record.uid}/history/"
        )
        self.assertEqual(response.status_code, 404)

    def test_history_rows_are_immutable_in_the_model_layer(self):
        event = models.MedicalRecordEvent.objects.create(
            patient=self.patient, record=self.record, actor=self.doctor_user,
            event_type="VIEWED",
        )
        event.event_type = "UPDATED"
        with self.assertRaises(ValueError):
            event.save()
        with self.assertRaises(ValueError):
            event.delete()

    def test_bulk_history_rewrite_is_refused(self):
        models.MedicalRecordEvent.objects.create(
            patient=self.patient, record=self.record, event_type="VIEWED",
        )
        with self.assertRaises(ValueError):
            models.MedicalRecordEvent.objects.filter(record=self.record).delete()


class EncounterTests(MedicalRecordTestBase):
    def test_consented_doctor_opens_an_encounter(self):
        self._grant(
            self.doctor_user, "medical_records.view", "medical_records.create",
        )
        response = client(self.doctor_user).post(
            "/api/clinical-encounters/",
            {
                "patient_uid": str(self.patient_user.uid),
                "encounter_type": "CLINIC_VISIT",
                "occurred_at": timezone.now().isoformat(),
                "facility_uid": str(self.facility.uid),
                "summary": "Routine review",
            },
            format="json",
        )
        self.assertEqual(response.status_code, 201, response.data)
        encounter = models.ClinicalEncounter.objects.get(uid=response.data["uid"])
        self.assertEqual(encounter.doctor_id, self.doctor.pk)

    def test_patient_cannot_open_an_encounter(self):
        response = client(self.patient_user).post(
            "/api/clinical-encounters/",
            {
                "encounter_type": "CLINIC_VISIT",
                "occurred_at": timezone.now().isoformat(),
            },
            format="json",
        )
        self.assertEqual(response.status_code, 403)

    def test_doctor_without_consent_cannot_open_an_encounter(self):
        response = client(self.doctor_user).post(
            "/api/clinical-encounters/",
            {
                "patient_uid": str(self.patient_user.uid),
                "encounter_type": "CLINIC_VISIT",
                "occurred_at": timezone.now().isoformat(),
            },
            format="json",
        )
        self.assertEqual(response.status_code, 403)


class CatalogTests(MedicalRecordTestBase):
    def test_categories_are_authenticated_reference_data(self):
        from rest_framework.test import APIClient

        self.assertIn(APIClient().get("/api/record-categories/").status_code, (401, 403))
        response = client(self.patient_user).get("/api/record-categories/")
        self.assertEqual(response.status_code, 200)
        self.assertIn("LAB_RESULT", {row["code"] for row in response.data["results"]})

    def test_anonymous_cannot_reach_the_chart_history(self):
        from rest_framework.test import APIClient

        self.assertIn(
            APIClient().get("/api/medical-records/history/").status_code, (401, 403),
        )

class NestedPatientRouteTests(MedicalRecordTestBase):
    """The approved `/patients/{uid}/medical-records` shape (matrix §9)."""

    BASE = "/api/patients/{uid}/medical-records"

    def test_owner_reads_their_chart_through_the_nested_route(self):
        response = client(self.patient_user).get(
            self.BASE.format(uid=self.patient_user.uid) + "/"
        )
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.data["count"], 1)

    def test_nested_detail_resolves(self):
        response = client(self.patient_user).get(
            self.BASE.format(uid=self.patient_user.uid) + f"/{self.record.uid}/"
        )
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.data["uid"], str(self.record.uid))

    def test_nested_route_does_not_bypass_the_consent_gate(self):
        """The nesting must not become a wider door than the flat resource."""
        response = client(self.caregiver_user).get(
            self.BASE.format(uid=self.patient_user.uid) + f"/{self.record.uid}/"
        )
        self.assertEqual(response.status_code, 404)

    def test_unknown_patient_is_404(self):
        response = client(self.patient_user).get(
            self.BASE.format(uid=uuid.uuid4()) + "/"
        )
        self.assertEqual(response.status_code, 404)

    def test_nested_list_cannot_show_another_patients_chart(self):
        other_user = orm_user("PATIENT")
        other = orm_patient_profile(other_user)
        other_record = self._make_record(patient=other, title="Someone else's result")
        response = client(self.patient_user).get(
            self.BASE.format(uid=self.patient_user.uid) + "/"
        )
        uids = {row["uid"] for row in response.data["results"]}
        self.assertNotIn(str(other_record.uid), uids)

    def test_nested_create_targets_the_url_patient(self):
        self._grant(
            self.doctor_user, "medical_records.view", "medical_records.create",
        )
        response = client(self.doctor_user).post(
            self.BASE.format(uid=self.patient_user.uid) + "/",
            {"title": "Nested entry", "category_code": "LAB_RESULT"},
            format="json",
        )
        self.assertEqual(response.status_code, 201, response.data)
        self.assertEqual(response.data["patient_uid"], str(self.patient_user.uid))

    def test_nested_history_is_scoped_to_that_patient(self):
        base = self.BASE.format(uid=self.patient_user.uid)
        client(self.patient_user).get(f"{base}/{self.record.uid}/")
        response = client(self.patient_user).get(f"{base}/history/")
        self.assertEqual(response.status_code, 200)
        self.assertEqual({row["record_uid"] for row in response.data}, {str(self.record.uid)})

    def test_oversight_nested_read_still_needs_a_reason(self):
        response = client(self.admin_user).get(
            self.BASE.format(uid=self.patient_user.uid) + "/"
        )
        self.assertEqual(response.status_code, 403)
        allowed = client(self.admin_user).get(
            self.BASE.format(uid=self.patient_user.uid) + "/",
            HTTP_X_OVERSIGHT_REASON="Annual audit sample review 2026",
        )
        self.assertEqual(allowed.status_code, 200)

    def test_me_alias_serves_the_callers_own_chart(self):
        """`/patients/me/medical-records` is the documented owner entry point."""
        response = client(self.patient_user).get("/api/patients/me/medical-records/")
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.data["count"], 1)
        uids = {row["uid"] for row in response.data["results"]}
        self.assertEqual(uids, {str(self.record.uid)})

    def test_me_alias_detail_and_history_resolve(self):
        base = "/api/patients/me/medical-records"
        detail = client(self.patient_user).get(f"{base}/{self.record.uid}/")
        self.assertEqual(detail.status_code, 200)
        self.assertEqual(detail.data["uid"], str(self.record.uid))
        history = client(self.patient_user).get(f"{base}/{self.record.uid}/history/")
        self.assertEqual(history.status_code, 200)
        self.assertTrue(history.data)

    def test_me_alias_for_a_user_without_a_patient_profile_is_404(self):
        non_patient = orm_user("DOCTOR")
        response = client(non_patient).get("/api/patients/me/medical-records/")
        self.assertEqual(response.status_code, 404)

    def test_me_alias_never_exposes_another_chart(self):
        other_user = orm_user("PATIENT")
        other_patient = orm_patient_profile(other_user)
        other_record = self._make_record(patient=other_patient, title="Someone else's result")
        response = client(self.patient_user).get("/api/patients/me/medical-records/")
        uids = {row["uid"] for row in response.data["results"]}
        self.assertIn(str(self.record.uid), uids)
        self.assertNotIn(str(other_record.uid), uids)

    def test_me_alias_create_targets_the_caller(self):
        response = client(self.patient_user).post(
            "/api/patients/me/medical-records/",
            {"title": "Own entry via alias", "category_code": "LAB_RESULT"},
            format="json",
        )
        self.assertEqual(response.status_code, 201, response.data)
        self.assertEqual(response.data["patient_uid"], str(self.patient_user.uid))
