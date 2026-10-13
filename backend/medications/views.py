"""Medication & health-tracking API views (Stage 4.6).

Ownership model ("deny by default", Stage 4.4 §18/§19, approved §07):
  * A patient manages ONLY their own medications/schedules/events/symptoms.
  * Querysets are always filtered by ``patient=request.user``; a foreign uid
    yields 404 (never 403, never a 200 with another user's data) — IDOR-safe.
  * Role is NOT a backdoor: a DOCTOR/CAREGIVER/ADMIN never falls through to
    a patient-owned queryset. Cross-patient access is via the approved
    consent+relationship gates (C2/C3) implemented in the consent stage, later.

Server-side validation only (§13): the API never trusts Flutter validation.
Pain 0..10, route vocabulary, schedule days_of_week, status/taken_at pairing
are all enforced here.

Audit: create/update/delete events append a ``SecurityEvent`` (event_type
only, never payload — §21/§24).
"""

import datetime
import logging

from django.db import transaction
from django.utils import timezone
from drf_spectacular.utils import OpenApiParameter, OpenApiTypes, extend_schema
from rest_framework import mixins, status as http_status, viewsets
from rest_framework.decorators import action
from rest_framework.exceptions import (
    APIException, NotFound, PermissionDenied, ValidationError,
)
from rest_framework.parsers import JSONParser
from rest_framework.response import Response

from accounts.models import SecurityEvent
from accounts.permissions import (
    IsAuthenticatedRespectStatus, IsPatient,
    MedicationAccess, SymptomAccess, _is_prescriber,
)
from core.pagination import CorePageNumberPagination
from medications import models, serializers, services

logger = logging.getLogger(__name__)


def _audit_event(user, event_type):
    try:
        SecurityEvent.objects.create(
            user=user, event_type=event_type,
            detail={"timestamp": timezone.now().isoformat()},
        )
    except Exception:
        logger.exception("SecurityEvent write failed (non-blocking): %s", event_type)


class IdempotencyConflict(APIException):
    """Approved §30: duplicate Idempotency-Key → 409, not a double record."""

    status_code = http_status.HTTP_409_CONFLICT
    default_detail = "Duplicate idempotency key."
    default_code = "idempotency_conflict"


def _patient_scope(request):
    """Return the owning patient (authenticated, non-anonymous, eligible).

    Eligibility mirrors ``IsAuthenticatedRespectStatus`` (ACTIVE /
    PENDING_VERIFICATION): a freshly registered patient may track their OWN
    health data before final verification (self-entered records only).
    Professional cross-patient access (doctor/caregiver) stays behind the
    verified + consent/relationship gates (C2/C3) — never here.
    """
    user = getattr(request, "user", None)
    if not (user and user.is_authenticated):
        raise PermissionDenied("Authentication required.")
    if not user.is_patient:
        raise PermissionDenied("Patient identity is required for health data.")
    if user.account_status not in ("ACTIVE", "PENDING_VERIFICATION"):
        raise PermissionDenied("Account not eligible for health data.")
    return user


def _health_subject(request, medication=None):
    """Resolve the owning patient a health write applies to (C2/C3 interim).

    A patient may write to their OWN rows. A verified prescriber may write to
    a target patient's rows (the medication's owner). Anyone else is denied.
    """
    user = getattr(request, "user", None)
    if not (user and user.is_authenticated):
        raise PermissionDenied("Authentication required.")
    if user.account_status not in ("ACTIVE", "PENDING_VERIFICATION"):
        raise PermissionDenied("Account not eligible for health data.")
    if user.is_patient:
        return user
    if _is_prescriber(user):
        if medication is None:
            raise PermissionDenied("Patient identity is required here.")
        return medication.patient
    raise PermissionDenied("Patient identity is required for health data.")


