"""Admin control-plane views (Stage 4.16 — Account Management).

Mounts the approved 4.16 admin surfaces that did not exist yet:

    GET    /api/admin/users/                    admin.users.manage — search/filter
    POST   /api/admin/users/{uid}/activate/     admin.users.manage (+audited reason)
    POST   /api/admin/users/{uid}/deactivate/   admin.users.manage (+audited reason)
    GET    /api/admin/users/{uid}/roles/        admin.users.manage
    POST   /api/admin/users/{uid}/roles/        admin.users.manage (C17 assign)
    DELETE /api/admin/users/{uid}/roles/        admin.users.manage (C17 revoke)
    GET    /api/admin/security-events/          admin.audit.read — monitoring

Design rules enforced here (role-permission-matrix §2, §3.4; api-design §07):

* Deny-by-default via ``admin.users.manage`` (seeded SUP/ADM only).
* C17 — privileged-role assignment is SUPER_ADMIN-only; ADMIN may assign only
  non-privileged roles; self-assignment always denied; every change audited.
* No admin can deactivate/suspend their own account; a non-super admin cannot
  touch a privileged (SUPER_ADMIN/ADMIN) account's status or roles.
* MFA step-up boundary (accounts.mfa) applies to every mutation.
* Account Management is strictly separate from Medical Record Management: no
  medical / donor / financial data is ever returned from these endpoints.
"""

import uuid as _uuid

from django.db import transaction
from django.db.models import Q
from rest_framework import permissions, status as http_status, viewsets
from rest_framework.decorators import action
from rest_framework.exceptions import NotFound, PermissionDenied, ValidationError
from rest_framework.response import Response

from audit.services import record_audit
from core.pagination import CorePageNumberPagination
from . import admin_serializers, mfa
from .models import Role, SecurityEvent, User, UserRole
from .permissions import IsAuthenticatedRespectStatus

PRIVILEGED_ROLE_CODES = frozenset({"SUPER_ADMIN", "ADMIN"})

_ACCOUNT_STATUSES = {c for c, _ in User.ACCOUNT_STATUS}

# Remote address / user-agent reader (kept local; never logged as secrets).
_REMOTE_ADDR = "REMOTE_ADDR"
_USER_AGENT = "HTTP_USER_AGENT"


def _deny(message):
    return PermissionDenied(message)


def _request_ip(request):
    meta = getattr(request, "META", {}) or {}
    return meta.get(_REMOTE_ADDR)


def _mfa_gate(request, user):
    """Cross the step-up boundary; record a telemetry event when refused."""
    policy = mfa.MfaPolicy()
    if policy.is_compliant(request, user):
        return True
    if policy.step_up_required(user):
        mfa.record_step_up_event(user=user, ip_address=_request_ip(request))
    return False


class AdminUsersAccess(permissions.BasePermission):
    """admin.users.manage + account-status + MFA step-up boundary."""

    message = "You do not have permission to manage users."

    def has_permission(self, request, view):
        user = getattr(request, "user", None)
        if not (user and user.is_authenticated):
            return False
        if not IsAuthenticatedRespectStatus().has_permission(request, view):
            return False
        if not user.has_perm_code("admin.users.manage"):
            return False
        return _mfa_gate(request, user)


