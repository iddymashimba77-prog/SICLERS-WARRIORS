"""Chat serializers (Stage 4.10).

Message bodies are sanitized on the way in and masked (tombstoned) once
deleted. Participant projection is uid + display name only; no email, phone,
roles or medical data crosses the chat boundary.
"""

from rest_framework import serializers

from . import models
from community.sanitizers import sanitize_html


def display_name(user) -> str:
    if user is None:
        return "Member"
    name = (getattr(user, "first_name", "") or "").strip()
    return name or "Member"


class UserBriefSerializer(serializers.Serializer):
    uid = serializers.UUIDField(read_only=True)
    display_name = serializers.SerializerMethodField()

    class Meta:
        ref_name = "DoctorUserBrief"

    def get_display_name(self, obj) -> str:
        return display_name(obj)


class ParticipantSerializer(serializers.ModelSerializer):
    user = UserBriefSerializer(read_only=True)

    class Meta:
        model = models.ConversationParticipant
        fields = ["user", "role_in_chat", "status", "joined_at"]
        read_only_fields = fields


class ConversationSerializer(serializers.ModelSerializer):
    created_by = UserBriefSerializer(read_only=True)
    participants = ParticipantSerializer(many=True, read_only=True)
    unread_count = serializers.SerializerMethodField()

    class Meta:
        model = models.Conversation
        fields = [
            "uid", "type", "status", "created_by", "participants",
            "last_message_at", "unread_count", "created_at", "updated_at",
        ]
        read_only_fields = fields

    def get_unread_count(self, obj) -> int:
        count = getattr(obj, "unread_count", None)
        if count is not None:
            return count
        request = self.context.get("request")
        if not request:
            return 0
        return (
            obj.messages.filter(deleted_at__isnull=True)
            .exclude(sender=request.user)
            .exclude(status="READ")
            .count()
        )


class ConversationCreateSerializer(serializers.Serializer):
    participant_uid = serializers.UUIDField()
    type = serializers.ChoiceField(choices=["DOCTOR_PATIENT"], default="DOCTOR_PATIENT")


class MessageSerializer(serializers.ModelSerializer):
    sender = UserBriefSerializer(read_only=True)
    conversation_uid = serializers.UUIDField(source="conversation.uid", read_only=True)
    deleted = serializers.SerializerMethodField()
    is_mine = serializers.SerializerMethodField()

    class Meta:
        model = models.Message
        fields = [
            "uid", "conversation_uid", "sender", "content", "message_type",
            "status", "deleted", "is_mine", "created_at",
        ]
        read_only_fields = fields

    def get_deleted(self, obj) -> bool:
        return obj.deleted_at is not None

    def get_is_mine(self, obj) -> bool:
        request = self.context.get("request")
        return bool(request and request.user.is_authenticated and obj.sender_id == request.user.pk)

    def to_representation(self, instance):
        data = super().to_representation(instance)
        if instance.deleted_at is not None:
            data["content"] = ""
        return data


class MessageCreateSerializer(serializers.Serializer):
    content = serializers.CharField(max_length=10000)
    message_type = serializers.ChoiceField(choices=["TEXT"], default="TEXT")

    def validate_content(self, value):
        cleaned = sanitize_html(value, max_length=10000)
        if not cleaned.strip():
            raise serializers.ValidationError("Message cannot be empty.")
        return cleaned


class AddParticipantSerializer(serializers.Serializer):
    user_uid = serializers.UUIDField()
    role_in_chat = serializers.CharField(max_length=20, required=False, default="MEMBER")


# ---------------------------------------------------------------------------
# Doctor professional registry (AUTH-1; database-design §3.4)
# ---------------------------------------------------------------------------


class DoctorSelfSerializer(serializers.ModelSerializer):
    """Own professional profile — /doctors/me (doctors.self_manage, C5)."""

    facility_uid = serializers.UUIDField(source="facility.uid", read_only=True)
    uid = serializers.UUIDField(source="user.uid", read_only=True)

    class Meta:
        model = models.Doctor
        fields = [
            "uid", "professional_type", "license_number", "specialty",
            "registration_body", "facility_uid", "verification_status",
            "verified_at", "verification_expires_at", "rejection_reason",
            "is_active", "created_at", "updated_at",
        ]
        read_only_fields = [
            "uid", "professional_type", "verification_status", "verified_at",
            "verification_expires_at", "rejection_reason", "is_active",
            "created_at", "updated_at",
        ]

    def validate_specialty(self, value):
        if value and len(str(value).strip()) < 2:
            raise serializers.ValidationError("Provide a clinical specialty.")
        return value


