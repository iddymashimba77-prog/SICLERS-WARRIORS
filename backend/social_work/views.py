"""Social-support workspace endpoints (§3).

Access rules, one line each:
  * role gate     — the exact ``social.*`` permission code from the role
    bundle (deny for PATIENT, DOCTOR, PSYCHOLOGIST … — separation);
  * consent       — a live patient consent naming the matching social code;
  * verification  — a write also needs an APPROVED registry row (C5);
  * boundaries    — case status moves only through the state machine, and
    this app never touches money: ``linked_workflow`` points at existing
    campaign/donation workflows instead.
"""
from django.core.exceptions import PermissionDenied
from django.utils import timezone
from rest_framework import generics, status as http_status
from rest_framework.exceptions import ValidationError
from rest_framework.response import Response

from accounts.permissions import IsAuthenticatedRespectStatus, require
from audit.services import record_audit
from core.pagination import CorePageNumberPagination
from doctors.models import Doctor
from medical_records.models import Consent
from medical_records.services import can_access, live_scope_map
from patients.models import Patient

from . import models, serializers

SOCIAL_PREFIX = "social."


def social_consent_scopes(user) -> dict[int, set[str]]:
    """patient_id → live ``social.*`` codes granted to ``user`` (shared service)."""
    return live_scope_map(user, SOCIAL_PREFIX)


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


class SocialCaseloadView(generics.ListAPIView):
    """The social worker's caseload: consented patients ∪ booked appointments."""

    pagination_class = CorePageNumberPagination
    serializer_class = serializers.SocialCaseloadItemSerializer
    permission_classes = [IsAuthenticatedRespectStatus, require("social.cases.read")]

    def get_queryset(self):
        user = self.request.user
        ids = set(social_consent_scopes(user))
        registry_row = Doctor.objects.filter(user=user).first()
        if registry_row is not None:
            from appointments.models import ClinicAppointment

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
        scopes = social_consent_scopes(request.user)
        open_cases: dict = {}
        if page:
            from django.db.models import Count

            rows = (
                models.SocialCase.objects.filter(
                    patient_id__in=[p.pk for p in page]
                ).exclude(status="RESOLVED")
                .values("patient_id")
                .annotate(total=Count("id"))
            )
            open_cases = {row["patient_id"]: row["total"] for row in rows}
        context = self.get_serializer_context()
        context["social_scope"] = scopes
        context["open_cases"] = open_cases
        serializer = self.get_serializer(page or queryset, many=True, context=context)
        return self.get_paginated_response(serializer.data)


class CaseListCreateView(generics.ListCreateAPIView):
    pagination_class = CorePageNumberPagination

    def get_permissions(self):
        if self.request.method == "POST":
            return [IsAuthenticatedRespectStatus(), require("social.cases.create")()]
        return [IsAuthenticatedRespectStatus(), require("social.cases.read")()]

    def get_serializer_class(self):
        if self.request.method == "POST":
            return serializers.SocialCaseCreateSerializer
        return serializers.SocialCaseSerializer

    def get_queryset(self):
        scopes = social_consent_scopes(self.request.user)
        readable = {pid for pid, codes in scopes.items() if "social.cases.read" in codes}
        qs = models.SocialCase.objects.filter(patient_id__in=readable).select_related(
            "patient__user", "opened_by"
        )
        patient_uid = self.request.query_params.get("patient_uid")
        if patient_uid:
            qs = qs.filter(patient__user__uid=patient_uid)
        status_param = (self.request.query_params.get("status") or "").strip().upper()
        if status_param:
            if status_param not in dict(models.SocialCase.STATUSES):
                raise ValidationError({"status": "Unknown status."})
            qs = qs.filter(status=status_param)
        return qs

    def create(self, request, *args, **kwargs):
        serializer = self.get_serializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        data = serializer.validated_data
        patient = _resolve_patient(data["patient_uid"])
        _require_verified_professional(request.user)
        _assert_write_consent(request.user, patient, "social.cases.create")
        case = models.SocialCase.objects.create(
            patient=patient,
            opened_by=request.user,
            title=data["title"],
            linked_workflow=data.get("linked_workflow", ""),
            opened_at=timezone.now(),
        )
        record_audit(
            actor=request.user,
            action_code="social.cases.create",
            resource_type="social_case",
            resource_id=case.pk,
            request=request,
            details={"case_uid": str(case.uid)},
        )
        return Response(
            serializers.SocialCaseSerializer(case).data,
            status=http_status.HTTP_201_CREATED,
        )


