"""Appointment serializers (§11).

Two shapes, deliberately:

* ``AppointmentSerializer`` — patient-facing. Carries the venue, the time, the
  reason and the reminder plan. ``notes`` is **not** included: clinical notes
  are not the patient's own record to read back.
* ``AppointmentClinicalSerializer`` — adds ``notes``/``status`` transitions for
  the clinic side only (see ``appointments.permissions``).
"""

from django.utils import timezone
from rest_framework import serializers

from doctors.models import Doctor
from facilities.models import Facility
from facilities.serializers import FacilitySerializer

from .models import (
    APPOINTMENT_STATUSES,
    APPOINTMENT_TYPES,
    FOLLOW_UP_STATUSES,
    ClinicAppointment,
)


def _normalise_time_list(value, field_name):
    """Validate a JSON list of ``HH:MM`` strings from a free-form client."""
    if value in (None, ""):
        return []
    if not isinstance(value, list):
        raise serializers.ValidationError({field_name: "Expected a list of times."})
    cleaned = []
    for item in value:
        text = str(item).strip()
        parts = text.split(":")
        if len(parts) not in (2, 3):
            raise serializers.ValidationError({field_name: f"'{text}' is not a valid time."})
        try:
            hour, minute = int(parts[0]), int(parts[1])
            second = int(parts[2]) if len(parts) == 3 else 0
        except (TypeError, ValueError):
            raise serializers.ValidationError({field_name: f"'{text}' is not a valid time."})
        if not (0 <= hour <= 23 and 0 <= minute <= 59 and 0 <= second <= 59):
            raise serializers.ValidationError({field_name: f"'{text}' is not a valid time."})
        cleaned.append(f"{hour:02d}:{minute:02d}")
    return cleaned


def _normalise_day_list(value, field_name):
    if value in (None, ""):
        return []
    if not isinstance(value, list):
        raise serializers.ValidationError({field_name: "Expected a list of days before."})
    cleaned = []
    for item in value:
        try:
            days = int(item)
        except (TypeError, ValueError):
            raise serializers.ValidationError({field_name: f"'{item}' is not a whole number."})
        if not 0 <= days <= 30:
            raise serializers.ValidationError({field_name: "Days before must be between 0 and 30."})
        cleaned.append(days)
    return sorted(set(cleaned))


