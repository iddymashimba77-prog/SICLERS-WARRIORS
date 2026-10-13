"""Consent authorization service (AUTH-1; database-design §9, role-perm §15/§22).

Enforcement at request time: the grantee's effective permissions are
intersected with the ACTIVE consent `permission_scope`; expiry/revocation are
checked against the DB clock (never client-side). Consent changes/access are
always audited by the views that call these helpers.
"""

from django.utils import timezone

from .models import Consent


def expire_due() -> int:
    """Flip ACTIVE consents past `expires_at` to EXPIRED (DB-clock truth).

    Idempotent; returns the number transitioned. Called lazily at read time so
    an expired grant is never served, without a background job.
    """
    return Consent.objects.filter(status="ACTIVE", expires_at__lte=timezone.now()).update(
        status="EXPIRED"
    )


def active_scope(patient, grantee) -> set[str]:
    """Union of permission codes granted by ACTIVE, non-expired consents.

    ``patient`` is a ``patients.Patient`` row (the grantor). Returns an empty
    set when no live grant covers the pair — deny by default.
    """
    expire_due()
    now = timezone.now()
    codes: set[str] = set()
    rows = Consent.objects.filter(
        patient_profile=patient,
        granted_to=grantee,
        status="ACTIVE",
        start_date__lte=now,
        expires_at__gt=now,
    )
    for row in rows:
        scope = row.permission_scope or []
        if isinstance(scope, (list, tuple)):
            codes.update(str(code) for code in scope)
        elif isinstance(scope, dict):
            codes.update(str(code) for code in scope.values())
    return codes


def can_access(patient, grantee, permission_code: str) -> bool:
    """True when a live consent grants ``permission_code`` to the grantee."""
    return permission_code in active_scope(patient, grantee)


def grant(*, patient, granted_to, permission_scope, resource_type,
          resource_ids=None, purpose="", expires_at=None, start_date=None,
          authorized_role=None):
    """Create an ACTIVE consent (DRAFT→ACTIVE creation per api-design §consent)."""
    now = timezone.now()
    if expires_at is None or expires_at <= now:
        raise ValueError("expires_at must be in the future.")
    if not permission_scope:
        raise ValueError("permission_scope cannot be empty.")
    if start_date is None:
        start_date = now
    row = Consent.objects.create(
        patient_profile=patient,
        granted_to=granted_to,
        authorized_role=authorized_role,
        resource_type=resource_type,
        resource_ids=resource_ids,
        permission_scope=[str(c) for c in permission_scope],
        purpose=purpose,
        start_date=start_date,
        expires_at=expires_at,
        status="ACTIVE",
    )
    return row


def revoke(row: Consent, *, actor) -> Consent:
    """Immediate-effect revocation (FR-MEDREC-005)."""
    if row.status == "REVOKED":
        return row
    row.status = "REVOKED"
    row.revoked_by = actor
    row.revoked_at = timezone.now()
    row.save(update_fields=["status", "revoked_by", "revoked_at", "updated_at"])
    return row


def renew(row: Consent, *, expires_at, actor) -> Consent:
    """Extend expiry on an ACTIVE (or live) consent."""
    if expires_at <= timezone.now():
        raise ValueError("expires_at must be in the future.")
    if row.status not in ("ACTIVE",):
        raise ValueError("Only an active consent can be renewed.")
    row.expires_at = expires_at
    row.save(update_fields=["expires_at", "updated_at"])
    return row

# ---------------------------------------------------------------------------
# Clinical records: file validation, read-set resolution, append-only history
# ---------------------------------------------------------------------------
#
# Clinical attachments are the most sensitive bytes in the system (DB design
# §18 "Highly Sensitive": encrypted at rest, consent-gated, strict audit, never a
# public URL). The rules below are deliberately narrower than the education
# handout rule set: a clinical record file may be a lab PDF or a photo of a
# paper result, and nothing else.

import hashlib

from django.db import transaction

from .models import (
    Consent,
    MedicalRecord,
    MedicalRecordEvent,
    MedicalRecordFile,
    MedicalRecordLink,
)

RECORD_FILE_MAX_BYTES = 15 * 1024 * 1024
RECORD_FILE_ALLOWED_CONTENT_TYPES = {
    "application/pdf",
    "image/jpeg",
    "image/png",
}

# C15 clinical writers: the roles the matrix marks as able to author a clinical
# entry. A PATIENT is deliberately absent — see `clinical_writer_patient_ids`.
# Roles allowed to author a clinical entry — and only under C15 (clinical
# relationship + consent). PSYCHOLOGIST is a clinical professional; SOCIAL_SUPPORT
# is deliberately absent, because a care navigator coordinates support and does not
# write clinical documentation into somebody's chart.
CLINICAL_WRITER_ROLE_CODES = ("DOCTOR", "PSYCHOLOGIST", "HEALTHCARE_STAFF", "HOSPITAL")