class CaseDetailView(generics.RetrieveUpdateAPIView):
    lookup_field = "uid"

    def get_permissions(self):
        if self.request.method == "PATCH":
            return [IsAuthenticatedRespectStatus(), require("social.cases.update")()]
        return [IsAuthenticatedRespectStatus(), require("social.cases.read")()]

    def get_serializer_class(self):
        if self.request.method == "PATCH":
            return serializers.SocialCaseStatusSerializer
        return serializers.SocialCaseSerializer

    def get_queryset(self):
        scopes = social_consent_scopes(self.request.user)
        readable = {pid for pid, codes in scopes.items() if "social.cases.read" in codes}
        return models.SocialCase.objects.filter(patient_id__in=readable).select_related(
            "patient__user", "opened_by"
        )

    def update(self, request, *args, **kwargs):
        case = self.get_object()
        partial = kwargs.pop("partial", False)
        serializer = self.get_serializer(data=request.data, partial=partial)
        serializer.is_valid(raise_exception=True)
        data = serializer.validated_data
        if "status" not in data:
            raise ValidationError({"status": "This endpoint only transitions case status."})
        _require_verified_professional(request.user)
        _assert_write_consent(request.user, case.patient, "social.cases.update")
        new_status = data["status"]
        if new_status != case.status:
            allowed = models.SocialCase.TRANSITIONS.get(case.status, [])
            if new_status not in allowed:
                raise ValidationError({
                    "status": (
                        f"Cannot move a {case.status} case to {new_status}. "
                        f"Allowed: {', '.join(allowed) or 'none'}."
                    )
                })
            case.status = new_status
            update_fields = ["status", "updated_at"]
            if new_status == "RESOLVED":
                case.closed_at = timezone.now()
                update_fields.append("closed_at")
            elif case.closed_at is not None:
                case.closed_at = None
                update_fields.append("closed_at")
            case.save(update_fields=update_fields)
            record_audit(
                actor=request.user,
                action_code="social.cases.update",
                resource_type="social_case",
                resource_id=case.pk,
                request=request,
                details={"case_uid": str(case.uid), "to_status": new_status},
            )
        return Response(serializers.SocialCaseSerializer(case).data)


class CaseNoteListCreateView(generics.ListCreateAPIView):
    pagination_class = CorePageNumberPagination

    def get_permissions(self):
        if self.request.method == "POST":
            return [IsAuthenticatedRespectStatus(), require("social.cases.update")()]
        return [IsAuthenticatedRespectStatus(), require("social.cases.read")()]

    def get_serializer_class(self):
        if self.request.method == "POST":
            return serializers.CaseNoteCreateSerializer
        return serializers.CaseNoteSerializer

    def _case_or_404(self):
        case = models.SocialCase.objects.filter(
            uid=self.kwargs["uid"]
        ).select_related("patient", "patient__user").first()
        if case is None:
            from rest_framework.exceptions import NotFound

            raise NotFound("Case not found.")
        return case

    def get_queryset(self):
        case = self._case_or_404()
        scopes = social_consent_scopes(self.request.user)
        readable = {pid for pid, codes in scopes.items() if "social.cases.read" in codes}
        if case.patient_id not in readable:
            return models.CaseNote.objects.none()
        return models.CaseNote.objects.filter(case=case).select_related("author")

    def create(self, request, *args, **kwargs):
        case = self._case_or_404()
        serializer = self.get_serializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        _require_verified_professional(request.user)
        _assert_write_consent(request.user, case.patient, "social.cases.update")
        note = models.CaseNote.objects.create(
            case=case, author=request.user, note=serializer.validated_data["note"],
        )
        record_audit(
            actor=request.user,
            action_code="social.cases.notes.create",
            resource_type="social_case_note",
            resource_id=note.pk,
            request=request,
            details={"note_uid": str(note.uid), "case_uid": str(case.uid)},
        )
        return Response(
            serializers.CaseNoteSerializer(note).data,
            status=http_status.HTTP_201_CREATED,
        )


class NeedsAssessmentListCreateView(generics.ListCreateAPIView):
    pagination_class = CorePageNumberPagination

    def get_permissions(self):
        if self.request.method == "POST":
            return [IsAuthenticatedRespectStatus(), require("social.cases.create")()]
        return [IsAuthenticatedRespectStatus(), require("social.cases.read")()]

    def get_serializer_class(self):
        if self.request.method == "POST":
            return serializers.SocialNeedsAssessmentCreateSerializer
        return serializers.SocialNeedsAssessmentSerializer

    def get_queryset(self):
        scopes = social_consent_scopes(self.request.user)
        readable = {pid for pid, codes in scopes.items() if "social.cases.read" in codes}
        qs = models.SocialNeedsAssessment.objects.filter(
            patient_id__in=readable
        ).select_related("patient__user", "author")
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
        _assert_write_consent(request.user, patient, "social.cases.create")
        assessment = models.SocialNeedsAssessment.objects.create(
            patient=patient,
            author=request.user,
            needs=data["needs"],
            observations=data.get("observations", ""),
            follow_up_at=data.get("follow_up_at"),
            assessed_at=data.get("assessed_at") or timezone.now(),
        )
        record_audit(
            actor=request.user,
            action_code="social.needs.create",
            resource_type="social_needs_assessment",
            resource_id=assessment.pk,
            request=request,
            details={"assessment_uid": str(assessment.uid), "need_count": len(assessment.needs)},
        )
        return Response(
            serializers.SocialNeedsAssessmentSerializer(assessment).data,
            status=http_status.HTTP_201_CREATED,
        )


