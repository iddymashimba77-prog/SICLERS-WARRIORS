"""Blood-network serializers (approved §12 / §3.8).

Privacy invariants enforced here:
  * Public donor records expose blood group / region / city / availability /
    donor history ONLY — never email, phone, photo, or home address (BR-006).
  * Requests carry no donor PII; the donor-facing subset is the owner/detail
    surface minus requester contact details.
"""

from rest_framework import serializers

from facilities.models import Facility
from facilities.serializers import FacilitySerializer
from . import models


class PublicDonorSerializer(serializers.ModelSerializer):
    """Non-contact donor subset (blood_donors.view / matches / events)."""

    class Meta:
        model = models.BloodDonor
        fields = [
            "id", "blood_group", "region", "city", "is_available",
            "is_verified", "donation_count", "last_donation_date",
        ]
        read_only_fields = fields


class BloodDonorSelfSerializer(serializers.ModelSerializer):
    """Donor's own profile (blood_donors.self_manage, BLD)."""

    class Meta:
        model = models.BloodDonor
        fields = [
            "id", "blood_group", "region", "city", "is_available",
            "last_donation_date", "donation_count", "is_verified",
            "created_at", "updated_at",
        ]
        read_only_fields = [
            "id", "last_donation_date", "donation_count", "is_verified",
            "created_at", "updated_at",
        ]


class BloodRequestSerializer(serializers.ModelSerializer):
    facility = FacilitySerializer(read_only=True)
    facility_uid = serializers.UUIDField(write_only=True, required=False, allow_null=True)
    creator_email = serializers.EmailField(source="created_by.email", read_only=True)
    # Explicit field (no auto UniqueValidator): duplicate keys are surfaced as
    # 409 in perform_create (approved §30), never as a 400 validation error.
    idempotency_key = serializers.CharField(
        max_length=120, required=False, allow_null=True, write_only=True
    )

    class Meta:
        model = models.BloodRequest
        fields = [
            "uid", "blood_group_needed", "units", "urgency", "facility",
            "facility_uid", "reason", "location", "status", "creator_email",
            "verified_at", "rejection_reason", "idempotency_key",
            "created_at", "updated_at",
        ]
        read_only_fields = [
            "uid", "status", "verified_at", "rejection_reason",
            "created_at", "updated_at",
        ]

    def validate_facility_uid(self, value):
        facility = Facility.objects.filter(uid=value, is_verified=True).first()
        if value is not None and facility is None:
            raise serializers.ValidationError("Only verified facilities can host donations.")
        return value

    def create(self, validated_data):
        facility_uid = validated_data.pop("facility_uid", None)
        if facility_uid:
            validated_data["facility"] = Facility.objects.get(uid=facility_uid)
        return super().create(validated_data)


class PublicBloodRequestSerializer(serializers.ModelSerializer):
    """Verified, donor-facing request subset (C8) — no requester contact data."""

    facility = FacilitySerializer(read_only=True)

    class Meta:
        model = models.BloodRequest
        fields = [
            "uid", "blood_group_needed", "units", "urgency", "facility",
            "reason", "location", "status", "created_at",
        ]
        read_only_fields = fields


class BloodMatchSerializer(serializers.ModelSerializer):
    """Match view — donor is always the non-contact PublicDonorSerializer."""

    request_uid = serializers.UUIDField(source="request.uid", read_only=True)
    donor = PublicDonorSerializer(read_only=True)

    class Meta:
        model = models.BloodMatch
        fields = [
            "id", "request_uid", "donor", "match_score", "match_reason",
            "status", "notified_at", "responded_at", "fulfilled_at", "created_at",
        ]
        read_only_fields = fields


class BloodDonationEventSerializer(serializers.ModelSerializer):
    donor = PublicDonorSerializer(read_only=True)
    request_uid = serializers.UUIDField(source="request.uid", read_only=True)
    facility = FacilitySerializer(read_only=True)
    recorded_by_email = serializers.EmailField(source="recorded_by.email", read_only=True)

    class Meta:
        model = models.BloodDonationEvent
        fields = [
            "id", "donor", "request_uid", "facility", "units", "donated_at",
            "outcome", "donation_serial", "recorded_by_email", "created_at",
        ]
        read_only_fields = fields


class DonationEventCreateSerializer(serializers.Serializer):
    """STA/HOS (C7) records a donation against a verified facility."""

    donor_id = serializers.IntegerField()
    facility_uid = serializers.UUIDField()
    units = serializers.IntegerField(min_value=1, max_value=10)
    donated_at = serializers.DateTimeField()
    outcome = serializers.ChoiceField(choices=["COMPLETED", "DEFERRED", "FAILED"])
    donation_serial = serializers.CharField(max_length=100, required=False, allow_blank=True)

    def validate_donor_id(self, value):
        donor = models.BloodDonor.objects.filter(pk=value, is_verified=True).first()
        if donor is None:
            raise serializers.ValidationError("Unknown or unverified donor.")
        return value

    def validate_facility_uid(self, value):
        facility = Facility.objects.filter(uid=value, is_verified=True).first()
        if facility is None:
            raise serializers.ValidationError("A verified facility is required.")
        return value


class BloodMatchRespondSerializer(serializers.Serializer):
    action = serializers.ChoiceField(choices=["ACCEPT", "DECLINE"])