class AdminUsersViewSet(viewsets.GenericViewSet):
    """Account management surface (App Account Management ≠ medical records)."""

    lookup_field = "uid"
    lookup_url_kwarg = "uid"
    pagination_class = CorePageNumberPagination
    serializer_class = admin_serializers.AdminUserSerializer
    permission_classes = [IsAuthenticatedRespectStatus, AdminUsersAccess]

    def _base_queryset(self):
        return User.objects.exclude(deleted_at__isnull=False)

    def get_queryset(self):
        qs = self._base_queryset()
        params = self.request.query_params
        q = (params.get("q") or "").strip()
        if q:
            qs = qs.filter(
                Q(email__icontains=q)
                | Q(phone__icontains=q)
                | Q(first_name__icontains=q)
                | Q(last_name__icontains=q)
            )
        status_filter = (params.get("status") or "").strip().upper()
        if status_filter:
            if status_filter not in _ACCOUNT_STATUSES:
                raise ValidationError({"status": "Unsupported account status."})
            qs = qs.filter(account_status=status_filter)
        role_filter = (params.get("role") or "").strip().upper()
        if role_filter:
            qs = qs.filter(user_roles__is_active=True, user_roles__role__code=role_filter).distinct()
        return qs

    def get_object(self):
        try:
            _uuid.UUID(str(self.kwargs[self.lookup_url_kwarg]))
        except (ValueError, TypeError):
            raise NotFound("Not found.")
        obj = self._base_queryset().filter(uid=self.kwargs[self.lookup_url_kwarg]).first()
        if obj is None:
            raise NotFound("Not found.")
        self.check_object_permissions(self.request, obj)
        return obj

    def _serialize(self, obj):
        return admin_serializers.AdminUserSerializer(obj, context={"request": self.request}).data

    def list(self, request):
        page = self.paginate_queryset(self.get_queryset().order_by("-created_at"))
        serializer = admin_serializers.AdminUserSerializer(page, many=True, context={"request": request})
        return self.get_paginated_response(serializer.data)

    @action(detail=True, methods=["get", "post", "delete"], url_path="roles", url_name="roles")
    @transaction.atomic
    def roles(self, request, uid=None):
        obj = self.get_object()
        method = request.method.upper()
        if method == "GET":
            return Response({"uid": obj.uid, "roles": obj.role_codes})

        role_code = str((request.data or {}).get("role_code", "")).strip().upper()
        if not role_code:
            raise ValidationError({"role_code": "Required."})
        role = Role.objects.filter(code=role_code).first()
        if role is None:
            raise ValidationError({"role_code": "Unknown role."})
        self._check_role_privilege(request.user, obj, role_code)

        serializer = admin_serializers.AdminRoleIn(data=request.data)
        serializer.is_valid(raise_exception=True)
        reason = serializer.validated_data["reason"]

        if method == "POST":
            return self._grant_role(request, obj, role, reason)
        return self._revoke_role(request, obj, role, reason)

    def _grant_role(self, request, obj, role, reason):
        user_role, created = UserRole.objects.get_or_create(
            user=obj, role=role,
            defaults={"granted_by": request.user, "is_active": True},
        )
        if not created and user_role.is_active:
            raise ValidationError({"role_code": f"{role.code} is already assigned."})
        if not user_role.is_active:
            user_role.is_active = True
            user_role.granted_by = request.user
            user_role.revoked_at = None
            user_role.save(update_fields=["is_active", "granted_by", "revoked_at"])

        record_audit(
            actor=request.user,
            action_code="admin.user.role_grant",
            resource_type="users",
            resource_id=obj.pk,
            request=request,
            details={"target": obj.email, "role": role.code, "reason": reason},
        )
        return Response(self._serialize(obj))

    def _revoke_role(self, request, obj, role, reason):
        user_role = UserRole.objects.filter(user=obj, role=role, is_active=True).first()
        if user_role is None:
            raise ValidationError({"role_code": f"{role.code} is not assigned."})
        active_count = UserRole.objects.filter(user=obj, is_active=True).count()
        if active_count <= 1:
            raise ValidationError({"role_code": "Cannot revoke the last role on the account."})

        user_role.is_active = False
        user_role.revoked_at = _now()
        user_role.save(update_fields=["is_active", "revoked_at"])

        record_audit(
            actor=request.user,
            action_code="admin.user.role_revoke",
            resource_type="users",
            resource_id=obj.pk,
            request=request,
            details={"target": obj.email, "role": role.code, "reason": reason},
        )
        return Response(self._serialize(obj))

    @action(detail=True, methods=["post"], url_path="activate")
    @transaction.atomic
    def activate(self, request, uid=None):
        obj = self.get_object()
        serializer = admin_serializers.AdminReasonIn(data=request.data)
        serializer.is_valid(raise_exception=True)
        if obj.account_status == "ACTIVE":
            raise ValidationError({"detail": "Account is already ACTIVE."})
        old_status = obj.account_status
        obj.account_status = "ACTIVE"
        obj.is_active = True
        obj.save(update_fields=["account_status", "is_active"])
        record_audit(
            actor=request.user,
            action_code="admin.user.activate",
            resource_type="users",
            resource_id=obj.pk,
            request=request,
            details={
                "target": obj.email, "from": old_status, "to": "ACTIVE",
                "reason": serializer.validated_data["reason"],
            },
        )
        return Response(self._serialize(obj))

    @action(detail=True, methods=["post"], url_path="deactivate")
    @transaction.atomic
    def deactivate(self, request, uid=None):
        obj = self.get_object()
        # Authorization precedes payload validation (fail closed).
        if obj.pk == request.user.pk:
            raise _deny("Administrators cannot deactivate their own account.")
        if not request.user._has_active_role("SUPER_ADMIN") and obj._has_active_role(*PRIVILEGED_ROLE_CODES):
            raise _deny("Only SUPER_ADMIN may suspend a privileged account.")
        serializer = admin_serializers.AdminReasonIn(data=request.data)
        serializer.is_valid(raise_exception=True)
        if obj.account_status in ("DEACTIVATED",):
            raise ValidationError({"detail": "Account is already deactivated."})
        old_status = obj.account_status
        obj.account_status = "SUSPENDED"
        # Stage 4.17 §20: an account revocation must kill the live session too.
        # SimpleJWT's auth rule keys on is_active, so a suspension must flip it
        # or the user could keep rotating refresh tokens indefinitely.
        obj.is_active = False
        obj.save(update_fields=["account_status", "is_active", "updated_at"])
        record_audit(
            actor=request.user,
            action_code="admin.user.deactivate",
            resource_type="users",
            resource_id=obj.pk,
            request=request,
            details={
                "target": obj.email, "from": old_status, "to": "SUSPENDED",
                "reason": serializer.validated_data["reason"],
            },
        )
        return Response(self._serialize(obj))

    def _check_role_privilege(self, actor, target, role_code):
        """C17: self-assignment denied; privileged roles are SUP-only."""
        if actor.pk == target.pk:
            raise _deny("Administrators cannot change their own roles.")
        if role_code in PRIVILEGED_ROLE_CODES and not actor._has_active_role("SUPER_ADMIN"):
            raise _deny("Only SUPER_ADMIN may grant or revoke a privileged role.")
        if not actor._has_active_role("SUPER_ADMIN") and target._has_active_role(*PRIVILEGED_ROLE_CODES):
            raise _deny("Only SUPER_ADMIN may change the roles of a privileged account.")


