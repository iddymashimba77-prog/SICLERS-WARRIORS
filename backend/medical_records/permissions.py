"""Object-level authorization for clinical records (role-perm §3.4, §15/§22).

Authorization is relationship-based, never role-equality — a permission string
says *what*, this module decides *whose*:

* **patient (owner, C16)** — own chart only; self-entered entries, soft delete.
* **doctor / healthcare staff / hospital (C15/C2/C3)** — read and write only for a
  patient they hold a live `medical_records` consent (or per-record link) for.
* **caregiver (C2/C3)** — read-only, and only under a live consent.
* **admin / super admin (C4)** — audit/oversight only: read requires an
  `X-Oversight-Reason` header that is stored with the access, and every read is
  written to the append-only record history. No create/update/upload.

Deny by default: an authenticated user with no relationship sees nothing, and a
foreign uid is a 404 rather than a 403 so the API never confirms that another
patient's record exists (IDOR-safe, matching the medications stage).
"""

from rest_framework.exceptions import NotFound, PermissionDenied
from rest_framework import permissions

from accounts.permissions import IsAuthenticatedRespectStatus
from patients.models import Patient

from . import services

VIEW = "medical_records.view"
CREATE = "medical_records.create"
UPDATE = "medical_records.update"
DOWNLOAD = "medical_records.download"
UPLOAD = "medical_records.upload"
DELETE = "medical_records.delete"

# Header a C4 oversight read must carry. §3.4 requires a recorded reason; making
# it a header (rather than a body field) means a plain GET cannot silently
# become an oversight read.
OVERSIGHT_REASON_HEADER = "HTTP_X_OVERSIGHT_REASON"
OVERSIGHT_REASON_MIN = 10


def patient_profile_for(user):
    """Return the owning `patients.Patient` row for a user, or None."""
    if user is None or not getattr(user, "is_authenticated", False):
        return None
    return Patient.objects.filter(user=user).first()


def oversight_reason(request) -> str:
    """The recorded justification for a C4 oversight read (may be empty)."""
    raw = (request.META.get(OVERSIGHT_REASON_HEADER) or "").strip()
    return raw[:500]


def assert_oversight_reason(reason: str) -> None:
    if len(reason) < OVERSIGHT_REASON_MIN:
        raise PermissionDenied(
            "Oversight access requires a recorded reason of at least "
            f"{OVERSIGHT_REASON_MIN} characters in the X-Oversight-Reason header."
        )


class MedicalRecordAccess(permissions.BasePermission):
    """Maps DRF action/method to the approved `medical_records.*` codes.

    The *code* gate here is only the first of two checks. It is deliberately
    permissive about the object so the view can distinguish "no permission at
    all" (403) from "permission but not this patient" (404); object scope is
    enforced by `MedicalRecordQuerysetMixin` / `assert_can_*` below.
    """

    message = "You do not have permission to perform this action."

    _ACTION_CODES = {
        "list": VIEW,
        "retrieve": VIEW,
        "history": VIEW,
        "chart_history": VIEW,
        "create": CREATE,
        "update": UPDATE,
        "partial_update": UPDATE,
        "destroy": DELETE,
        "files": VIEW,
        "file_detail": VIEW,
        "upload_file": UPLOAD,
        "remove_file": UPLOAD,
        "share": VIEW,
        "revoke_share": VIEW,
        "set_visibility": UPDATE,
        "set_status": UPDATE,
    }
    # Method overrides for the two detail actions that change meaning by verb.
    _METHOD_OVERRIDES = {
        "files": {"POST": UPLOAD},
        "file_detail": {"DELETE": UPLOAD},
    }

    def _code_for(self, request, view) -> str | None:
        action = getattr(view, "action", None) or request.method.lower()
        override = self._METHOD_OVERRIDES.get(action, {}).get(request.method.upper())
        if override:
            return override
        return self._ACTION_CODES.get(action)

    def has_permission(self, request, view) -> bool:
        user = getattr(request, "user", None)
        if not (user and user.is_authenticated):
            return False
        if not IsAuthenticatedRespectStatus().has_permission(request, view):
            return False
        code = self._code_for(request, view)
        return code is not None and user.has_perm_code(code)


