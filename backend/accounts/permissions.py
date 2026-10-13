"""Permissions and role checks for Sickler's Warriors (§ SD-9 / § 07).

Centralized authorization:

* every permission is a stable ``module.resource.action`` string
* roles are bundles of permissions (never hardcoded role==permission)
* enforce at the API layer with reusable DRF permission classes
* object-level ownership: user may act only on own resources / approved
  relationships (patient↔caregiver/family per consent, doctor↔patient per
  approved care relationship)
* default-deny: unknown or unapproved permission → 403

These classes are consumed by DRF ``filter_backends``/``permission_classes``
project-wide. Never duplicate the checks across views.
"""

from typing import TYPE_CHECKING

from django.db.models import Q
from rest_framework import permissions

if TYPE_CHECKING:  # pragma: no cover — import cycle guard only
    from django.http import HttpRequest

    from .models import User


class IsAuthenticatedRespectStatus(permissions.BasePermission):
    """
    Authenticated AND account status must not be SUSPENDED / DISABLED /
    DEACTIVATED. A logged-in but suspended user is denied everywhere (BR §17,
    BR §18 / "account status"). Safe default used for every protected view.
    """

    message = "Your account is not eligible to access this resource."

    def has_permission(self, request: "HttpRequest", view) -> bool:
        user = getattr(request, "user", None)
        if not (user and user.is_authenticated):
            return False
        return user.account_status in ("ACTIVE", "PENDING_VERIFICATION")


class HasPermission(permissions.BasePermission):
    """
    Role-independent permission check. Deny by default; allow only when the
    user holds an approved permission string (directly or via an active role).

    Usage: ``permission_classes = [require("medical.view")]`` — DRF instantiates
    every entry of ``permission_classes``, so :func:`require` is the class-level
    entry point (an instance would not be callable).
    """

    message = "You do not have permission to perform this action."

    def __init__(self, permission_code: str, *, require_object_ownership: bool = False):
        self.permission_code = permission_code
        self.require_object_ownership = require_object_ownership
        super().__init__()

    def has_permission(self, request: "HttpRequest", view) -> bool:
        user = getattr(request, "user", None)
        if not (user and user.is_authenticated):
            return False
        if not IsAuthenticatedRespectStatus().has_permission(request, view):
            return False
        return user.has_perm_code(self.permission_code)

    def has_object_permission(self, request: "HttpRequest", view, obj) -> bool:
        user = getattr(request, "user", None)
        if not self.has_permission(request, view):
            return False
        if not self.require_object_ownership:
            return True
        owner = getattr(obj, "user", None)
        return owner is not None and owner.pk == user.pk


def require(permission_code: str, *, require_object_ownership: bool = False):
    """Return a concrete permission class bound to ``permission_code``.

    DRF calls ``permission()`` on every item in ``permission_classes``, so a
    class (not an already-instantiated object) is required. ``HasPermission``
    carries state, so we bind the code at definition time.
    """

    def __init__(self):
        HasPermission.__init__(
            self, permission_code, require_object_ownership=require_object_ownership
        )

    return type(
        f"Require({permission_code})",
        (HasPermission,),
        {"__init__": __init__},
    )


class CanReviewVerificationDocuments(permissions.BasePermission):
    """C6 reviewers may open the documents submitted with an application.

    A document belongs to an applicant (a doctor/psychologist/social-support
    professional or a facility operator). Anyone entitled to decide one of
    those applications — ``doctors.verify`` or ``facilities.verify`` — may read
    the attachment behind it so the decision is made on the evidence itself.
    Everyone else is denied (default-deny).
    """

    message = "You are not allowed to review verification documents."
    _CODES = ("doctors.verify", "facilities.verify")

    def has_permission(self, request: "HttpRequest", view) -> bool:
        user = getattr(request, "user", None)
        if not (user and user.is_authenticated):
            return False
        if not IsAuthenticatedRespectStatus().has_permission(request, view):
            return False
        return any(user.has_perm_code(code) for code in self._CODES)


class IsPatient(permissions.BasePermission):
    message = "Only patients may perform this action."

    def has_permission(self, request: "HttpRequest", view) -> bool:
        user = getattr(request, "user", None)
        return bool(user and user.is_authenticated and user.is_patient)


class IsDoctor(permissions.BasePermission):
    message = "Only verified doctors may perform this action."

    def has_permission(self, request: "HttpRequest", view) -> bool:
        user = getattr(request, "user", None)
        return bool(user and user.is_authenticated and user.is_verified_doctor)


class IsCaregiver(permissions.BasePermission):
    message = "Only authorized caregivers may perform this action."

    def has_permission(self, request: "HttpRequest", view) -> bool:
        user = getattr(request, "user", None)
        return bool(user and user.is_authenticated and user.is_caregiver)