@extend_schema(
    parameters=[
        OpenApiParameter(
            name="schedule_uid",
            type=OpenApiTypes.STR,
            location=OpenApiParameter.PATH,
            description="Public identifier of the medication schedule slot.",
        )
    ]
)
class MedicationViewSet(
    mixins.ListModelMixin,
    mixins.CreateModelMixin,
    mixins.RetrieveModelMixin,
    mixins.UpdateModelMixin,
    mixins.DestroyModelMixin,
    viewsets.GenericViewSet,
):
    """/api/medications — patient owns own rows; verified prescribers author them.

    Permission model (Stage 4.6 dispose + doctor cycle):
      * Patient:  manage only their OWN medications — foreign uid → 404.
      * Doctor:   a verified prescriber may list/create/update/delete a
                  patient's medications via ``?patient=<uid>`` (and their own
                  prescribed set when no param is given). Writes set
                  ``prescribed_by=request.user`` so the profile shows its
                  author. Cross-patient 404/403 semantics never leak a row.
    Destroy is a soft-delete (sets ``deleted_at`` / ``is_active=False``). Dose
    logging stays patient-only.
    """

    lookup_field = "uid"
    serializer_class = serializers.MedicationSerializer
    permission_classes = [IsAuthenticatedRespectStatus, MedicationAccess]
    parser_classes = [JSONParser]
    pagination_class = CorePageNumberPagination

    def get_queryset(self):
        user = self.request.user
        if not (user and user.is_authenticated):
            return models.Medication.objects.none()
        if user.is_patient:
            return models.Medication.objects.filter(
                patient=user, deleted_at__isnull=True
            )
        if _is_prescriber(user):
            qs = models.Medication.objects.filter(deleted_at__isnull=True)
            patient_uid = self.request.query_params.get("patient")
            if patient_uid:
                qs = qs.filter(patient__uid=patient_uid)
            else:
                qs = qs.filter(prescribed_by=user)
            return qs
        return models.Medication.objects.none()

    @transaction.atomic
    def perform_create(self, serializer):
        user = self.request.user
        if user.is_patient:
            patient = user
            med = serializer.save(patient=patient)
        elif _is_prescriber(user):
            patient = serializer.validated_data.pop("patient", None)
            if patient is None:
                raise ValidationError(
                    {"patient": "A registered patient is required for a prescription."}
                )
            med = serializer.save(patient=patient, prescribed_by=user)
        else:
            raise PermissionDenied(
                "Only a patient or a verified prescriber may manage medications."
            )
        services.record_timeline(
            patient=patient, event_type="MED_STARTED", event_id=med.uid,
            occurred_at=med.created_at,
            summary=f"Medication started: {med.name}",
            payload={"medication_uid": str(med.uid), "name": med.name},
        )
        _audit_event(user, "MEDICATION_CREATED")

    @transaction.atomic
    def perform_update(self, serializer):
        user = self.request.user
        med = self.get_object()
        if user.is_patient:
            patient = user
        elif _is_prescriber(user):
            patient = med.patient
        else:
            raise PermissionDenied(
                "Only a patient or a verified prescriber may manage medications."
            )
        serializer.validated_data.pop("patient", None)
        was_active = med.is_active
        med = serializer.save()
        if was_active and not med.is_active:
            services.record_timeline(
                patient=patient, event_type="MED_STOPPED", event_id=med.uid,
                occurred_at=timezone.now(),
                summary=f"Medication deactivated: {med.name}",
                payload={"medication_uid": str(med.uid), "name": med.name},
            )
        _audit_event(user, "MEDICATION_UPDATED")

    def destroy(self, request, *args, **kwargs):
        """Soft-delete: set ``deleted_at`` and ``is_active=False``."""
        user = request.user
        med = self.get_object()
        if user.is_patient:
            patient = user
        elif _is_prescriber(user):
            patient = med.patient
        else:
            raise PermissionDenied(
                "Only a patient or a verified prescriber may manage medications."
            )
        now = timezone.now()
        models.Medication.objects.filter(pk=med.pk).update(
            deleted_at=now, is_active=False, updated_at=now,
        )
        services.record_timeline(
            patient=patient, event_type="MED_STOPPED", event_id=med.uid,
            occurred_at=now,
            summary=f"Medication stopped: {med.name}",
            payload={"medication_uid": str(med.uid), "name": med.name},
        )
        _audit_event(user, "MEDICATION_DEACTIVATED")
        return Response(status=http_status.HTTP_204_NO_CONTENT)

    @action(detail=True, methods=["get", "post"], url_path="schedule")
    def schedule(self, request, uid=None):
        """GET  /medications/{uid}/schedule  — list schedule slots (medications.view)
        POST /medications/{uid}/schedule      — create new schedule  (medications.update)
        """
        medication = self.get_object()
        if request.method == "GET":
            page = self.paginate_queryset(medication.schedules.all())
            data = serializers.MedicationScheduleSerializer(
                page if page is not None else medication.schedules.all(), many=True
            ).data
            return self.get_paginated_response(data) if page is not None else Response(
                {"data": data, "meta": {}}
            )
        _health_subject(request, medication)
        data = request.data.copy()
        data["medication"] = medication.pk
        srz = serializers.MedicationScheduleSerializer(data=data)
        srz.is_valid(raise_exception=True)
        srz.save(medication=medication)
        return Response(srz.data, status=http_status.HTTP_201_CREATED)

    @action(detail=True, methods=["patch", "delete"],
            url_path=r"schedule/(?P<schedule_uid>[^/.]+)")
    def schedule_detail(self, request, uid=None, schedule_uid=None):
        """PATCH/DELETE /medications/{uid}/schedule/{schedule_uid}."""
        medication = self.get_object()
        owner = _health_subject(request, medication)
        try:
            sched = medication.schedules.get(uid=schedule_uid)
        except models.MedicationSchedule.DoesNotExist:
            raise NotFound("Schedule not found.")
        if request.method == "PATCH":
            srz = serializers.MedicationScheduleSerializer(
                sched, data=request.data, partial=True
            )
            srz.is_valid(raise_exception=True)
            srz.save()
            return Response(srz.data)
        services.record_timeline(
            patient=owner, event_type="MED_STOPPED", event_id=medication.uid,
            occurred_at=timezone.now(),
            summary=f"Schedule removed: {sched.time_of_day:%H:%M} {','.join(sched.days_of_week or [])}",
            payload={"medication_uid": str(medication.uid), "schedule_uid": str(sched.uid)},
        )
        sched.delete()
        return Response(status=http_status.HTTP_204_NO_CONTENT)

    @action(detail=True, methods=["post"], url_path="log-dose")
    def log_dose(self, request, uid=None):
        """POST /medications/{uid}/log-dose — record dose outcome.

        Idempotency (approved §30): read ``Idempotency-Key`` header first,
        fall back to ``idempotency_key`` body field. Duplicate key → 409.
        """
        medication = self.get_object()
        owner = _patient_scope(request)
        data = request.data.copy()
        data.setdefault("idempotency_key", request.headers.get("Idempotency-Key", ""))
        srz = serializers.MedicationEventSerializer(
            data=data, medication=medication, context={"request": request}
        )
        srz.is_valid(raise_exception=True)
        key = srz.validated_data.get("idempotency_key")
        if key and models.MedicationEvent.objects.filter(
            patient=owner, idempotency_key=key
        ).exists():
            raise IdempotencyConflict({"idempotency_key": "Duplicate idempotency key."})
        with transaction.atomic():
            try:
                event = srz.save(patient=owner)
            except Exception as exc:
                if "UNIQUE" in str(exc) and "idempotency_key" in str(exc):
                    raise IdempotencyConflict(
                        {"idempotency_key": "Duplicate idempotency key."}
                    )
                raise
        status_val = event.status
        summary_map = {
            "TAKEN": "Dose taken",
            "MISSED": "Dose missed",
            "SKIPPED": "Dose skipped",
            "SNOOZED": "Dose snoozed",
        }
        services.record_timeline(
            patient=owner,
            event_type=f"DOSE_{status_val}",
            event_id=event.id,
            occurred_at=event.created_at,
            summary=f"{summary_map.get(status_val, 'Dose recorded')}: {medication.name}",
            payload={
                "medication_uid": str(medication.uid),
                "status": status_val,
                "taken_at": event.taken_at.isoformat() if event.taken_at else None,
            },
        )
        _audit_event(owner, "DOSE_LOGGED")
        out = serializers.DoseLogOutSerializer(event)
        return Response(out.data, status=http_status.HTTP_201_CREATED)

    @action(detail=True, methods=["get"], url_path="events")
    def events(self, request, uid=None):
        """GET /medications/{uid}/events — paginated dose history."""
        medication = self.get_object()
        page = self.paginate_queryset(
            models.MedicationEvent.objects.filter(schedule__medication=medication)
            .order_by("-created_at")
        )
        rows = page if page is not None else medication.events.all()[:0]
        data = serializers.DoseLogOutSerializer(rows, many=True).data
        return self.get_paginated_response(data) if page is not None else Response(
            {"data": data, "meta": {}}
        )

    @action(detail=False, methods=["get"], url_path="stats")
    def stats(self, request):
        """GET /medications/stats — approved FR-MED-006."""
        owner = _patient_scope(request)
        return Response(services.adherence_stats(owner))