class MedicalRecordScope:
    """Mixin: the read set and the per-object write checks for a viewset."""

    def _is_owner(self, record) -> bool:
        user = self.request.user
        own = patient_profile_for(user)
        return own is not None and record.patient_id == own.pk

    def _is_oversight_reader(self) -> bool:
        """C4 — the admin/supervisor roles reading for oversight, not for work.

        Deliberately keyed on the *role*, not on a permission string: PATIENT
        also holds `medical_records.delete` under C16, so testing for that code
        would silently turn every patient's own chart request into an oversight
        read. Only SUPER_ADMIN/ADMIN qualify.
        """
        user = self.request.user
        return user.is_admin and user.has_perm_code(VIEW)

    def _is_clinical_writer(self) -> bool:
        return bool(services.clinical_writer_patient_ids(self.request.user))

    def readable_patient_ids(self) -> set[int]:
        """Ids the caller may read, including C4 oversight when justified."""
        user = self.request.user
        if self._is_oversight_reader():
            reason = oversight_reason(self.request)
            assert_oversight_reason(reason)
            self._oversight_reason = reason
            return set(Patient.objects.values_list("pk", flat=True))
        return services.readable_patient_ids(user)

    def record_queryset(self, queryset):
        return queryset.filter(patient_id__in=self.readable_patient_ids())

    def get_record_or_404(self, uid):
        """Resolve one record inside the caller's read set, else 404."""
        record = self.record_queryset(
            services.MedicalRecord.objects.filter(uid=uid)
        ).first()
        if record is None:
            raise NotFound("Medical record not found.")
        return record

    def _grant_scope_for(self, record) -> str:
        """Effective scope of a non-owner on one record (least privilege)."""
        return services.linked_record_ids(self.request.user).get(record.pk, "")

    def assert_can_read(self, record) -> None:
        user = self.request.user
        if self._is_owner(record):
            return
        if self._is_oversight_reader():
            assert_oversight_reason(oversight_reason(self.request))
            return
        if not record.is_visible_to_grantee():
            raise NotFound("Medical record not found.")
        scope = self._grant_scope_for(record)
        if scope:
            return
        if services.can_access(record.patient, user, VIEW):
            return
        raise NotFound("Medical record not found.")

    def assert_can_edit(self, record) -> None:
        """Content edit gate (C15 clinicians / C16 owner self-entries).

        A patient may amend what they wrote themselves but may not rewrite a
        clinician's note in place — the clinical text belongs to the clinician
        who entered it, and the patient's control over it is expressed through
        archive/suppress (their data) and consent (who else sees it), not by
        silently editing someone else's clinical opinion.
        """
        user = self.request.user
        if self._is_owner(record):
            if record.recorded_by_id == user.pk:
                if not user.has_perm_code(UPDATE):
                    raise PermissionDenied("You cannot modify this record.")
                return
            raise PermissionDenied(
                "This entry was written by your clinician and cannot be edited "
                "here. You can archive it or change who may see it."
            )
        if record.patient_id in services.clinical_writer_patient_ids(user):
            return
        raise PermissionDenied("You do not have consent to write to this record.")

    def assert_can_attach(self, record) -> None:
        """File upload gate (C16 owner / C15 clinical writer).

        Deliberately *not* `assert_can_edit`: attaching a scan of a paper result
        to a clinician's note is additive evidence about the patient's own
        health, not a rewrite of the clinician's text. Gating it on edit rights
        would make the most common real upload impossible.
        """
        user = self.request.user
        if not user.has_perm_code(UPLOAD):
            raise PermissionDenied("You cannot attach files to this record.")
        if self._is_owner(record):
            return
        if record.patient_id in services.clinical_writer_patient_ids(user):
            return
        raise PermissionDenied("You do not have consent to write to this record.")

    def assert_can_set_status(self, record) -> None:
        """Archive/suppress gate — the owner's control over their own chart."""
        user = self.request.user
        if self._is_owner(record):
            return
        if record.patient_id in services.clinical_writer_patient_ids(user):
            return
        raise PermissionDenied("You cannot change the status of this record.")

    def get_can_attach(self, record) -> bool:
        """Serializer helper: may the caller attach a file to this record?"""
        try:
            self.assert_can_attach(record)
        except Exception:
            return False
        return True

    def assert_can_delete(self, record) -> None:
        """Soft delete: the owner (C16) or C4 oversight, never a clinician."""
        user = self.request.user
        if self._is_owner(record):
            return
        if user.has_perm_code(DELETE):
            reason = oversight_reason(self.request)
            assert_oversight_reason(reason)
            return
        raise PermissionDenied("You cannot delete this record.")