_RECORD_FILE_MAGIC = (
    (b"%PDF-", "application/pdf"),
    (b"\xff\xd8\xff", "image/jpeg"),
    (b"\x89PNG\r\n\x1a\n", "image/png"),
)

_RECORD_FILE_EXTENSIONS = {
    "application/pdf": (".pdf",),
    "image/jpeg": (".jpg", ".jpeg"),
    "image/png": (".png",),
}


class RecordFileRejected(ValueError):
    """A clinical attachment failed validation (structured 400 for the client)."""

    def __init__(self, reason, *, field="file"):
        super().__init__(reason)
        self.reason = reason
        self.field = field


def safe_file_name(name: str, *, fallback: str = "record-file") -> str:
    """Reduce an uploaded name to a safe, extension-preserving basename."""
    base = (name or "").replace("\\", "/").rsplit("/", 1)[-1].strip()
    base = "".join(ch for ch in base if ch.isprintable() and ch not in '<>:"|?*')
    base = base.lstrip(".") or fallback
    return base[:255]


def validate_record_file(uploaded) -> dict:
    """Validate a clinical attachment: presence, size, declared type, magic bytes.

    A declared type that disagrees with the bytes is refused rather than
    rewritten, and the stored name must actually carry the extension the bytes
    prove — otherwise a patient would download ``results.pdf.exe``.
    """
    if uploaded is None:
        raise RecordFileRejected("No file was uploaded.")

    size = getattr(uploaded, "size", 0) or 0
    if size <= 0:
        raise RecordFileRejected("The file is empty.")
    if size > RECORD_FILE_MAX_BYTES:
        raise RecordFileRejected(
            f"The file is larger than {RECORD_FILE_MAX_BYTES // (1024 * 1024)} MB."
        )

    declared = (getattr(uploaded, "content_type", "") or "").split(";")[0].strip().lower()
    if declared in ("", "application/octet-stream", "binary/octet-stream"):
        # Mobile pickers and some browsers report octet-stream for an ordinary
        # JPEG or PDF; that is an unknown hint, not a refusal.
        declared = ""
    if declared and declared not in RECORD_FILE_ALLOWED_CONTENT_TYPES:
        raise RecordFileRejected(
            "Unsupported file type. Attach a PDF, JPEG or PNG."
        )

    head = uploaded.read(16)
    try:
        uploaded.seek(0)
    except (AttributeError, ValueError):  # pragma: no cover — non-seekable upload
        pass

    sniffed = next(
        (content_type for prefix, content_type in _RECORD_FILE_MAGIC if head.startswith(prefix)),
        None,
    )
    if sniffed is None:
        raise RecordFileRejected("That file is not a supported document.")
    if declared and declared != sniffed:
        raise RecordFileRejected(
            "The file type does not match its contents. Re-upload the original file."
        )

    name = safe_file_name(getattr(uploaded, "name", "") or "record-file")
    if not name.lower().endswith(_RECORD_FILE_EXTENSIONS[sniffed]):
        raise RecordFileRejected(
            "The file name does not match the file type. Rename it to a "
            + "/".join(_RECORD_FILE_EXTENSIONS[sniffed])
            + " file and try again."
        )

    digest = hashlib.sha256()
    for chunk in uploaded.chunks():
        digest.update(chunk)
    try:
        uploaded.seek(0)
    except (AttributeError, ValueError):  # pragma: no cover — non-seekable upload
        pass
    return {
        "content_type": sniffed,
        "size": size,
        "name": name,
        "checksum": digest.hexdigest(),
    }


@transaction.atomic
def attach_record_file(*, record: MedicalRecord, uploaded, actor) -> MedicalRecordFile:
    """Validate, store and hash one clinical attachment."""
    meta = validate_record_file(uploaded)
    row = MedicalRecordFile(
        record=record,
        file=uploaded,
        file_name=meta["name"],
        content_type=meta["content_type"],
        size_bytes=meta["size"],
        checksum=meta["checksum"],
        uploaded_by=actor,
    )
    row.save()
    record_event(
        record=record, actor=actor, event_type="FILE_ATTACHED",
        details={"file_uid": str(row.uid), "file_name": row.file_name,
                 "size_bytes": row.size_bytes},
    )
    return row


@transaction.atomic
def remove_record_file(*, row: MedicalRecordFile, actor) -> None:
    """Delete an attachment and erase its bytes; history keeps the fact."""
    record = row.record
    details = {"file_uid": str(row.uid), "file_name": row.file_name}
    storage_name = row.file.name
    row.delete()
    if storage_name:
        try:
            from django.core.files.storage import default_storage

            if default_storage.exists(storage_name):
                default_storage.delete(storage_name)
        except Exception:  # pragma: no cover — storage failure must not 500 a DELETE
            pass
    record_event(record=record, actor=actor, event_type="FILE_REMOVED", details=details)