class SymptomViewSet(
    mixins.ListModelMixin,
    mixins.CreateModelMixin,
    viewsets.GenericViewSet,
):
    """/api/symptoms — append-only pain/symptom records.

    Patient: own records only (create via symptoms.create, list via symptoms.view).
    Verified prescriber: READ access to a patient's symptom log
    (``?patient=<uid>``), useful to the doctor alongside the medication
    profile. Prescribers can never create a symptom record on a patient's
    behalf. No update/delete (no approved symptoms.update/delete codes).
    """

    lookup_field = "uid"
    serializer_class = serializers.SymptomSerializer
    permission_classes = [IsAuthenticatedRespectStatus, SymptomAccess]
    parser_classes = [JSONParser]
    pagination_class = CorePageNumberPagination

    def get_queryset(self):
        user = self.request.user
        if not (user and user.is_authenticated):
            return models.Symptom.objects.none()
        if user.is_patient:
            return models.Symptom.objects.filter(patient=user).select_related("symptom_type")
        if _is_prescriber(user):
            qs = models.Symptom.objects.select_related("symptom_type")
            patient_uid = self.request.query_params.get("patient")
            if patient_uid:
                qs = qs.filter(patient__uid=patient_uid)
            else:
                qs = qs.filter(patient__medications__prescribed_by=user)
            return qs.distinct()
        return models.Symptom.objects.none()

    @transaction.atomic
    def perform_create(self, serializer):
        owner = _patient_scope(request=self.request)
        sym = serializer.save(patient=owner)
        st_code = sym.symptom_type.code if sym.symptom_type else "UNKNOWN"
        services.record_timeline(
            patient=owner, event_type="SYMPTOM_RECORDED", event_id=sym.uid,
            occurred_at=sym.recorded_at,
            summary=f"Symptom recorded: {st_code}",
            payload={
                "symptom_uid": str(sym.uid),
                "type_code": st_code,
                "pain_level": sym.pain_level,
            },
        )
        if sym.pain_level is not None:
            services.record_timeline(
                patient=owner, event_type="PAIN_RECORDED", event_id=sym.uid,
                occurred_at=sym.recorded_at,
                summary=f"Pain level: {sym.pain_level}/10",
                payload={"pain_level": sym.pain_level, "symptom_uid": str(sym.uid)},
            )
        _audit_event(owner, "SYMPTOM_RECORDED")


