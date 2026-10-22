"""Psychologist workspace endpoints (§2).

Access rules, one line each:
  * role gate   — the exact ``psychology.*`` permission code from the
    professional's role bundle (deny for PATIENT, DOCTOR, SOCIAL_SUPPORT …);
  * consent     — a live patient consent naming the matching psychology code,
    the same machinery the medical-records module uses (deny by default);
  * verification — a write also needs an APPROVED registry row (C5).
  * separation  — caseload and rows are scoped to this professional only;
    social-work endpoints live in another app and never read these tables.
"""
from django.core.exceptions import PermissionDenied
from django.db.models import Max, Min
from django.utils import timezone
from rest_framework import generics, status as http_status
from rest_framework.exceptions import ValidationError
from rest_framework.response import Response

from accounts.permissions import IsAuthenticatedRespectStatus, require
from appointments.models import ClinicAppointment
from audit.services import record_audit
from core.pagination import CorePageNumberPagination
from doctors.models import Doctor
from medical_records.models import Consent
from medical_records.services import can_access
from patients.models import Patient

from . import models, serializers

PSYCHOLOGY_PREFIX = "psychology."


def psychology_consent_scopes(user) -> dict[int, set[str]]:
    """patient_id → the live ``psychology.*`` codes granted to ``user``.

    Delegates to the shared consent service so this workspace and the
    social-work one can never drift apart on expiry/revocation rules.
    """
    from medical_records.services import live_scope_map

    return live_scope_map(user, PSYCHOLOGY_PREFIX)


def _require_verified_professional(user) -> None:
    if not user.is_verified_professional:
        raise PermissionDenied(
            "Your professional verification must be approved before you can record."
        )


def _resolve_patient(patient_uid) -> Patient:
    patient = Patient.objects.filter(user__uid=patient_uid).first()
    if patient is None:
        raise ValidationError({"patient_uid": "That patient account does not exist."})
    return patient


def _assert_write_consent(user, patient, code: str) -> None:
    if not can_access(patient, user, code):
        raise PermissionDenied("You do not have consent to record for this patient.")


class CaseloadView(generics.ListAPIView):
    """The psychologist's caseload: consented patients ∪ booked appointments.

    Rows are identity-only (name, consent state) — records stay hidden until
    read consent is checked per row. An appointment without consent shows as
    ``has_consent: false``: contactable, not readable.
    """

    pagination_class = CorePageNumberPagination
    serializer_class = serializers.CaseloadItemSerializer
    permission_classes = [IsAuthenticatedRespectStatus, require("psychology.assessments.read")]

    def get_queryset(self):
        user = self.request.user
        ids = set(psychology_consent_scopes(user))
        registry_row = Doctor.objects.filter(user=user).first()
        if registry_row is not None:
            ids |= set(
                Patient.objects.filter(
                    user__clinic_appointments__doctor=registry_row,
                    user__deleted_at__isnull=True,
                ).values_list("id", flat=True)
            )
        return (
            Patient.objects.filter(id__in=ids, user__deleted_at__isnull=True)
            .select_related("user")
            .order_by("user__first_name", "user__last_name", "pk")
        )

    def list(self, request, *args, **kwargs):
        queryset = self.filter_queryset(self.get_queryset())
        page = self.paginate_queryset(queryset)
        scopes = psychology_consent_scopes(request.user)
        last_appointment: dict = {}
        if page:
            by_user = {patient.user_id: patient.pk for patient in page}
            rows = (
                ClinicAppointment.objects.filter(patient_id__in=by_user)
                .values("patient_id")
                .annotate(latest=Max("scheduled_at"))
            )
            last_appointment = {
                by_user[row["patient_id"]]: row["latest"] for row in rows
            }
        context = self.get_serializer_context()
        context["psych_scope"] = scopes
        context["last_appointment"] = last_appointment
        next_appointment: dict = {}
        if page:
            upcoming = (
                ClinicAppointment.objects.filter(
                    patient_id__in=by_user, scheduled_at__gte=timezone.now()
                )
                .values("patient_id")
                .annotate(earliest=Min("scheduled_at"))
            )
            next_appointment = {
                by_user[row["patient_id"]]: row["earliest"] for row in upcoming
            }
        context["next_appointment"] = next_appointment
        serializer = self.get_serializer(page or queryset, many=True, context=context)
        return self.get_paginated_response(serializer.data)