def record_event(
    *, patient=None, record=None, actor=None, event_type: str, details=None,
    from_status: str = "", to_status: str = "",
) -> MedicalRecordEvent:
    """Append one immutable history row (FR-MEDREC-006).

    `details` must stay non-PHI: field names, counts, file names, statuses. The
    clinical text itself lives in the record and must never be copied into an
    audit/history payload (DB design §18, §21).
    """
    if patient is None and record is not None:
        patient = record.patient
    return MedicalRecordEvent.objects.create(
        patient=patient,
        record=record,
        actor=actor,
        event_type=event_type,
        from_status=from_status or "",
        to_status=to_status or "",
        details=dict(details or {}),
    )


def live_consent_patient_ids(user) -> set[int]:
    """Patient ids a grantee holds a live `medical_records` consent for.

    A consent qualifies when it is ACTIVE, inside its window, and its
    `permission_scope` actually names a medical-record permission. A consent for
    a different resource (say `appointments`) does **not** open the chart.
    """
    expire_due()
    now = timezone.now()
    codes_needed = ("medical_records.view", "medical_records.download")
    ids: set[int] = set()
    rows = Consent.objects.filter(
        granted_to=user, status="ACTIVE", start_date__lte=now, expires_at__gt=now,
    ).select_related("patient_profile")
    for row in rows:
        scope = row.permission_scope or []
        codes = {
            str(code) for code in (
                scope if isinstance(scope, (list, tuple)) else scope.values()
            )
        }
        if row.resource_type != "medical_records" and not codes & set(codes_needed):
            continue
        ids.add(row.patient_profile_id)
    return ids


def linked_record_ids(user) -> dict[int, str]:
    """Record ids handed to ``user`` directly, mapped to their scope.

    A per-record `MedicalRecordLink` is the narrowest grant possible: it opens
    exactly one record, optionally time-boxed, and is revoked instantly.
    """
    now = timezone.now()
    scope_by_record: dict[int, str] = {}
    rows = MedicalRecordLink.objects.filter(
        granted_to=user, revoked_at__isnull=True,
    ).select_related("record")
    for row in rows:
        if row.expires_at is not None and row.expires_at <= now:
            continue
        if not row.record.is_visible_to_grantee():
            continue
        scope_by_record[row.record_id] = row.scope
    return scope_by_record


def readable_patient_ids(user) -> set[int]:
    """Patient ids whose chart ``user`` may read (owner ∪ consent ∪ link).

    Deliberately excludes admins: C4 oversight is handled by its own explicit
    branch that demands a recorded reason, so it can never be reached by an
    ordinary list request.
    """
    from patients.models import Patient

    ids: set[int] = set()
    own = Patient.objects.filter(user=user).first()
    if own is not None:
        ids.add(own.pk)
    ids |= live_consent_patient_ids(user)
    for record_id in linked_record_ids(user):
        record = MedicalRecord.objects.filter(pk=record_id).select_related("patient").first()
        if record is not None:
            ids.add(record.patient_id)
    return ids


def clinical_writer_patient_ids(user) -> set[int]:
    """Patient ids ``user`` may author clinical entries for (C15).

    C15 is "clinical relationship **and** consent": a consent alone lets a
    caregiver *read* the chart but never write into it. Only the three roles the
    matrix marks as clinical writers (DOC/STA/HOS) qualify, and each still needs
    a live consent — so a PATIENT, however carefully scoped their own consent,
    can never author an entry into somebody else's chart.
    """
    if not user.has_perm_code("medical_records.create"):
        return set()
    if not any(code in user.role_codes for code in CLINICAL_WRITER_ROLE_CODES):
        return set()
    # C5: professional verification, not merely the role. A pending, rejected or
    # suspended professional is not an eligible clinical writer even with a
    # consent. `is_verified_professional` covers DOCTOR and PSYCHOLOGIST; STA and
    # HOS have no registry row and are gated by facility verification instead
    # (see `assert_writer_facility_is_verified`).
    if (
        any(code in user.role_codes for code in ("DOCTOR", "PSYCHOLOGIST"))
        and not user.is_verified_professional
    ):
        return set()
    return live_consent_patient_ids(user)


def assert_writer_facility_is_verified(facility) -> None:
    """C7: a clinical entry may only be attributed to a verified facility.

    A record naming an unverified facility would launder a claim of clinical
    authority through the record, so the write is refused instead.
    """
    if facility is not None and not facility.is_verified:
        raise ValueError("Records can only be attributed to a verified facility.")