class IsBloodDonor(permissions.BasePermission):
    message = "Only registered blood donors may perform this action."

    def has_permission(self, request: "HttpRequest", view) -> bool:
        user = getattr(request, "user", None)
        return bool(user and user.is_authenticated and user.is_blood_donor)


class IsFinancialDonor(permissions.BasePermission):
    message = "Only registered financial donors may perform this action."

    def has_permission(self, request: "HttpRequest", view) -> bool:
        user = getattr(request, "user", None)
        return bool(user and user.is_authenticated and user.is_financial_donor)


class IsAdmin(permissions.BasePermission):
    message = "Only administrators may perform this action."

    def has_permission(self, request: "HttpRequest", view) -> bool:
        user = getattr(request, "user", None)
        return bool(user and user.is_authenticated and user.is_admin)


def _is_prescriber(user) -> bool:
    """A verified DOCTOR holding the approved ``medications.prescribe`` code.

    This is the C2/C3 "doctor may write the patient's medication profile"
    gate (Stage 4.6 user cycle): role + account status + professional
    verification + the clinical permission bundle. It is deliberately
    narrower than ``is_verified_professional`` (a psychologist is never a
    prescriber here) and narrower than verification alone.
    """
    return bool(
        user
        and user.is_authenticated
        and user.is_verified_doctor
        and user.has_perm_code("medications.prescribe")
    )


class MedicationAccess(permissions.BasePermission):
    """Approved medication gates (Stage 4.6, "deny by default").

    Maps DRF action/method to the approved `medications.*` permission codes:

      list/retrieve/events/stats        -> medications.view
      create                            -> medications.create
      update/partial_update/log_dose,
        schedule POST/PATCH             -> medications.update
      destroy, schedule DELETE          -> medications.delete

    A verified prescriber ([_is_prescriber]: APPROVED DOCTOR holding
    ``medications.prescribe``) passes every action — the doctor authors the
    patient's medication profile. No caregiver/hospital role is granted here;
    admin GET-only oversight (C4) is likewise not on patient surfaces.
    """

    message = "You do not have permission to perform this action."

    _ACTION_CODES = {
        "list": "medications.view",
        "retrieve": "medications.view",
        "create": "medications.create",
        "update": "medications.update",
        "partial_update": "medications.update",
        "destroy": "medications.delete",
        "log_dose": "medications.update",
        "events": "medications.view",
        "stats": "medications.view",
    }

    def _code_for(self, request, view) -> str | None:
        action = getattr(view, "action", None) or request.method.lower()
        if action in self._ACTION_CODES:
            return self._ACTION_CODES[action]
        if action == "schedule":
            return "medications.view" if request.method == "GET" else "medications.update"
        if action == "schedule_detail":
            return "medications.delete" if request.method == "DELETE" else "medications.update"
        return None

    def has_permission(self, request: "HttpRequest", view) -> bool:
        user = getattr(request, "user", None)
        if not (user and user.is_authenticated):
            return False
        if not IsAuthenticatedRespectStatus().has_permission(request, view):
            return False
        if _is_prescriber(user):
            return True
        code = self._code_for(request, view)
        return code is not None and user.has_perm_code(code)


class SymptomAccess(permissions.BasePermission):
    """Approved symptom gates (Stage 4.6). Codes: symptoms.view / symptoms.create.

    No update/delete codes exist in the approved matrix — symptom records are
    append-only evidence with no patient-side deletion (corrected by a new
    record, never by mutating history).

    Verified prescribers ([_is_prescriber]) may *read* a patient's symptom log
    (list/retrieve only) so the doctor sees the symptom history alongside the
    medication profile; they can never create a symptom record on the patient's
    behalf.
    """

    message = "You do not have permission to perform this action."

    _ACTION_CODES = {
        "list": "symptoms.view",
        "retrieve": "symptoms.view",
        "create": "symptoms.create",
    }

    def _code_for(self, request, view) -> str | None:
        action = getattr(view, "action", None) or request.method.lower()
        return self._ACTION_CODES.get(action)

    def has_permission(self, request: "HttpRequest", view) -> bool:
        user = getattr(request, "user", None)
        if not (user and user.is_authenticated):
            return False
        if not IsAuthenticatedRespectStatus().has_permission(request, view):
            return False
        if _is_prescriber(user) and request.method in ("GET",):
            return True
        code = self._code_for(request, view)
        return code is not None and user.has_perm_code(code)


class PatientDirectoryAccess(permissions.BasePermission):
    """Doctor-facing patient picker (Stage 4.6 doctor cycle).

    Lets a verified prescriber list the identity rows (uid/name/email) of
    registered patients so the doctor UI can target a patient when authoring
    their medication profile. No medical data is exposed.
    """

    message = "Only a verified prescriber can browse the patient directory."

    def has_permission(self, request: "HttpRequest", view) -> bool:
        user = getattr(request, "user", None)
        if not (user and user.is_authenticated):
            return False
        if not IsAuthenticatedRespectStatus().has_permission(request, view):
            return False
        return _is_prescriber(user)
