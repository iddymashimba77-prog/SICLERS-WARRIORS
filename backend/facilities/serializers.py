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


class FacilityVerificationSubmitSerializer(serializers.Serializer):
    """Facility C5 application — identity fields + attachment references.

    ``documents`` is a list of ``{"doc_type", "file_url"}`` entries whose
    ``file_url`` values are storage keys previously returned by
    ``POST /auth/verification/documents/upload/`` (never client-supplied URLs).
    """

    facility_type = serializers.ChoiceField(choices=Facility.FACILITY_TYPE)
    name = serializers.CharField(max_length=200)
    region = serializers.CharField(required=False, allow_blank=True, max_length=100)
    city = serializers.CharField(required=False, allow_blank=True, max_length=100)
    address = serializers.CharField(required=False, allow_blank=True)
    registration_number = serializers.CharField(required=False, allow_blank=True, max_length=100)
    documents = serializers.ListField(
        child=serializers.DictField(), min_length=2, max_length=10,
        error_messages={"min_length": "Attach your registration and National ID documents."},
    )


class FacilityAdminSerializer(serializers.ModelSerializer):
    """Admin directory row (ADMIN-3) — identity + verification state only.

    Never returns medical records, donor data or MFA materials (§24): the
    facility card exposes the minimum an officer/administrator needs to review
    an organization application."""

    operator_email = serializers.EmailField(source="operator.email", read_only=True)
    operator_uid = serializers.UUIDField(source="operator.uid", read_only=True)

    verification_documents = serializers.SerializerMethodField()

    def get_verification_documents(self, facility) -> list:
        """Submission-attachment summary for the reviewer (document *types*,
        statuses and file names plus the ``id`` to open through the audited admin
        document endpoint — never the file contents or storage keys)."""
        if not facility.operator_id:
            return []
        from accounts.serializers import VerificationDocumentReviewSerializer

        docs = facility.operator.verification_documents.order_by("created_at")
        return VerificationDocumentReviewSerializer(docs, many=True).data

    class Meta:
        model = Facility
        fields = [
            "uid", "name", "facility_type", "region", "city", "address",
            "registration_number", "is_verified", "verified_at",
            "operator_uid", "operator_email", "verification_documents", "created_at",
        ]
        read_only_fields = fields