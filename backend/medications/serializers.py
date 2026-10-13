"""Medication & health-tracking API serializers (§ approved §07/§08 endpoints).

Reuses the approved identity `accounts.User`; enforces ownership and approved
health vocabulary server-side (never trust Flutter validation alone, §13).
"""

import datetime
import uuid as _uuid

from django.contrib.auth import get_user_model
from django.utils import timezone
from rest_framework import serializers

from medications import models

User = get_user_model()


class SymptomTypeSerializer(serializers.ModelSerializer):
    class Meta:
        model = models.SymptomType
        fields = ["code", "name", "is_pain_related"]
        read_only_fields = fields


class MedicationScheduleSerializer(serializers.ModelSerializer):
    class Meta:
        model = models.MedicationSchedule
        fields = [
            "uid", "time_of_day", "days_of_week", "notes",
            "created_at", "updated_at",
        ]
        read_only_fields = ["uid", "created_at", "updated_at"]

    def validate_days_of_week(self, value):
        valid = set(models.MedicationSchedule.DAYS)
        bad = [d for d in (value or []) if d not in valid]
        if bad:
            raise serializers.ValidationError(
                f"Invalid day codes: {', '.join(bad)}. Allowed: {', '.join(valid)}."
            )
        return value


class MedicationSerializer(serializers.ModelSerializer):
    schedules = MedicationScheduleSerializer(many=True, read_only=True)
    prescribed_by = serializers.SlugRelatedField(
        slug_field="email", read_only=True, allow_null=True
    )
    patient = serializers.SlugRelatedField(
        slug_field="uid",
        queryset=User.objects.filter(
            user_roles__role__code="PATIENT", user_roles__is_active=True
        ).distinct(),
        write_only=True, required=False, allow_null=False,
    )

    class Meta:
        model = models.Medication
        fields = [
            "uid", "name", "generic_name", "strength", "dosage", "route",
            "frequency", "instructions", "start_date", "end_date",
            "prescribed_by", "is_active", "schedules", "created_at",
            "updated_at", "patient",
        ]
        read_only_fields = ["uid", "prescribed_by", "created_at", "updated_at"]

    def validate(self, attrs):
        errors = {}
        start = attrs.get("start_date") or getattr(self.instance, "start_date", None)
        end = attrs.get("end_date") or getattr(self.instance, "end_date", None)
        if start and end and end < start:
            errors["end_date"] = "end_date must be the same as or after start_date."
        # Instructions are patient-facing directions, so they are bounded and
        # plain text only.
        instructions = attrs.get("instructions", getattr(self.instance, "instructions", ""))
        if len(instructions) > 2000:
            errors["instructions"] = "Keep instructions under 2000 characters."
        if errors:
            raise serializers.ValidationError(errors)
        return attrs

    def validate_route(self, value):
        valid = {c[0] for c in models.Medication._meta.get_field("route").choices}
        if value not in valid:
            raise serializers.ValidationError(
                f"Invalid route. Allowed: {', '.join(sorted(valid))}."
            )
        return value


class MedicationEventSerializer(serializers.ModelSerializer):
    schedule = serializers.SlugRelatedField(
        slug_field="uid",
        queryset=models.MedicationSchedule.objects.none(),
    )
    idempotency_key = serializers.CharField(
        write_only=True, required=False, allow_blank=True, max_length=120,
    )

    class Meta:
        model = models.MedicationEvent
        fields = [
            "schedule", "status", "taken_at", "note",
            "idempotency_key", "created_at",
        ]
        read_only_fields = ["created_at"]

    def __init__(self, *args, medication=None, **kwargs):
        self.medication = medication
        super().__init__(*args, **kwargs)
        if medication is not None:
            self.fields["schedule"].queryset = medication.schedules.all()

    def validate(self, attrs):
        status_val = attrs.get("status")
        taken_at = attrs.get("taken_at")
        errors = {}
        if status_val == "TAKEN" and not taken_at:
            errors["taken_at"] = "taken_at is required when status is TAKEN."
        if status_val in ("MISSED", "SKIPPED", "SNOOZED") and taken_at:
            errors["taken_at"] = f"taken_at must be null when status is {status_val}."
        schedule = attrs.get("schedule")
        if schedule:
            if taken_at and schedule.medication.end_date:
                if taken_at.date() > schedule.medication.end_date:
                    errors["taken_at"] = "taken_at is after medication end_date."
        if errors:
            raise serializers.ValidationError(errors)
        return attrs


class DoseLogOutSerializer(serializers.ModelSerializer):
    """Read-only output for a medication event (no idempotency_key)."""
    schedule_uid = serializers.SerializerMethodField()

    class Meta:
        model = models.MedicationEvent
        fields = ["id", "schedule_uid", "status", "taken_at", "note", "created_at"]
        read_only_fields = fields

    def get_schedule_uid(self, obj):
        return str(obj.schedule.uid) if obj.schedule_id else None


class SymptomSerializer(serializers.ModelSerializer):
    symptom_type_code = serializers.SlugRelatedField(
        slug_field="code", source="symptom_type",
        queryset=models.SymptomType.objects.all(), required=False, allow_null=True,
    )

    class Meta:
        model = models.Symptom
        fields = [
            "uid", "symptom_type_code", "pain_level", "triggers",
            "duration_minutes", "notes", "recorded_at",
            "created_at", "updated_at",
        ]
        read_only_fields = ["uid", "created_at", "updated_at"]

    def validate(self, attrs):
        pain = attrs.get("pain_level")
        if pain is not None and not (0 <= pain <= 10):
            raise serializers.ValidationError(
                {"pain_level": "Must be an integer 0..10."}
            )
        recorded_at = attrs.get("recorded_at") or getattr(self.instance, "recorded_at", None)
        if recorded_at and recorded_at > timezone.now() + datetime.timedelta(hours=1):
            raise serializers.ValidationError(
                {"recorded_at": "Cannot be more than one hour in the future."}
            )
        triggers = attrs.get("triggers", [])
        if not isinstance(triggers, list):
            raise serializers.ValidationError(
                {"triggers": "Must be a list of strings."}
            )
        return attrs

    def validate_triggers(self, value):
        bad = [t for t in value if not isinstance(t, str)]
        if bad:
            raise serializers.ValidationError("Each trigger must be a string.")
        return value


class HealthTimelineEntrySerializer(serializers.ModelSerializer):
    class Meta:
        model = models.HealthTimelineEntry
        fields = [
            "event_type", "event_id", "occurred_at", "summary", "payload",
            "created_at",
        ]
        read_only_fields = fields