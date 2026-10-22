"""Social-work workspace serializers.

``patient_uid`` is the *user* uid on input (the medical-records convention)
 and the same uid on output; case-owned rows carry the case uid so a client
can build a case detail screen without N+1 lookups.
"""
from rest_framework import serializers

from . import models


def _patient_name(patient) -> str:
    user = patient.user
    return (
        f"{getattr(user, 'first_name', '')} {getattr(user, 'last_name', '')}".strip()
        or "Warrior"
    )


class NeedsField(serializers.ListField):
    """Ordered, de-duplicated list of known social-need codes."""

    def to_internal_value(self, data):
        if not isinstance(data, list):
            raise serializers.ValidationError("Expected a list of need codes.")
        if not data:
            raise serializers.ValidationError("Select at least one need.")
        if len(data) > len(models.NEED_CODES):
            raise serializers.ValidationError("Too many needs selected.")
        seen = []
        for item in data:
            code = str(item)
            if code not in models.NEED_CODES:
                raise serializers.ValidationError(
                    f"Unknown need '{code}'. Allowed: " + ", ".join(models.NEED_CODES)
                )
            if code not in seen:
                seen.append(code)
        return seen


class SocialCaseSerializer(serializers.ModelSerializer):
    patient_uid = serializers.UUIDField(source="patient.user.uid", read_only=True)
    patient_name = serializers.SerializerMethodField()
    opened_by_uid = serializers.UUIDField(source="opened_by.uid", read_only=True)

    class Meta:
        model = models.SocialCase
        fields = [
            "uid", "patient_uid", "patient_name", "opened_by_uid",
            "title", "status", "opened_at", "closed_at", "linked_workflow",
            "created_at", "updated_at",
        ]
        read_only_fields = [
            "uid", "patient_uid", "patient_name", "opened_by_uid",
            "status", "opened_at", "closed_at", "created_at", "updated_at",
        ]

    def get_patient_name(self, obj) -> str:
        return _patient_name(obj.patient)


class SocialCaseCreateSerializer(serializers.Serializer):
    patient_uid = serializers.UUIDField()
    title = serializers.CharField(max_length=200)
    linked_workflow = serializers.CharField(
        required=False, allow_blank=True, default="",
        help_text="Pointer to an existing campaign/donation workflow (no money here).",
    )


class SocialCaseStatusSerializer(serializers.Serializer):
    """Case status transition — validated against the state machine."""

    status = serializers.ChoiceField(choices=models.SocialCase.STATUSES)


class CaseNoteSerializer(serializers.ModelSerializer):
    case_uid = serializers.UUIDField(source="case.uid", read_only=True)
    author_uid = serializers.UUIDField(source="author.uid", read_only=True)
    author_name = serializers.SerializerMethodField()

    class Meta:
        model = models.CaseNote
        fields = ["uid", "case_uid", "author_uid", "author_name", "note", "created_at"]
        read_only_fields = fields

    def get_author_name(self, obj) -> str:
        name = f"{obj.author.first_name} {obj.author.last_name}".strip()
        return name or "Social worker"


class CaseNoteCreateSerializer(serializers.Serializer):
    note = serializers.CharField()


class SocialNeedsAssessmentSerializer(serializers.ModelSerializer):
    patient_uid = serializers.UUIDField(source="patient.user.uid", read_only=True)
    patient_name = serializers.SerializerMethodField()
    author_uid = serializers.UUIDField(source="author.uid", read_only=True)

    class Meta:
        model = models.SocialNeedsAssessment
        fields = [
            "uid", "patient_uid", "patient_name", "author_uid",
            "needs", "observations", "follow_up_at", "assessed_at", "created_at",
        ]
        read_only_fields = fields

    def get_patient_name(self, obj) -> str:
        return _patient_name(obj.patient)


class SocialNeedsAssessmentCreateSerializer(serializers.Serializer):
    patient_uid = serializers.UUIDField()
    needs = NeedsField()
    observations = serializers.CharField(required=False, allow_blank=True, default="")
    follow_up_at = serializers.DateTimeField(required=False, allow_null=True, default=None)
    assessed_at = serializers.DateTimeField(required=False)


class SocialReferralSerializer(serializers.ModelSerializer):
    patient_uid = serializers.UUIDField(source="patient.user.uid", read_only=True)
    patient_name = serializers.SerializerMethodField()
    case_uid = serializers.UUIDField(source="case.uid", read_only=True, default=None)
    author_uid = serializers.UUIDField(source="author.uid", read_only=True)

    class Meta:
        model = models.SocialReferral
        fields = [
            "uid", "patient_uid", "patient_name", "case_uid", "author_uid",
            "destination", "reason", "urgency", "status",
            "responsible_person", "follow_up_at", "created_at", "updated_at",
        ]
        read_only_fields = [
            "uid", "patient_uid", "patient_name", "case_uid", "author_uid",
            "status", "created_at", "updated_at",
        ]

    def get_patient_name(self, obj) -> str:
        return _patient_name(obj.patient)


class SocialReferralCreateSerializer(serializers.Serializer):
    patient_uid = serializers.UUIDField()
    case_uid = serializers.UUIDField(required=False, allow_null=True, default=None)
    destination = serializers.CharField(max_length=200)
    reason = serializers.CharField()
    urgency = serializers.ChoiceField(
        choices=models.SocialReferral.URGENCIES, default="ROUTINE",
    )
    responsible_person = serializers.CharField(
        required=False, allow_blank=True, default="",
    )
    follow_up_at = serializers.DateTimeField(required=False, allow_null=True, default=None)


class SocialReferralStatusSerializer(serializers.Serializer):
    status = serializers.ChoiceField(choices=models.SocialReferral.STATUSES)
    responsible_person = serializers.CharField(
        required=False, allow_blank=True, default="",
    )
    follow_up_at = serializers.DateTimeField(required=False, allow_null=True)


class SocialCaseloadItemSerializer(serializers.Serializer):
    patient_uid = serializers.UUIDField(source="user.uid", read_only=True)
    patient_name = serializers.SerializerMethodField()
    has_consent = serializers.SerializerMethodField()
    consent_scope = serializers.SerializerMethodField()
    open_case_count = serializers.SerializerMethodField()

    def get_patient_name(self, obj) -> str:
        return _patient_name(obj)

    def get_has_consent(self, obj) -> bool:
        return bool(self.context.get("social_scope", {}).get(obj.pk))

    def get_consent_scope(self, obj) -> list:
        return sorted(self.context.get("social_scope", {}).get(obj.pk, set()))

    def get_open_case_count(self, obj) -> int:
        return self.context.get("open_cases", {}).get(obj.pk, 0)