class AssessmentListCreateView(generics.ListCreateAPIView):
    pagination_class = CorePageNumberPagination

    def get_permissions(self):
        if self.request.method == "POST":
            return [IsAuthenticatedRespectStatus(), require("psychology.assessments.create")()]
        return [IsAuthenticatedRespectStatus(), require("psychology.assessments.read")()]

    def get_serializer_class(self):
        if self.request.method == "POST":
            return serializers.PsychAssessmentCreateSerializer
        return serializers.PsychAssessmentSerializer

    def get_queryset(self):
        scopes = psychology_consent_scopes(self.request.user)
        readable = {
            pid for pid, codes in scopes.items()
            if "psychology.assessments.read" in codes
        }
        qs = models.PsychAssessment.objects.filter(patient_id__in=readable).select_related(
            "patient__user", "author"
        )
        patient_uid = self.request.query_params.get("patient_uid")
        if patient_uid:
            qs = qs.filter(patient__user__uid=patient_uid)
        risk_level = (self.request.query_params.get("risk_level") or "").strip().upper()
        if risk_level:
            if risk_level not in dict(models.PsychAssessment.RISK_LEVELS):
                raise ValidationError({"risk_level": "Unknown risk level."})
            qs = qs.filter(risk_level=risk_level)
        return qs

    def create(self, request, *args, **kwargs):
        serializer = self.get_serializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        data = serializer.validated_data
        patient = _resolve_patient(data["patient_uid"])
        _require_verified_professional(request.user)
        _assert_write_consent(request.user, patient, "psychology.assessments.create")
        assessment = models.PsychAssessment.objects.create(
            patient=patient,
            author=request.user,
            concerns=data["concerns"],
            impression=data["impression"],
            risk_level=data["risk_level"],
            notes=data.get("notes", ""),
            assessed_at=data.get("assessed_at") or timezone.now(),
            follow_up_at=data.get("follow_up_at"),
        )
        record_audit(
            actor=request.user,
            action_code="psychology.assessments.create",
            resource_type="psych_assessment",
            resource_id=assessment.pk,
            request=request,
            details={
                "assessment_uid": str(assessment.uid),
                "risk_level": assessment.risk_level,
            },
        )
        return Response(
            serializers.PsychAssessmentSerializer(assessment).data,
            status=http_status.HTTP_201_CREATED,
        )


class ProgressNoteListCreateView(generics.ListCreateAPIView):
    pagination_class = CorePageNumberPagination

    def get_permissions(self):
        if self.request.method == "POST":
            return [IsAuthenticatedRespectStatus(), require("psychology.progress_notes.create")()]
        return [IsAuthenticatedRespectStatus(), require("psychology.progress_notes.read")()]

    def get_serializer_class(self):
        if self.request.method == "POST":
            return serializers.ProgressNoteCreateSerializer
        return serializers.ProgressNoteSerializer

    def get_queryset(self):
        scopes = psychology_consent_scopes(self.request.user)
        readable = {
            pid for pid, codes in scopes.items()
            if "psychology.progress_notes.read" in codes
        }
        qs = models.ProgressNote.objects.filter(patient_id__in=readable).select_related(
            "patient__user", "author"
        )
        patient_uid = self.request.query_params.get("patient_uid")
        if patient_uid:
            qs = qs.filter(patient__user__uid=patient_uid)
        return qs

    def create(self, request, *args, **kwargs):
        serializer = self.get_serializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        data = serializer.validated_data
        patient = _resolve_patient(data["patient_uid"])
        _require_verified_professional(request.user)
        _assert_write_consent(request.user, patient, "psychology.progress_notes.create")
        note = models.ProgressNote.objects.create(
            patient=patient,
            author=request.user,
            note=data["note"],
            session_at=data.get("session_at") or timezone.now(),
            follow_up_at=data.get("follow_up_at"),
        )
        record_audit(
            actor=request.user,
            action_code="psychology.notes.create",
            resource_type="psych_progress_note",
            resource_id=note.pk,
            request=request,
            details={"note_uid": str(note.uid)},
        )
        return Response(
            serializers.ProgressNoteSerializer(note).data,
            status=http_status.HTTP_201_CREATED,
        )


