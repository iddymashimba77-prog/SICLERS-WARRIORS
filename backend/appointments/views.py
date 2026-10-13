"""Clinic appointment API (§11).

    GET    /api/appointments/                    own + consented + assigned
    POST   /api/appointments/                    book (self or consented proxy)
    GET    /api/appointments/{uid}/              detail
    PATCH  /api/appointments/{uid}/              edit time/reminders (owner or clinic)
    POST   /api/appointments/{uid}/status/       transition (cancel / confirm / complete)
    DELETE /api/appointments/{uid}/              cancel (soft — history is retained)

Every transition is audited (`appointments.*` action codes) and the row is never
hard-deleted: clinical history must survive a mistaken booking (§8 history).
"""

from django.db import transaction
from django.utils import timezone
from drf_spectacular.utils import OpenApiTypes, extend_schema
from rest_framework import status as http_status
from rest_framework.exceptions import ValidationError
from rest_framework.generics import ListCreateAPIView, RetrieveUpdateAPIView
from rest_framework.response import Response
from rest_framework.views import APIView

from audit.services import record_audit
from core.pagination import CorePageNumberPagination
from .models import PATIENT_TRANSITIONS, ClinicAppointment
from .permissions import (
    APPOINTMENT_MANAGE,
    APPOINTMENT_READ,
    APPOINTMENT_WRITE_OWN,
    AppointmentAccess,
    appointment_manage_permissions,
    appointment_permissions,
    patient_profile_for,
)
from .serializers import (
    AppointmentClinicalSerializer,
    AppointmentSerializer,
    AppointmentStatusSerializer,
)

# Statuses a patient may set themselves. Everything else is clinic-side.
PATIENT_SETTABLE = {"CANCELLED", "RESCHEDULED"}


class AppointmentListCreateView(AppointmentAccess, ListCreateAPIView):
    """GET/POST /appointments — scoped list, or book a new visit."""

    serializer_class = AppointmentSerializer
    permission_classes = appointment_permissions
    pagination_class = CorePageNumberPagination
    queryset = ClinicAppointment.objects.select_related("facility", "doctor__user", "patient")

    def get_serializer_class(self):
        if self.request.method == "GET" and self.request.user.has_perm_code(APPOINTMENT_MANAGE):
            return AppointmentClinicalSerializer
        return super().get_serializer_class()

    def get_queryset(self):
        qs = super().get_queryset()
        # Directory-level management permission widens to everything, then the
        # usual status filter applies.
        if self.request.user.has_perm_code(APPOINTMENT_MANAGE):
            params = self.request.query_params
            wanted = (params.get("status") or "").strip().upper()
            if wanted:
                qs = qs.filter(status=wanted)
            return qs
        qs = qs.filter(patient_id__in=self.accessible_patient_ids())
        params = self.request.query_params
        wanted = (params.get("status") or "").strip().upper()
        if wanted:
            qs = qs.filter(status=wanted)
        upcoming_only = (params.get("upcoming") or "").strip().lower() in ("1", "true", "yes")
        if upcoming_only:
            qs = qs.filter(scheduled_at__gte=timezone.now()).exclude(
                status__in=["CANCELLED", "COMPLETED", "NO_SHOW"]
            )
        return qs

    def accessible_patient_ids(self):
        from .permissions import accessible_patient_users

        return accessible_patient_users(self.request.user)

    def create(self, request, *args, **kwargs):
        if not (request.user.has_perm_code(APPOINTMENT_WRITE_OWN)
                or patient_profile_for(request.user) is not None
                or request.user.has_perm_code(APPOINTMENT_MANAGE)):
            raise ValidationError(
                {"detail": "You are not eligible to book clinic appointments."}
            )
        serializer = self.get_serializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        # A proxy booking keeps `patient` server-side; the client cannot spoof it.
        target = self.resolve_target_patient(dict(request.data))
        with transaction.atomic():
            appointment = serializer.save(patient=target, created_by=request.user)
        record_audit(
            actor=request.user,
            action_code="appointments.create",
            resource_type="clinic_appointment",
            resource_id=appointment.pk,
            request=request,
            details={
                "scheduled_at": appointment.scheduled_at.isoformat(),
                "appointment_type": appointment.appointment_type,
                "on_behalf_of": target.uid.hex if hasattr(target, "uid") else str(target.id),
                "facility_uid": appointment.facility.uid.hex if appointment.facility else None,
            },
        )
        return Response(self.get_serializer(appointment).data, status=http_status.HTTP_201_CREATED)


