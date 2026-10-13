"""Admin system-broadcast endpoint (Stage 4.16 §16).

    POST /api/admin/notifications/broadcast/   notifications.broadcast (SUP/ADM)

Approved broadcast contract (api-design §M / §21 notification admin):
* Only ``SYSTEM`` type, IN_APP notifications are broadcast — no impersonation
  of a medical/comms channel.
* Audience is ``ALL`` | ``ROLE`` | ``USERS`` and is validated server-side.
  ``ROLE``/``USERS`` target ACTIVE accounts only; ``USERS`` is capped to stop
  accidental platform-wide spam.
* Sender, audience + target count and timestamp are recorded on every row and
  in the append-only audit trail. Nothing about private user notifications is
  ever exposed from this surface.
* MFA step-up boundary (accounts.mfa) applies, like all admin surfaces.
"""

from django.db import transaction
from drf_spectacular.utils import extend_schema
from rest_framework import permissions, serializers as drf_serializers, status as http_status
from rest_framework.response import Response
from rest_framework.views import APIView

from accounts.models import Role, User
from accounts.permissions import IsAuthenticatedRespectStatus
from audit.services import record_audit

from .admin_serializers import AdminBroadcastOut

MAX_USERS_AUDIENCE = 500
ALLOWED_TYPES = {"SYSTEM"}

AUDIENCE_CHOICES = ("ALL", "ROLE", "USERS")


class _BroadcastAccess(permissions.BasePermission):
    """notifications.broadcast + status gate + MFA boundary."""

    message = "You do not have permission to broadcast notifications."

    def has_permission(self, request, view):
        user = getattr(request, "user", None)
        if not (user and user.is_authenticated):
            return False
        if not IsAuthenticatedRespectStatus().has_permission(request, view):
            return False
        if not user.has_perm_code("notifications.broadcast"):
            return False
        from accounts.mfa import MfaPolicy

        return MfaPolicy().is_compliant(request, user)


class AdminBroadcastIn(drf_serializers.Serializer):
    audience = drf_serializers.ChoiceField(choices=AUDIENCE_CHOICES)
    title = drf_serializers.CharField(max_length=200, trim_whitespace=True)
    body = drf_serializers.CharField(max_length=5000, trim_whitespace=True)
    role_code = drf_serializers.CharField(max_length=32, required=False, allow_blank=True)
    user_uid = drf_serializers.ListField(
        child=drf_serializers.UUIDField(), required=False, allow_empty=True,
    )

    def validate(self, attrs):
        audience = attrs["audience"]
        if audience == "ROLE" and not attrs.get("role_code", "").strip():
            raise drf_serializers.ValidationError({"role_code": "Required for ROLE audiences."})
        if audience == "USERS" and not attrs.get("user_uid"):
            raise drf_serializers.ValidationError({"user_uid": "Required for USERS audiences."})
        if audience != "USERS" and len(attrs.get("user_uid") or []) > 0:
            raise drf_serializers.ValidationError({"user_uid": "Only valid for USERS audiences."})
        if audience == "USERS" and len(attrs["user_uid"]) > MAX_USERS_AUDIENCE:
            raise drf_serializers.ValidationError(
                {"user_uid": f"USERS audience is capped at {MAX_USERS_AUDIENCE} recipients."}
            )
        return attrs


@extend_schema(request=AdminBroadcastIn, responses={201: AdminBroadcastOut})
class AdminBroadcastView(APIView):
    """Broadcast across an approved audience. Creates IN_APP SYSTEM rows."""

    permission_classes = [IsAuthenticatedRespectStatus, _BroadcastAccess]

    @transaction.atomic
    def post(self, request):
        serializer = AdminBroadcastIn(data=request.data)
        serializer.is_valid(raise_exception=True)
        data = serializer.validated_data

        audience = data["audience"]
        targets = User.objects.filter(
            deleted_at__isnull=True, account_status="ACTIVE",
        )
        if audience == "ROLE":
            role_code = data["role_code"].strip().upper()
            if not Role.objects.filter(code=role_code).exists():
                raise drf_serializers.ValidationError({"role_code": "Unknown role."})
            targets = targets.filter(user_roles__is_active=True, user_roles__role__code=role_code).distinct()
        elif audience == "USERS":
            uids = data["user_uid"]
            targets = targets.filter(uid__in=uids).distinct()
            found = targets.count()
            if found != len(uids):
                raise drf_serializers.ValidationError(
                    {"user_uid": "One or more target accounts were not found or are not ACTIVE."}
                )

        if not targets.exists():
            raise drf_serializers.ValidationError({"audience": "The audience is empty."})

        # Stage 4.18: one bulk_insert window instead of one INSERT per recipient.
        from .services import create_broadcast_notifications

        created = create_broadcast_notifications(
            recipients=targets.iterator(),
            title=data["title"],
            body=data["body"],
            channel="IN_APP",
        )

        record_audit(
            actor=request.user,
            action_code="notifications.broadcast",
            resource_type="notifications",
            request=request,
            details={
                "audience": audience,
                "role_code": data.get("role_code", ""),
                "target_count": created,
                "title": data["title"][:200],
            },
        )
        return Response(AdminBroadcastOut({"audience": audience, "recipient_count": created}).data,
                        status=http_status.HTTP_201_CREATED)