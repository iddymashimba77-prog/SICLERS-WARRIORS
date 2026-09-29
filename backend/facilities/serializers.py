"""Facility serializers (approved §6 endpoint surface)."""

from rest_framework import serializers

from .models import Facility


class FacilitySerializer(serializers.ModelSerializer):
    """Public subset — verified facilities for the blood-request venue picker."""

    class Meta:
        model = Facility
        fields = [
            "uid", "name", "facility_type", "region", "city", "is_verified",
        ]
        read_only_fields = ["uid", "is_verified"]


class FacilityMeSerializer(FacilitySerializer):
    """HOSPITAL-operator self surface (adds operational fields, C7)."""

    class Meta:
        model = Facility
        fields = FacilitySerializer.Meta.fields + [
            "address", "registration_number", "operator",
        ]
        read_only_fields = ["uid", "is_verified", "operator"]


class FacilityVerifySerializer(serializers.Serializer):
    approve = serializers.BooleanField()
    reason = serializers.CharField(required=False, allow_blank=True)


class FacilityAdminSerializer(serializers.ModelSerializer):
    """Admin directory row (ADMIN-3) — identity + verification state only.

    Never returns medical records, donor data or MFA materials (§24): the
    facility card exposes the minimum an officer/administrator needs to review
    an organization application."""

    operator_email = serializers.EmailField(source="operator.email", read_only=True)
    operator_uid = serializers.UUIDField(source="operator.uid", read_only=True)

    class Meta:
        model = Facility
        fields = [
            "uid", "name", "facility_type", "region", "city", "address",
            "registration_number", "is_verified", "verified_at",
            "operator_uid", "operator_email", "created_at",
        ]
        read_only_fields = fields