class AppointmentDetailView(AppointmentAccess, RetrieveUpdateAPIView):
    """GET/PATCH /appointments/{uid} — detail or edit."""

    lookup_field = "uid"
    serializer_class = AppointmentSerializer
    permission_classes = appointment_permissions

    def get_queryset(self):
        return ClinicAppointment.objects.select_related(
            "facility", "doctor__user", "patient"
        ).filter(patient_id__in=self.accessible_patient_ids())

    def accessible_patient_ids(self):
        from .permissions import accessible_patient_users

        return accessible_patient_users(self.request.user)

    def get_serializer_class(self):
        user = self.request.user
        if user.has_perm_code(APPOINTMENT_MANAGE):
            return AppointmentClinicalSerializer
        uid = self.kwargs.get("uid")
        # The attending clinician sees the clinical note; everyone else does not.
        if uid and ClinicAppointment.objects.filter(
            uid=uid, doctor__user=user
        ).exists():
            return AppointmentClinicalSerializer
        return AppointmentSerializer

    def partial_update(self, request, *args, **kwargs):
        instance = self.get_object()
        self._appointment = instance
        self.assert_can_manage(instance)
        previous = instance.scheduled_at
        serializer = self.get_serializer(instance, data=request.data, partial=True)
        serializer.is_valid(raise_exception=True)
        if "status" in request.data:
            raise ValidationError(
                {"status": "Use the status endpoint to change an appointment status."}
            )
        with transaction.atomic():
            appointment = serializer.save()
            if previous != appointment.scheduled_at and appointment.status in ("CONFIRMED", "REQUESTED"):
                # Time moved: it needs re-confirmation by the clinic.
                appointment.status = "RESCHEDULED"
                appointment.save(update_fields=["status", "updated_at"])
        record_audit(
            actor=request.user,
            action_code="appointments.update",
            resource_type="clinic_appointment",
            resource_id=appointment.pk,
            request=request,
            details={
                "previous_scheduled_at": previous.isoformat(),
                "scheduled_at": appointment.scheduled_at.isoformat(),
                "status": appointment.status,
            },
        )
        return Response(self.get_serializer(appointment).data)

    def delete(self, request, *args, **kwargs):
        """Soft cancel — the row stays as history (§8 history, §24 audit)."""
        instance = self.get_object()
        self.assert_can_manage(instance)
        if instance.status in ("COMPLETED", "CANCELLED"):
            raise ValidationError({"detail": "This appointment is already closed."})
        reason = (request.data or {}).get("reason", "") if request.data else ""
        with transaction.atomic():
            instance.status = "CANCELLED"
            instance.cancelled_at = timezone.now()
            instance.cancellation_reason = reason[:1000]
            instance.save(update_fields=["status", "cancelled_at", "cancellation_reason", "updated_at"])
        record_audit(
            actor=request.user,
            action_code="appointments.cancel",
            resource_type="clinic_appointment",
            resource_id=instance.pk,
            request=request,
            details={"reason": reason[:500], "soft_delete": True},
        )
        return Response(self.get_serializer(instance).data, status=http_status.HTTP_200_OK)