class AdminSecurityEventsAccess(permissions.BasePermission):
    """admin.audit.read (+ status gate + MFA boundary). Read-only monitoring."""

    message = "You do not have permission to view security events."

    def has_permission(self, request, view):
        user = getattr(request, "user", None)
        if not (user and user.is_authenticated):
            return False
        if not IsAuthenticatedRespectStatus().has_permission(request, view):
            return False
        if not user.has_perm_code("admin.audit.read"):
            return False
        return _mfa_gate(request, user)


class AdminSecurityEventsView(viewsets.GenericViewSet):
    """GET /api/admin/security-events/ — auth/security telemetry monitoring.
    Never returns credentials; detail is bounded already at write time."""

    queryset = None
    pagination_class = CorePageNumberPagination
    serializer_class = admin_serializers.SecurityEventSerializer
    permission_classes = [IsAuthenticatedRespectStatus, AdminSecurityEventsAccess]

    def list(self, request):
        qs = SecurityEvent.objects.all()
        params = request.query_params
        event_type = (params.get("event_type") or "").strip().upper()
        if event_type:
            if event_type not in SecurityEvent.KINDS:
                raise ValidationError({"event_type": "Unsupported event type."})
            qs = qs.filter(event_type=event_type)
        status_filter = (params.get("status") or "").strip().upper()
        if status_filter:
            qs = qs.filter(status=status_filter)
        user_q = (params.get("user") or "").strip()
        if user_q:
            qs = qs.filter(user__email__icontains=user_q)
        ip_q = (params.get("ip") or "").strip()
        if ip_q:
            qs = qs.filter(ip_address=ip_q)
        date_from = (params.get("date_from") or "").strip()
        if date_from:
            qs = qs.filter(created_at__date__gte=_parse_date(date_from))
        date_to = (params.get("date_to") or "").strip()
        if date_to:
            qs = qs.filter(created_at__date__lte=_parse_date(date_to))
        page = self.paginate_queryset(qs.order_by("-created_at"))
        serializer = admin_serializers.SecurityEventSerializer(page, many=True)
        return self.get_paginated_response(serializer.data)


def _parse_date(value):
    from datetime import datetime

    try:
        return datetime.strptime(value, "%Y-%m-%d").date()
    except ValueError:
        raise ValidationError({"date": "Use YYYY-MM-DD dates."})


def _now():
    from django.utils import timezone

    return timezone.now()