class AppointmentSerializer(serializers.ModelSerializer):
    """Patient-facing view of an appointment.

    Relations travel by public ``uid`` in and a nested read-only projection out
    (the project-wide convention — internal primary keys are never part of a
    client contract, matching ``blood_network``).
    """

    facility = FacilitySerializer(read_only=True)
    facility_uid = serializers.UUIDField(write_only=True, required=False, allow_null=True)
    doctor_uid = serializers.UUIDField(write_only=True, required=False, allow_null=True)
    doctor_name = serializers.SerializerMethodField()
    facility_name = serializers.SerializerMethodField()
    facility_region = serializers.SerializerMethodField()
    facility_city = serializers.SerializerMethodField()
    patient_uid = serializers.UUIDField(source="patient.uid", read_only=True)
    booked_by_role = serializers.SerializerMethodField()
    is_past = serializers.SerializerMethodField()

    class Meta:
        model = ClinicAppointment
        fields = [
            "uid", "patient_uid", "facility", "facility_uid",
            "facility_name", "facility_region", "facility_city",
            "doctor_uid", "doctor_name", "appointment_type", "status",
            "scheduled_at", "duration_minutes", "reason", "follow_up_required",
            "follow_up_due_on", "follow_up_status", "reminder_enabled",
            "reminder_days_before", "reminder_times", "reminder_channels",
            "reminders_sent", "cancellation_reason", "booked_by_role", "is_past",
            "created_at", "updated_at",
        ]
        read_only_fields = [
            "uid", "status", "follow_up_status", "reminders_sent",
            "cancellation_reason", "created_at", "updated_at",
        ]

    def validate_facility_uid(self, value):
        """A clinic must be a *verified* facility — same gate as blood venues."""
        if value is None:
            return value
        if not Facility.objects.filter(uid=value, is_verified=True).exists():
            raise serializers.ValidationError("Choose a verified clinic or hospital.")
        return value

    def validate_doctor_uid(self, value):
        if value is None:
            return value
        if not Doctor.objects.filter(user__uid=value).exists():
            raise serializers.ValidationError("That clinician account does not exist.")
        return value

    def get_facility_name(self, obj) -> str:
        return obj.facility.name if obj.facility else None

    def get_facility_region(self, obj) -> str:
        return obj.facility.region if obj.facility else None

    def get_facility_city(self, obj) -> str:
        return obj.facility.city if obj.facility else None

    def get_doctor_name(self, obj) -> str:
        doctor = getattr(obj, "doctor", None)
        if doctor is None:
            return None
        user = getattr(doctor, "user", None)
        full_name = (user.get_full_name() or "").strip() if user else ""
        return full_name or (user.username if user else None)

    def get_booked_by_role(self, obj) -> str:
        user = getattr(obj, "created_by", None)
        if user is None:
            return None
        active = user.get_active_role_code() if hasattr(user, "get_active_role_code") else None
        return active or (user.primary_role if hasattr(user, "primary_role") else None)

    def get_is_past(self, obj) -> bool:
        return obj.scheduled_at < timezone.now()

    # --- validation ------------------------------------------------------
    def validate_scheduled_at(self, value):
        if value < timezone.now() - timezone.timedelta(minutes=5):
            raise serializers.ValidationError("Choose a date and time in the future.")
        return value

    def validate_reminder_times(self, value):
        return _normalise_time_list(value, "reminder_times")

    def validate_reminder_days_before(self, value):
        return _normalise_day_list(value, "reminder_days_before")

    def validate_reminder_channels(self, value):
        if value in (None, ""):
            return []
        if not isinstance(value, list):
            raise serializers.ValidationError({"reminder_channels": "Expected a list of channels."})
        allowed = {"in_app", "push", "sms", "email", "whatsapp"}
        cleaned = []
        for item in value:
            channel = str(item).strip().lower()
            if channel not in allowed:
                raise serializers.ValidationError(
                    {"reminder_channels": f"'{item}' is not a supported channel."}
                )
            cleaned.append(channel)
        return cleaned

    def validate(self, attrs):
        reminder_enabled = attrs.get("reminder_enabled", getattr(self.instance, "reminder_enabled", True))
        if reminder_enabled:
            times = attrs.get("reminder_times", getattr(self.instance, "reminder_times", None))
            days = attrs.get(
                "reminder_days_before", getattr(self.instance, "reminder_days_before", None)
            )
            if not times:
                raise serializers.ValidationError(
                    {"reminder_times": "Add at least one reminder time or turn reminders off."}
                )
            if not days:
                raise serializers.ValidationError(
                    {"reminder_days_before": "Choose how many days before to remind."}
                )
        follow_up_required = attrs.get(
            "follow_up_required", getattr(self.instance, "follow_up_required", False)
        )
        due = attrs.get("follow_up_due_on", getattr(self.instance, "follow_up_due_on", None))
        if follow_up_required and not due:
            raise serializers.ValidationError(
                {"follow_up_due_on": "A follow-up date is required when a follow-up is needed."}
            )
        # Swap client-supplied uids for the real relations here, so every
        # write path (create and patch) resolves them identically.
        facility_uid = attrs.pop("facility_uid", None)
        if facility_uid is not None:
            attrs["facility"] = Facility.objects.get(uid=facility_uid)
        doctor_uid = attrs.pop("doctor_uid", None)
        if doctor_uid is not None:
            attrs["doctor"] = Doctor.objects.get(user__uid=doctor_uid)
        return attrs


class AppointmentClinicalSerializer(AppointmentSerializer):
    """Clinic-side view — adds the clinical note that patients never receive."""

    notes = serializers.CharField(required=False, allow_blank=True)

    class Meta(AppointmentSerializer.Meta):
        fields = AppointmentSerializer.Meta.fields + ["notes"]
        read_only_fields = [f for f in AppointmentSerializer.Meta.read_only_fields if f != "status"]

    def validate_status(self, value):
        allowed = {s for s, _ in APPOINTMENT_STATUSES}
        if value not in allowed:
            raise serializers.ValidationError("Unsupported appointment status.")
        return value

    def validate_follow_up_status(self, value):
        if value not in {s for s, _ in FOLLOW_UP_STATUSES}:
            raise serializers.ValidationError("Unsupported follow-up status.")
        return value

    def validate_appointment_type(self, value):
        if value not in {t for t, _ in APPOINTMENT_TYPES}:
            raise serializers.ValidationError("Unsupported appointment type.")
        return value


class AppointmentStatusSerializer(serializers.Serializer):
    """Small payload for the status transition endpoint."""

    status = serializers.ChoiceField(choices=[s for s, _ in APPOINTMENT_STATUSES])
    reason = serializers.CharField(required=False, allow_blank=True, max_length=1000)
    scheduled_at = serializers.DateTimeField(required=False)