"""Admin serializers (Stage 4.16 — user management, security events).

Minimal by corporate-design principle: the admin surface never returns medical
records, identity secrets or MFA materials — only identity + RBAC state.
"""

from rest_framework import serializers

from .models import SecurityEvent, User


class AdminUserSerializer(serializers.ModelSerializer):
    """Admin-facing account row. Identity + RBAC only; zero medical data,
    zero MFA secret, no Contact/secrets."""

    full_name = serializers.SerializerMethodField()
    role_codes = serializers.SerializerMethodField()

    class Meta:
        model = User
        fields = [
            "uid", "email", "phone", "full_name", "account_status",
            "role_codes", "mfa_enabled", "created_at",
        ]
        read_only_fields = fields

    def get_full_name(self, obj):
        name = f"{obj.first_name} {obj.last_name}".strip()
        return name or ""

    def get_role_codes(self, obj):
        return obj.role_codes


class AdminReasonIn(serializers.Serializer):
    """Every sensitive account/role mutation carries an audited reason."""

    reason = serializers.CharField(min_length=5, max_length=500, trim_whitespace=True)


class AdminRoleIn(AdminReasonIn):
    role_code = serializers.CharField(min_length=2, max_length=32)


class AdminRoleSerializer(serializers.Serializer):
    """Role row for the admin RBAC matrix (ADMIN-3). Permission *codes* only —
    never medical data, donor data or credentials."""

    code = serializers.CharField(read_only=True)
    name = serializers.CharField(read_only=True)
    is_system = serializers.BooleanField(read_only=True)
    permission_count = serializers.IntegerField(read_only=True)
    member_count = serializers.IntegerField(read_only=True)


class AdminRolePermissionIn(serializers.Serializer):
    """Grant/revoke one role<->permission edge (SUP-only write)."""

    permission_code = serializers.CharField(max_length=128, trim_whitespace=True)
    grant = serializers.BooleanField()
    reason = serializers.CharField(min_length=5, max_length=500, trim_whitespace=True)


class SecurityEventSerializer(serializers.ModelSerializer):
    user_uid = serializers.UUIDField(source="user.uid", read_only=True)
    user_email = serializers.EmailField(source="user.email", read_only=True)

    class Meta:
        model = SecurityEvent
        fields = [
            "id", "user_uid", "user_email", "event_type", "status",
            "ip_address", "user_agent", "detail", "created_at",
        ]
        read_only_fields = fields