"""Psychology workspace serializers.

Read serializers expose identity (uid) but never file contents; write
serializers take ``patient_uid`` as the *user* uid — the same convention the
medical-records module uses (``Patient.objects.filter(user__uid=...)``).
"""
from rest_framework import serializers

from . import models


def _patient_name(patient) -> str:
    user = patient.user
    return (
        f"{getattr(user, 'first_name', '')} {getattr(user, 'last_name', '')}".strip()
        or "Warrior"
    )


class ConcernsField(serializers.ListField):
    """Ordered, de-duplicated list of known concern-domain codes."""

    def to_internal_value(self, data):
        if not isinstance(data, list):
            raise serializers.ValidationError("Expected a list of concern codes.")
        if not data:
            raise serializers.ValidationError("Select at least one concern.")
        if len(data) > len(models.CONCERN_CODES):
            raise serializers.ValidationError("Too many concerns selected.")
        seen = []
        for item in data:
            code = str(item)
            if code not in models.CONCERN_CODES:
                raise serializers.ValidationError(
                    f"Unknown concern '{code}'. Allowed: "
                    + ", ".join(models.CONCERN_CODES)
                )
            if code not in seen:
                seen.append(code)
        return seen


class PsychAssessmentSerializer(serializers.ModelSerializer):
    patient_uid = serializers.UUIDField(source="patient.user.uid", read_only=True)
    patient_name = serializers.SerializerMethodField()
    author_uid = serializers.UUIDField(source="author.uid", read_only=True)
    author_name = serializers.SerializerMethodField()

    class Meta:
        model = models.PsychAssessment
        fields = [
            "uid", "patient_uid", "patient_name", "author_uid", "author_name",
            "concerns", "impression", "risk_level", "notes",
            "assessed_at", "follow_up_at", "created_at",
        ]
        read_only_fields = fields

    def get_patient_name(self, obj) -> str:
        return _patient_name(obj.patient)

    def get_author_name(self, obj) -> str:
        name = (
            f"{obj.author.first_name} {obj.author.last_name}".strip()
        )
        return name or "Psychologist"


class PsychAssessmentCreateSerializer(serializers.Serializer):
    patient_uid = serializers.UUIDField()
    concerns = ConcernsField()
    impression = serializers.ChoiceField(
        choices=models.PsychAssessment.IMPRESSIONS, default="NONE",
    )
    risk_level = serializers.ChoiceField(
        choices=models.PsychAssessment.RISK_LEVELS, default="ROUTINE",
    )
    notes = serializers.CharField(required=False, allow_blank=True, default="")
    assessed_at = serializers.DateTimeField(required=False)
    follow_up_at = serializers.DateTimeField(required=False, allow_null=True, default=None)


class ProgressNoteSerializer(serializers.ModelSerializer):
    patient_uid = serializers.UUIDField(source="patient.user.uid", read_only=True)
    patient_name = serializers.SerializerMethodField()
    author_uid = serializers.UUIDField(source="author.uid", read_only=True)
    author_name = serializers.SerializerMethodField()

    class Meta:
        model = models.ProgressNote
        fields = [
            "uid", "patient_uid", "patient_name", "author_uid", "author_name",
            "note", "session_at", "follow_up_at", "created_at",
        ]
        read_only_fields = fields

    def get_patient_name(self, obj) -> str:
        return _patient_name(obj.patient)

    def get_author_name(self, obj) -> str:
        name = f"{obj.author.first_name} {obj.author.last_name}".strip()
        return name or "Psychologist"


class ProgressNoteCreateSerializer(serializers.Serializer):
    patient_uid = serializers.UUIDField()
    note = serializers.CharField()
    session_at = serializers.DateTimeField(required=False)
    follow_up_at = serializers.DateTimeField(required=False, allow_null=True, default=None)


class PsychologyReferralSerializer(serializers.ModelSerializer):
    patient_uid = serializers.UUIDField(source="patient.user.uid", read_only=True)
    patient_name = serializers.SerializerMethodField()
    author_uid = serializers.UUIDField(source="author.uid", read_only=True)

    class Meta:
        model = models.PsychologyReferral
        fields = [
            "uid", "patient_uid", "patient_name", "author_uid",
            "destination", "reason", "urgency", "status",
            "responsible_person", "follow_up_at", "created_at", "updated_at",
        ]
        read_only_fields = ["uid", "patient_uid", "patient_name", "author_uid", "status",
                            "created_at", "updated_at"]

    def get_patient_name(self, obj) -> str:
        return _patient_name(obj.patient)


class PsychologyReferralCreateSerializer(serializers.Serializer):
    patient_uid = serializers.UUIDField()
    destination = serializers.CharField(max_length=200)
    reason = serializers.CharField()
    urgency = serializers.ChoiceField(
        choices=models.PsychologyReferral.URGENCIES, default="ROUTINE",
    )
    responsible_person = serializers.CharField(
        required=False, allow_blank=True, default="",
    )
    follow_up_at = serializers.DateTimeField(required=False, allow_null=True, default=None)


class PsychologyReferralStatusSerializer(serializers.Serializer):
    """Status transition for an existing referral (author or consented peer)."""

    status = serializers.ChoiceField(choices=models.PsychologyReferral.STATUSES)
    responsible_person = serializers.CharField(
        required=False, allow_blank=True, default="",
    )
    follow_up_at = serializers.DateTimeField(required=False, allow_null=True)


class CaseloadItemSerializer(serializers.Serializer):
    patient_uid = serializers.UUIDField(source="user.uid", read_only=True)
    patient_name = serializers.SerializerMethodField()
    has_consent = serializers.SerializerMethodField()
    consent_scope = serializers.SerializerMethodField()
    last_appointment_at = serializers.SerializerMethodField()
    next_appointment_at = serializers.SerializerMethodField()

    def get_patient_name(self, obj) -> str:
        return _patient_name(obj)

    def get_has_consent(self, obj) -> bool:
        scope = self.context.get("psych_scope", {}).get(obj.pk, set())
        return bool(scope)

    def get_consent_scope(self, obj) -> list:
        return sorted(self.context.get("psych_scope", {}).get(obj.pk, set()))

    def get_last_appointment_at(self, obj):
        return self.context.get("last_appointment", {}).get(obj.pk)

    def get_next_appointment_at(self, obj):
        return self.context.get("next_appointment", {}).get(obj.pk)