class ReferralListCreateView(generics.ListCreateAPIView):
    pagination_class = CorePageNumberPagination
    permission_classes = [IsAuthenticatedRespectStatus, require("psychology.counseling.manage")]

    def get_serializer_class(self):
        if self.request.method == "POST":
            return serializers.PsychologyReferralCreateSerializer
        return serializers.PsychologyReferralSerializer

    def get_queryset(self):
        scopes = psychology_consent_scopes(self.request.user)
        manageable = {
            pid for pid, codes in scopes.items()
            if "psychology.counseling.manage" in codes
        }
        qs = models.PsychologyReferral.objects.filter(patient_id__in=manageable).select_related(
            "patient__user", "author"
        )
        patient_uid = self.request.query_params.get("patient_uid")
        if patient_uid:
            qs = qs.filter(patient__user__uid=patient_uid)
        status_param = (self.request.query_params.get("status") or "").strip().upper()
        if status_param:
            if status_param not in dict(models.PsychologyReferral.STATUSES):
                raise ValidationError({"status": "Unknown status."})
            qs = qs.filter(status=status_param)
        return qs

    def create(self, request, *args, **kwargs):
        serializer = self.get_serializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        data = serializer.validated_data
        patient = _resolve_patient(data["patient_uid"])
        _require_verified_professional(request.user)
        _assert_write_consent(request.user, patient, "psychology.counseling.manage")
        referral = models.PsychologyReferral.objects.create(
            patient=patient,
            author=request.user,
            destination=data["destination"],
            reason=data["reason"],
            urgency=data["urgency"],
            responsible_person=data.get("responsible_person", ""),
            follow_up_at=data.get("follow_up_at"),
        )
        record_audit(
            actor=request.user,
            action_code="psychology.referrals.create",
            resource_type="psychology_referral",
            resource_id=referral.pk,
            request=request,
            details={
                "referral_uid": str(referral.uid),
                "urgency": referral.urgency,
            },
        )
        return Response(
            serializers.PsychologyReferralSerializer(referral).data,
            status=http_status.HTTP_201_CREATED,
        )


class ReferralDetailView(generics.RetrieveUpdateAPIView):
    permission_classes = [IsAuthenticatedRespectStatus, require("psychology.counseling.manage")]
    lookup_field = "uid"

    def get_serializer_class(self):
        if self.request.method == "PATCH":
            return serializers.PsychologyReferralStatusSerializer
        return serializers.PsychologyReferralSerializer

    def get_queryset(self):
        scopes = psychology_consent_scopes(self.request.user)
        manageable = {
            pid for pid, codes in scopes.items()
            if "psychology.counseling.manage" in codes
        }
        return models.PsychologyReferral.objects.filter(
            patient_id__in=manageable
        ).select_related("patient__user", "author")

    def update(self, request, *args, **kwargs):
        referral = self.get_object()
        serializer = self.get_serializer(data=request.data, partial=kwargs.pop("partial", False))
        serializer.is_valid(raise_exception=True)
        data = serializer.validated_data
        changed = []
        if "status" in data and data["status"] != referral.status:
            referral.status = data["status"]
            changed.append("status")
        if "responsible_person" in data:
            referral.responsible_person = data["responsible_person"]
            changed.append("responsible_person")
        if "follow_up_at" in data:
            referral.follow_up_at = data["follow_up_at"]
            changed.append("follow_up_at")
        if changed:
            referral.save(update_fields=changed + ["updated_at"])
            record_audit(
                actor=request.user,
                action_code="psychology.referrals.update",
                resource_type="psychology_referral",
                resource_id=referral.pk,
                request=request,
                details={"referral_uid": str(referral.uid), "changed": changed},
            )
        return Response(serializers.PsychologyReferralSerializer(referral).data)
