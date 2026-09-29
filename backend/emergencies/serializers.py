"""Emergency serializers (approved §8.6 + endpoint-matrix §13)."""

from rest_framework import serializers

from accounts.models import User
from .models import EmergencyAccessGrant, EmergencyRequest, EmergencyResponder


REQUEST_FIELDS = [
    "uid", "requester_email", "patient_email", "severity", "type", "location",
    "description", "status", "rate_limit_ok", "phone_verified",
    "escalated_at", "resolved_at", "created_at", "updated_at",
]


class EmergencyRequestSerializer(serializers.ModelSerializer):
    requester_email = serializers.EmailField(source="requester.email", read_only=True)
    patient_email = serializers.EmailField(source="patient.email", read_only=True)

    class Meta:
        model = EmergencyRequest
        fields = REQUEST_FIELDS
        read_only_fields = [
            "uid", "requester_email", "patient_email", "status",
            "rate_limit_ok", "phone_verified", "escalated_at", "resolved_at",
            "created_at", "updated_at",
        ]


class EmergencyResponderSummarySerializer(serializers.ModelSerializer):
    """Responder view for the request owner (EMG-004 timeline).

    Deliberately omits the responder's email/PII: the owner only needs to know
    a role has acknowledged and its progress, not responder contact details.
    """

    class Meta:
        model = EmergencyResponder
        fields = [
            "responder_role", "status",
            "notified_at", "acknowledged_at", "arrived_at", "completed_at", "updated_at",
        ]
        read_only_fields = fields


class EmergencyDetailSerializer(EmergencyRequestSerializer):
    """Request detail with the responder timeline for status tracking (EMG-004)."""

    responders = EmergencyResponderSummarySerializer(many=True, read_only=True)

    class Meta(EmergencyRequestSerializer.Meta):
        fields = REQUEST_FIELDS + ["responders"]


class EmergencyCreateSerializer(serializers.Serializer):
    """FR-EMG-001/002 submission payload.

    ``phone_verified`` is deliberately NOT an input (Stage 4.17 §18): only the
    operator verification workflow can assert a phone is verified; a client
    may never self-stamp that monitoring red-flag.
    """

    severity = serializers.ChoiceField(choices=["NORMAL", "URGENT", "CRITICAL"], default="NORMAL")
    type = serializers.ChoiceField(choices=["MEDICAL", "PAIN_CRISIS", "BLOOD", "FALL", "OTHER"])
    location = serializers.JSONField(required=False, default=dict)
    description = serializers.CharField(required=False, allow_blank=True, max_length=2000)
    patient_uid = serializers.UUIDField(required=False, default=None)
    idempotency_key = serializers.CharField(required=False, allow_blank=True, max_length=120, write_only=True)

    def validate_patient_uid(self, value):
        if value is None:
            return None
        patient = User.objects.filter(uid=value).first()
        if patient is None:
            raise serializers.ValidationError("Unknown patient.")
        return value

    def validate_location(self, value):
        """Validate the free-form location payload (EMG-003, database-design §8.6).

        Location is stored as JSON so a warrior can give whatever they know
        ("hostel B, room 4", a landmark) without requiring a GPS dependency.
        If coordinates are supplied they must be a valid pair and in range;
        nothing else is required. Precise coordinates are only ever returned to
        the requester, active responders and admins (view queryset scoping).
        """
        if not isinstance(value, dict):
            raise serializers.ValidationError("Location must be an object.")
        latitude = value.get("latitude")
        longitude = value.get("longitude")
        if (latitude is None) != (longitude is None):
            raise serializers.ValidationError(
                "latitude and longitude must be provided together."
            )
        if latitude is not None:
            try:
                latitude = float(latitude)
                longitude = float(longitude)
            except (TypeError, ValueError):
                raise serializers.ValidationError("Coordinates must be numeric.")
            if not -90 <= latitude <= 90 or not -180 <= longitude <= 180:
                raise serializers.ValidationError("Coordinates are out of range.")
        return value



class EmergencyResponderSerializer(serializers.ModelSerializer):
    responder_email = serializers.EmailField(source="responder.email", read_only=True)

    class Meta:
        model = EmergencyResponder
        fields = [
            "id", "responder_email", "responder_role", "status",
            "notified_at", "acknowledged_at", "arrived_at", "completed_at", "updated_at",
        ]
        read_only_fields = fields


class EmergencyAccessGrantSerializer(serializers.ModelSerializer):
    patient_email = serializers.EmailField(source="patient.email", read_only=True)
    grantee_email = serializers.EmailField(source="grantee.email", read_only=True)

    class Meta:
        model = EmergencyAccessGrant
        fields = [
            "uid", "patient_email", "grantee_email", "scope", "reason",
            "status", "starts_at", "expires_at", "created_at",
        ]
        read_only_fields = fields