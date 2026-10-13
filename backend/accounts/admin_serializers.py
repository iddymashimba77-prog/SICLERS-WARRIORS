"""Admin serializers (Stage 4.16 — user management, security events).

Minimal by corporate-design principle: the admin surface never returns medical
records, identity secrets or MFA materials — only identity + RBAC state.
"""

from rest_framework import serializers

from .models import Permission, SecurityEvent, User


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

    def get_full_name(self, obj) -> str:
        name = f"{obj.first_name} {obj.last_name}".strip()
        return name or ""

    def get_role_codes(self, obj) -> list[str]:
        return obj.role_codes


class AdminReasonIn(serializers.Serializer):
    """Every sensitive account/role mutation carries an audited reason."""

    reason = serializers.CharField(min_length=5, max_length=500, trim_whitespace=True)


class AdminRoleIn(AdminReasonIn):
    role_code = serializers.CharField(min_length=2, max_length=32)


class AdminPermissionSerializer(serializers.ModelSerializer):
    """Read-only permission catalog row (api-design §3.3 ``GET /admin/permissions``).

    ``name`` is a derived human label — the ``Permission`` model stores the
    authoritative ``module.resource.action`` triple only.
    """

    name = serializers.SerializerMethodField()

    class Meta:
        model = Permission
        fields = ["code", "module", "resource", "action", "name"]
        read_only_fields = fields

    def get_name(self, obj) -> str:
        return f"{obj.resource.replace('_', ' ').title()} ({obj.action})"


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


class AdminRoleCreateIn(serializers.Serializer):
    """Create a new non-system role (SUP-only write).

    ``code`` is optional — when omitted it is derived from ``name``
    (e.g. "Medical Officer" -> MEDICAL_OFFICER). Admin-created roles start
    with zero permissions (deny-by-default) and no members.
    """

    name = serializers.CharField(min_length=2, max_length=150, trim_whitespace=True)
    code = serializers.CharField(
        required=False, max_length=50, trim_whitespace=True,
    )
    description = serializers.CharField(
        required=False, allow_blank=True, max_length=500,
    )

    def validate_code(self, value):
        return _normalize_role_code(value)

    def validate(self, attrs):
        name = attrs["name"]
        code = attrs.get("code") or _derive_role_code(name)
        if not code:
            raise serializers.ValidationError(
                {"code": "Could not derive a code from the name; provide one explicitly."}
            )
        from django.apps import apps

        Role = apps.get_model("accounts", "Role")
        if Role.objects.filter(code=code).exists():
            raise serializers.ValidationError(
                {"code": f"A role with code {code} already exists."}
            )
        if code in {"PATIENT", "DOCTOR", "PSYCHOLOGIST", "SOCIAL_SUPPORT",
                    "BLOOD_DONOR", "FINANCIAL_DONOR", "CAREGIVER", "RECRUITER",
                    "SUPER_ADMIN", "ADMIN", "HOSPITAL", "CLINIC"}:
            raise serializers.ValidationError(
                {"code": f"{code} is a system role and cannot be re-created."}
            )
        attrs["code"] = code
        return attrs


def _derive_role_code(name: str) -> str:
    """MEDICAL_OFFICER from 'Medical Officer'; falls back to '' when node."""

    import re

    tokens = re.findall(r"[^\W_]+", name)
    return "_".join(t.upper() for t in tokens if t.isalpha()) if tokens else ""


def _normalize_role_code(value: str) -> str:
    import re

    code = value.strip().upper()
    if not re.fullmatch(r"[A-Z0-9_]+", code or ""):
        raise serializers.ValidationError(
            "Code must contain only uppercase letters, digits and underscores."
        )
    return code


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