class AppointmentStatusView(AppointmentAccess, APIView):
    """POST /appointments/{uid}/status — audited lifecycle transition."""

    permission_classes = appointment_permissions

    @extend_schema(
        request=AppointmentStatusSerializer,
        responses={200: OpenApiTypes.OBJECT},
    )
    def post(self, request, uid):
        appointment = ClinicAppointment.objects.select_related(
            "doctor__user", "patient", "facility"
        ).filter(uid=uid).first()
        if appointment is None:
            return Response(
                {"detail": "That appointment does not exist."},
                status=http_status.HTTP_404_NOT_FOUND,
            )
        is_clinic = request.user.has_perm_code(APPOINTMENT_MANAGE) or (
            appointment.doctor_id
            and appointment.doctor.user_id == request.user.id
        )
        if not (appointment.patient_id == request.user.id or is_clinic):
            self.assert_can_manage(appointment)
        payload = AppointmentStatusSerializer(data=request.data)
        payload.is_valid(raise_exception=True)
        target_status = payload.validated_data["status"]
        reason = payload.validated_data.get("reason", "")
        if not is_clinic and target_status not in PATIENT_SETTABLE:
            raise ValidationError({"status": "You cannot set that status yourself."})
        if target_status not in PATIENT_TRANSITIONS.get(appointment.status, set()) and not is_clinic:
            raise ValidationError(
                {"status": f"An appointment that is {appointment.status.replace('_', ' ').lower()} cannot be changed to {target_status.replace('_', ' ').lower()}."}
            )
        if target_status == "CANCELLED" and not is_clinic and not reason:
            raise ValidationError({"reason": "Tell us why you are cancelling so the clinic can help."})
        update_fields = ["status", "updated_at"]
        with transaction.atomic():
            appointment.status = target_status
            if target_status == "CANCELLED":
                appointment.cancelled_at = timezone.now()
                appointment.cancellation_reason = reason[:1000]
                update_fields += ["cancelled_at", "cancellation_reason"]
            if target_status == "COMPLETED":
                appointment.completed_at = timezone.now()
                update_fields.append("completed_at")
            if target_status == "RESCHEDULED" and payload.validated_data.get("scheduled_at"):
                appointment.scheduled_at = payload.validated_data["scheduled_at"]
                update_fields.append("scheduled_at")
            if appointment.follow_up_required and appointment.follow_up_status == "NOT_REQUIRED":
                appointment.follow_up_status = "PENDING"
                update_fields.append("follow_up_status")
            appointment.save(update_fields=update_fields)
        record_audit(
            actor=request.user,
            action_code=f"appointments.{target_status.lower()}",
            resource_type="clinic_appointment",
            resource_id=appointment.pk,
            request=request,
            details={"reason": reason[:500]},
        )
        serializer = (
            AppointmentClinicalSerializer(appointment) if is_clinic else AppointmentSerializer(appointment)
        )
        return Response(serializer.data, status=http_status.HTTP_200_OK)


class AppointmentReminderStateView(APIView):
    """GET /appointments/reminders/due — what the reminder dispatcher owes.

    Exposed so the reminder job is observable (and testable) without reaching
    into the database. Staff only.
    """

    permission_classes = appointment_manage_permissions

    @extend_schema(responses={200: OpenApiTypes.OBJECT})
    def get(self, request):
        now = timezone.now()
        due = []
        window = now + timezone.timedelta(days=14)
        qs = (
            ClinicAppointment.objects.filter(
                reminder_enabled=True,
                scheduled_at__gte=now,
                scheduled_at__lte=window,
            )
            .exclude(status__in=["CANCELLED", "COMPLETED", "NO_SHOW"])
            .select_related("patient", "facility")
        )
        for appointment in qs:
            slots = appointment.reminder_due(now)
            if slots:
                due.append(
                    {
                        "uid": appointment.uid.hex,
                        "patient_uid": appointment.patient.uid.hex,
                        "scheduled_at": appointment.scheduled_at.isoformat(),
                        "slots": [slot.isoformat() for slot in slots],
                        "channels": appointment.reminder_channels,
                    }
                )
        return Response(
            {"count": len(due), "reminders": due},
            status=http_status.HTTP_200_OK,
        )