class SymptomTypeViewSet(mixins.ListModelMixin, viewsets.GenericViewSet):
    """/api/symptom-types — approved read-only vocabulary (§ §09 no invention)."""

    serializer_class = serializers.SymptomTypeSerializer
    permission_classes = [IsAuthenticatedRespectStatus]
    pagination_class = None
    queryset = models.SymptomType.objects.all()


class HealthTimelineViewSet(mixins.ListModelMixin, viewsets.GenericViewSet):
    """/api/health-timeline — chronological projection, patient-owned, read-only."""

    serializer_class = serializers.HealthTimelineEntrySerializer
    permission_classes = [IsAuthenticatedRespectStatus, IsPatient]
    pagination_class = CorePageNumberPagination

    def get_queryset(self):
        user = self.request.user
        if not (user and user.is_authenticated):
            return models.HealthTimelineEntry.objects.none()
        return models.HealthTimelineEntry.objects.filter(patient=user)


class PatientDashboardView(viewsets.ViewSet):
    """GET /patients/me/dashboard — approved FR-MED-007."""

    permission_classes = [IsAuthenticatedRespectStatus, IsPatient]
    parser_classes = [JSONParser]
    pagination_class = None

    @extend_schema(responses={200: OpenApiTypes.OBJECT})
    def list(self, request):
        owner = _patient_scope(request)
        return Response(services.dashboard(owner))
