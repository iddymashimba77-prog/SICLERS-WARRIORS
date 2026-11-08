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

import datetime

from django.db.models import Sum
from django.utils import timezone
from rest_framework import generics, status
from rest_framework.exceptions import PermissionDenied, ValidationError
from rest_framework.parsers import JSONParser
from rest_framework.response import Response
from rest_framework.views import APIView

from accounts.models import SecurityEvent, User
from accounts.permissions import (
    IsAuthenticatedRespectStatus, IsPatient, PatientDirectoryAccess,
)
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

    def update(self, request, *args, **kwargs):
        """Profile completion requires a treating facility (§6).

        Checked on the *validated* payload, before anything is written: a
        patient who has not chosen where they are treated must not end up with
        half of a PATCH persisted just because the request came back 400. An
        existing profile that already has a facility may patch other fields
        without resending it, so the field is only mandatory when it is being
        cleared or was never set.
        """
        instance = self.get_object()
        serializer = self.get_serializer(
            instance, data=request.data, partial=kwargs.pop("partial", False)
        )
        serializer.is_valid(raise_exception=True)
        # `PatientSerializer.validate` renames facility_uid -> facility, so the
        # resolved Facility instance (or None) lands under that key. Absence
        # means this PATCH left the facility alone.
        _UNSET = object()
        facility = serializer.validated_data.get("facility", _UNSET)
        if facility is _UNSET:
            facility = instance.facility
        if facility is None:
            raise ValidationError(
                {
                    "facility_uid": [
                        "A treating facility is required. Choose one from the "
                        "facility directory before completing your profile."
                    ]
                }
            )
        self.perform_update(serializer)
        return Response(serializer.data)


class PatientDirectoryView(generics.ListAPIView):
    """GET `/patients/directory/` — verified-prescriber patient picker.

    Identity rows (uid/email/name) for every registered PATIENT so a doctor
    can select whom they are building a medication profile for. No medical
    payload is exposed; access is the verified DOCTOR + ``medications.prescribe``
    bundle (PatientDirectoryAccess).
    """

    serializer_class = serializers.PatientDirectorySerializer
    permission_classes = [IsAuthenticatedRespectStatus, PatientDirectoryAccess]
    pagination_class = None

    def get_queryset(self):
        return (
            User.objects.filter(
                user_roles__role__code="PATIENT", user_roles__is_active=True
            )
            .distinct()
            .order_by("first_name", "email")
        )

# ---------------------------------------------------------------------------
# Patient hydration tracker
# ---------------------------------------------------------------------------


def _hydration_profile(user):
    profile, _ = models.Patient.objects.get_or_create(user=user)
    return profile


def _require_hydration_code(user, code):
    if not user.has_perm_code(code):
        raise PermissionDenied(
            "You do not have permission to manage hydration records."
        )


class HydrationTodayView(APIView):
    """GET/POST `/patients/me/hydration/` — own hydration summary and intake.

    The response intentionally carries no default goal: ``goal_ml`` is null
    until the patient (with their care team) sets one. Records are append-only
    in this surface so history stays honest.
    """

    permission_classes = [IsAuthenticatedRespectStatus, IsPatient]
    parser_classes = [JSONParser]

    def get(self, request):
        user = request.user
        _require_hydration_code(user, "hydration.view")
        profile = _hydration_profile(user)

        raw_date = request.query_params.get("date")
        if raw_date:
            try:
                day = datetime.date.fromisoformat(raw_date)
            except ValueError:
                raise ValidationError({"date": "Use an ISO date (YYYY-MM-DD)."})
        else:
            day = timezone.localdate()

        entries = models.HydrationEntry.objects.filter(
            patient=user, recorded_at__date=day
        )
        consumed = entries.aggregate(total=Sum("amount_ml"))["total"] or 0
        goal = profile.hydration_goal_ml
        remaining = max(goal - consumed, 0) if goal is not None else None
        progress = (
            min(round(consumed / goal * 100), 100)
            if goal and goal > 0
            else None
        )
        return Response(
            {
                "date": day.isoformat(),
                "goal_ml": goal,
                "consumed_ml": consumed,
                "remaining_ml": remaining,
                "progress_pct": progress,
                "entries": serializers.HydrationEntrySerializer(
                    entries, many=True
                ).data,
            }
        )

    def post(self, request):
        user = request.user
        _require_hydration_code(user, "hydration.create")
        serializer = serializers.HydrationEntrySerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        entry = serializer.save(patient=user)
        return Response(
            serializers.HydrationEntrySerializer(entry).data,
            status=status.HTTP_201_CREATED,
        )


class HydrationGoalView(APIView):
    """PATCH `/patients/me/hydration/goal/` — set or clear the personal goal."""

    permission_classes = [IsAuthenticatedRespectStatus, IsPatient]
    parser_classes = [JSONParser]

    def patch(self, request):
        user = request.user
        _require_hydration_code(user, "hydration.update")
        serializer = serializers.HydrationGoalSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        profile = _hydration_profile(user)
        profile.hydration_goal_ml = serializer.validated_data["hydration_goal_ml"]
        profile.save(update_fields=["hydration_goal_ml", "updated_at"])
        return Response({"hydration_goal_ml": profile.hydration_goal_ml})
