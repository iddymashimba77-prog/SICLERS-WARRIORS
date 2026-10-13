"""Object-level authorization for appointments (§11, role-perm §15/§22).

Authorization is relationship-based, never role-equality:

* **patient** — their own appointments, full lifecycle of booking/cancel.
* **caregiver** — only for a patient they hold an ACTIVE, unexpired `Consent`
  whose `permission_scope` covers appointments.
* **clinical staff** — only an appointment they are attached to as the doctor,
  or one for a patient with an approved care relationship/consent.
* **admin** — directory oversight via `appointments.manage`.

Deny by default: an authenticated user with no relationship sees nothing.
"""

from rest_framework.exceptions import PermissionDenied

from accounts.permissions import IsAuthenticatedRespectStatus, require
from medical_records.services import can_access
from patients.models import Patient

APPOINTMENT_READ = "appointments.read"
APPOINTMENT_WRITE_OWN = "appointments.write_own"
APPOINTMENT_MANAGE = "appointments.manage"


def patient_profile_for(user):
    """Return the `patients.Patient` row for a user, or None."""
    if user is None or not getattr(user, "is_authenticated", False):
        return None
    return Patient.objects.filter(user=user).first()


def accessible_patient_users(user):
    """User rows whose appointments ``user`` may read.

    The patient themselves, plus every patient a caregiver holds a live
    appointments consent for, plus the patients of appointments the user is the
    attending doctor on.
    """
    if user is None or not getattr(user, "is_authenticated", False):
        return []
    from django.contrib.auth import get_user_model
    from .models import ClinicAppointment

    User = get_user_model()
    ids = set()
    own = Patient.objects.filter(user=user).first()
    if own is not None:
        ids.add(own.user_id)
    if user.has_perm_code("patients.records.read"):
        # Caregiver/family access: enumerate live consents for this grantee.
        from medical_records.models import Consent

        now = timezone_now()
        consents = Consent.objects.filter(
            granted_to=user, status="ACTIVE", start_date__lte=now, expires_at__gt=now
        ).select_related("patient_profile")
        for consent in consents:
            scope = consent.permission_scope or []
            codes = [str(c) for c in (scope if isinstance(scope, (list, tuple)) else scope.values())]
            if APPOINTMENT_READ in codes or "appointments" == consent.resource_type:
                ids.add(consent.patient_profile.user_id)
    if hasattr(user, "doctor_profile"):
        ids.update(
            ClinicAppointment.objects.filter(doctor__user=user)
            .values_list("patient_id", flat=True)
            .distinct()
        )
    if user.has_perm_code(APPOINTMENT_MANAGE):
        return list(User.objects.all().values_list("id", flat=True))
    return list(ids)


def timezone_now():
    from django.utils import timezone

    return timezone.now()


class AppointmentAccess:
    """Mixin: resolves the appointment subject and enforces relationship scope."""

    def appointment_queryset(self, queryset):
        user = self.request.user
        return queryset.filter(patient_id__in=accessible_patient_users(user))

    def resolve_target_patient(self, data):
        """Pick the patient a booking is for, enforcing consent for proxies."""
        user = self.request.user
        requested = data.get("patient") or data.get("patient_uid")
        own = patient_profile_for(user)
        if requested in (None, "", "me"):
            if own is None:
                raise PermissionDenied("Only registered patients can book clinic appointments.")
            return own.user
        target = None
        from django.contrib.auth import get_user_model

        User = get_user_model()
        target = User.objects.filter(uid=requested).first() if not str(requested).isdigit() else User.objects.filter(pk=requested).first()
        if target is None:
            from rest_framework.exceptions import NotFound

            raise NotFound("That patient account does not exist.")
        if target == user:
            return target
        target_profile = Patient.objects.filter(user=target).first()
        if target_profile is None:
            raise PermissionDenied("That account is not a registered patient.")
        if can_access(target_profile, user, APPOINTMENT_READ) or can_access(
            target_profile, user, APPOINTMENT_WRITE_OWN
        ):
            return target
        raise PermissionDenied("You do not have consent to act for this patient.")

    def assert_can_manage(self, appointment):
        user = self.request.user
        if appointment.patient_id == user.id:
            return
        if user.has_perm_code(APPOINTMENT_MANAGE):
            return
        if appointment.doctor_id and getattr(appointment.doctor, "user_id", None) == user.id:
            return
        raise PermissionDenied("You cannot change this appointment.")


appointment_permissions = [IsAuthenticatedRespectStatus]
appointment_read_permissions = [IsAuthenticatedRespectStatus, require(APPOINTMENT_READ)]
appointment_manage_permissions = [IsAuthenticatedRespectStatus, require(APPOINTMENT_MANAGE)]