class ReferralListCreateView(generics.ListCreateAPIView):
    pagination_class = CorePageNumberPagination

    def get_permissions(self):
        if self.request.method == "POST":
            return [IsAuthenticatedRespectStatus(), require("social.referrals.create")()]
        return [IsAuthenticatedRespectStatus(), require("social.referrals.read")()]

    def get_serializer_class(self):
        if self.request.method == "POST":
            return serializers.SocialReferralCreateSerializer
        return serializers.SocialReferralSerializer

    def get_queryset(self):
        scopes = social_consent_scopes(self.request.user)
        readable = {pid for pid, codes in scopes.items() if "social.referrals.read" in codes}
        qs = models.SocialReferral.objects.filter(patient_id__in=readable).select_related(
            "patient__user", "author", "case"
        )
        patient_uid = self.request.query_params.get("patient_uid")
        if patient_uid:
            qs = qs.filter(patient__user__uid=patient_uid)
        status_param = (self.request.query_params.get("status") or "").strip().upper()
        if status_param:
            if status_param not in dict(models.SocialReferral.STATUSES):
                raise ValidationError({"status": "Unknown status."})
            qs = qs.filter(status=status_param)
        return qs

    def create(self, request, *args, **kwargs):
        serializer = self.get_serializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        data = serializer.validated_data
        patient = _resolve_patient(data["patient_uid"])
        case = None
        if data.get("case_uid"):
            case = models.SocialCase.objects.filter(
                uid=data["case_uid"], patient=patient
            ).first()
            if case is None:
                raise ValidationError({"case_uid": "No such case for this patient."})
        _require_verified_professional(request.user)
        _assert_write_consent(request.user, patient, "social.referrals.create")
        referral = models.SocialReferral.objects.create(
            patient=patient,
            case=case,
            author=request.user,
            destination=data["destination"],
            reason=data["reason"],
            urgency=data["urgency"],
            responsible_person=data.get("responsible_person", ""),
            follow_up_at=data.get("follow_up_at"),
        )
        record_audit(
            actor=request.user,
            action_code="social.referrals.create",
            resource_type="social_referral",
            resource_id=referral.pk,
            request=request,
            details={"referral_uid": str(referral.uid), "urgency": referral.urgency},
        )
        return Response(
            serializers.SocialReferralSerializer(referral).data,
            status=http_status.HTTP_201_CREATED,
        )


class ReferralDetailView(generics.RetrieveUpdateAPIView):
    lookup_field = "uid"

    def get_permissions(self):
        if self.request.method == "PATCH":
            return [IsAuthenticatedRespectStatus(), require("social.referrals.update")()]
        return [IsAuthenticatedRespectStatus(), require("social.referrals.read")()]

    def get_serializer_class(self):
        if self.request.method == "PATCH":
            return serializers.SocialReferralStatusSerializer
        return serializers.SocialReferralSerializer

    def get_queryset(self):
        scopes = social_consent_scopes(self.request.user)
        readable = {pid for pid, codes in scopes.items() if "social.referrals.read" in codes}
        return models.SocialReferral.objects.filter(patient_id__in=readable).select_related(
            "patient__user", "author", "case"
        )

    def update(self, request, *args, **kwargs):
        referral = self.get_object()
        partial = kwargs.pop("partial", False)
        serializer = self.get_serializer(data=request.data, partial=partial)
        serializer.is_valid(raise_exception=True)
        data = serializer.validated_data
        _require_verified_professional(request.user)
        _assert_write_consent(request.user, referral.patient, "social.referrals.update")
        changed = []
        if "status" in data and data["status"] != referral.status:
            allowed = models.SocialReferral.TRANSITIONS.get(referral.status, [])
            if data["status"] not in allowed:
                raise ValidationError({
                    "status": (
                        f"Cannot move a {referral.status} referral to "
                        f"{data['status']}. Allowed: {', '.join(allowed) or 'none'}."
                    )
                })
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
                action_code="social.referrals.update",
                resource_type="social_referral",
                resource_id=referral.pk,
                request=request,
                details={"referral_uid": str(referral.uid), "changed": changed},
            )
        return Response(serializers.SocialReferralSerializer(referral).data)
