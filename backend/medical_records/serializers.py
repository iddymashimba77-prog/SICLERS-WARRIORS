"""Consent serializers (AUTH-1; database-design §9, api-design consent rows)."""

from rest_framework import serializers

from accounts.models import Role
from . import models


class ConsentSerializer(serializers.ModelSerializer):
    granted_to_uid = serializers.UUIDField(source="granted_to.uid", read_only=True)
    granted_to_email = serializers.EmailField(source="granted_to.email", read_only=True)
    granted_to_name = serializers.SerializerMethodField()
    authorized_role_code = serializers.CharField(source="authorized_role.code", read_only=True)

    class Meta:
        model = models.Consent
        fields = [
            "uid", "resource_type", "resource_ids", "permission_scope", "purpose",
            "start_date", "expires_at", "status", "revoked_at",
            "authorized_role_code", "granted_to_uid", "granted_to_email",
            "granted_to_name", "created_at", "updated_at",
        ]
        read_only_fields = fields

    def get_granted_to_name(self, obj) -> str:
        name = f"{obj.granted_to.first_name} {obj.granted_to.last_name}".strip()
        return name or "Member"


class ConsentCreateSerializer(serializers.Serializer):
    granted_to_uid = serializers.UUIDField()
    authorized_role_code = serializers.CharField(required=False, allow_blank=True, max_length=50)
    resource_type = serializers.ChoiceField(choices=[c for c, _ in models.Consent.RESOURCE_TYPE])
    resource_ids = serializers.ListField(child=serializers.IntegerField(), required=False)
    permission_scope = serializers.ListField(
        child=serializers.CharField(max_length=120), allow_empty=False,
    )
    purpose = serializers.CharField(required=False, allow_blank=True, max_length=2000)
    start_date = serializers.DateTimeField(required=False)
    expires_at = serializers.DateTimeField()

    def validate_permission_scope(self, value):
        for code in value:
            parts = str(code).split(".")
            # Approved codes are `module.resource.action`; legacy matrix codes
            # are 2-part (`patients.view`, `auth.profile_view`).
            if len(parts) not in (2, 3) or not all(parts):
                raise serializers.ValidationError(
                    f"Invalid permission code: {code} (expected module.resource.action)."
                )
        return value


class ConsentPatchSerializer(serializers.Serializer):
    permission_scope = serializers.ListField(
        child=serializers.CharField(max_length=120), required=False,
    )
    purpose = serializers.CharField(required=False, allow_blank=True, max_length=2000)
    expires_at = serializers.DateTimeField(required=False)

    def validate_permission_scope(self, value):
        for code in value:
            parts = str(code).split(".")
            if len(parts) not in (2, 3) or not all(parts):
                raise serializers.ValidationError(
                    f"Invalid permission code: {code} (expected module.resource.action)."
                )
        return value


class ConsentRenewSerializer(serializers.Serializer):
    expires_at = serializers.DateTimeField()