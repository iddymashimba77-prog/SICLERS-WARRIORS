"""Patient profile views (approved Stage 4.5 endpoints).

Endpoint contract (api-endpoint-matrix §4):
* GET/PATCH `/patients/me` — `patients.view` (own) / `patients.update_own`
  (own), object rule = owner, audit `—` for self.

Deny-by-default (`patients/views`):
* Authentication alone grants nothing (NFR-SEC-003/004). The caller must
  be a PATIENT (active role) and hold the method-appropriate approved
  permission code.
* Ownership is structural: the row is 1:1 with `request.user` and there is no
  uid lookup on this surface, so IDOR is impossible by construction (a foreign
  identity can never be targeted — no /patients/{uid} here).
* A DOCTOR/CAREGIVER/HOSPITAL/ADMIN never falls through to a patient-owned
  row on this surface; cross-patient medical access flows through the
  approved consent/permission architecture (separate, consent-gated surface).

Audit (§21): changes (create + update) record a SecurityEvent with the event
type only — never the medical payload.
"""

from rest_framework import generics
from rest_framework.exceptions import PermissionDenied

from accounts.models import SecurityEvent
from accounts.permissions import IsAuthenticatedRespectStatus
from patients import models, serializers


class PatientMeView(generics.RetrieveUpdateAPIView):
    """GET/PATCH `/patients/me` — the authenticated patient's own profile."""

    serializer_class = serializers.PatientSerializer
    permission_classes = [IsAuthenticatedRespectStatus]

    def get_object(self):
        user = self.request.user
        if not (user and user.is_authenticated):
            raise PermissionDenied("Authentication required.")
        if not user.is_patient:
            raise PermissionDenied("A patient profile is required for this resource.")
        if self.request.method in ("PUT", "PATCH"):
            if not user.has_perm_code("patients.update_own"):
                raise PermissionDenied(
                    "You do not have permission to edit this profile."
                )
        elif not user.has_perm_code("patients.view"):
            raise PermissionDenied("You do not have permission to view this profile.")

        profile, created = models.Patient.objects.get_or_create(user=user)
        if created:
            SecurityEvent.objects.create(
                user=user, event_type="PROFILE_CREATED", status="SUCCESS"
            )
        return profile

    def perform_update(self, serializer):
        serializer.save()
        SecurityEvent.objects.create(
            user=self.request.user, event_type="PROFILE_UPDATED", status="SUCCESS"
        )