class DoctorPublicSerializer(serializers.ModelSerializer):
    """Public registry subset — name/specialty/registration body, no contact
    data and no license number (data-classification: public non-PHI only)."""

    display_name = serializers.SerializerMethodField()
    facility = serializers.SerializerMethodField()
    uid = serializers.UUIDField(source="user.uid", read_only=True)

    class Meta:
        model = models.Doctor
        fields = [
            "uid", "professional_type", "display_name", "specialty",
            "registration_body", "facility", "verification_status",
        ]

    def get_display_name(self, obj) -> str:
        return display_name(obj.user)

    def get_facility(self, obj) -> str | None:
        return obj.facility.name if obj.facility_id else None


class DoctorAdminSerializer(DoctorSelfSerializer):
    """Verification queue / decision output — C6-gated (doctors.verify only)."""

    display_name = serializers.SerializerMethodField()
    email = serializers.EmailField(source="user.email", read_only=True)
    verification_documents = serializers.SerializerMethodField()

    class Meta:
        model = models.Doctor
        fields = DoctorSelfSerializer.Meta.fields + [
            "display_name", "email", "verification_documents",
        ]

    def get_display_name(self, obj) -> str:
        return display_name(obj.user)

    def get_verification_documents(self, obj) -> list:
        """Submission attachments for the reviewer: type/status/file name and the
        ``id`` to open through the audited admin document endpoint — never the
        file contents or the storage key."""
        from accounts.serializers import VerificationDocumentReviewSerializer

        docs = obj.user.verification_documents.order_by("created_at")
        return VerificationDocumentReviewSerializer(docs, many=True).data


class DoctorVerificationSubmitSerializer(serializers.Serializer):
    """POST /doctors/me/verification — submit documents (FR-DOC-002).

    Only submits wording/document references; verification decisions remain the
    exclusive job of a VO/ADM/SUP (doctors.verify). `file_url` is a secure-
    storage key, never a public URL (SD: verification_documents).
    """

    license_number = serializers.CharField(required=False, allow_blank=True, max_length=120)
    specialty = serializers.CharField(required=False, allow_blank=True, max_length=120)
    registration_body = serializers.CharField(required=False, allow_blank=True, max_length=200)
    facility_uid = serializers.UUIDField(required=False, allow_null=True)
    documents = serializers.ListField(child=serializers.DictField(), required=False, default=list)
    professional_type = serializers.ChoiceField(
        choices=models.Doctor.PROFESSIONAL_TYPE_CODES, required=False, default="DOCTOR",
        help_text=(
            "Which professional this applicant is. A claim only: it decides which "
            "documents and which role the officer checks, and it is never a "
            "privilege grant. Default DOCTOR."
        ),
    )


class DoctorVerifySerializer(serializers.Serializer):
    """POST /admin/doctors/{uid}/verify — approve/reject with reason (design.unified)."""

    approve = serializers.BooleanField()
    reason = serializers.CharField(required=False, allow_blank=True, max_length=1000)


class DoctorSuspendSerializer(serializers.Serializer):
    """POST /admin/doctors/{uid}/suspend — reason required (suspension)."""

    reason = serializers.CharField(max_length=1000)


class DoctorVerificationDecisionSerializer(serializers.ModelSerializer):
    """One immutable verification decision row (FR-DOC-006/007, C6).

    The `Doctor` row carries only the current status, so this is the only place
    a rejected-then-approved applicant still shows their earlier rejection and
    the reason given for it.
    """

    actor_uid = serializers.UUIDField(source="actor.uid", read_only=True)
    actor_name = serializers.SerializerMethodField()
    doctor_uid = serializers.UUIDField(source="doctor.user.uid", read_only=True)
    license_number = serializers.CharField(source="doctor.license_number", read_only=True)

    class Meta:
        model = models.DoctorVerificationDecision
        fields = [
            "uid", "doctor_uid", "license_number", "decision", "from_status",
            "to_status", "reason", "details", "actor_uid", "actor_name", "decided_at",
        ]
        read_only_fields = fields

    def get_actor_name(self, obj) -> str:
        if obj.actor is None:
            return "System"
        name = f"{obj.actor.first_name} {obj.actor.last_name}".strip()
        return name or obj.actor.email
