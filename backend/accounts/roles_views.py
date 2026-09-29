"""Admin role & permission matrix surface (ADMIN-3).

    GET    /api/admin/roles/                    admin.roles.manage        (SUP/ADM)
    GET    /api/admin/roles/{code}/permissions/ admin.roles.manage        (SUP/ADM)
    POST   /api/admin/roles/{code}/permissions/ admin.permissions.manage  (SUP)

Read surfaces expose the LIVE role/permission matrix the backend actually
enforces (Role -> RolePermission -> Permission) plus active-member counts —
never a snapshot or a client-supplied projection. Write surfaces (SUP-only,
`admin.permissions.manage`, seeded SUPER_ADMIN-only) grant/revoke a single
role<->permission edge with a mandatory reason; every change is append-only
audited and refused when it would strip SUPER_ADMIN of a system-critical
permission (lockout guard).

Security posture mirrors every other admin control plane:
* Deny-by-default permission gate + account-status gate + MFA step-up boundary.
* Reasons are `security==>observability` evidence, echoed into the audit trail.
* The matrix endpoint returns permission *codes* only — never medical data,
  donor data or credentials (§24).
"""

from django.db.models import Count, Q
from rest_framework import permissions, status as http_status, viewsets
from rest_framework.decorators import action
from rest_framework.exceptions import NotFound, ValidationError
from rest_framework.response import Response

from audit.services import record_audit
from core.pagination import CorePageNumberPagination
from . import mfa
from .admin_serializers import AdminRolePermissionIn, AdminRoleSerializer
from .models import Permission, Role, RolePermission
from .permissions import IsAuthenticatedRespectStatus

# Generator-proof kernel: revoking any of these from SUPER_ADMIN would strand
# the platform's highest-role accountability (self-lockout). Refused server-side.
_SUPER_ADMIN_KERNEL = frozenset({
    "admin.permissions.manage",
    "admin.roles.manage",
    "admin.users.manage",
    "admin.audit.read",
    "admin.audit.export",
    "admin.system.manage",
})


def _mfa_ok(request, user) -> bool:
    return mfa.MfaPolicy().is_compliant(request, user)


class AdminRolesReadAccess(permissions.BasePermission):
    """admin.roles.manage + status gate + MFA boundary (read surfaces)."""

    message = "You do not have permission to view roles."

    def has_permission(self, request, view):
        user = getattr(request, "user", None)
        if not (user and user.is_authenticated):
            return False
        if not IsAuthenticatedRespectStatus().has_permission(request, view):
            return False
        if not user.has_perm_code("admin.roles.manage"):
            return False
        return _mfa_ok(request, user)


class AdminRolesWriteAccess(permissions.BasePermission):
    """admin.permissions.manage (SUP-only) + status gate + MFA boundary."""

    message = "Only a SUPER_ADMIN may change role permissions."

    def has_permission(self, request, view):
        user = getattr(request, "user", None)
        if not (user and user.is_authenticated):
            return False
        if not IsAuthenticatedRespectStatus().has_permission(request, view):
            return False
        if not user.has_perm_code("admin.permissions.manage"):
            return False
        return _mfa_ok(request, user)


class AdminRoleViewSet(viewsets.GenericViewSet):
    """Role / permission matrix for the admin portal (ADMIN-3)."""

    lookup_field = "code"
    lookup_url_kwarg = "code"
    pagination_class = CorePageNumberPagination

    def get_permissions(self):
        if getattr(self, "action", None) == "permissions" and self.request.method.upper() == "POST":
            return [IsAuthenticatedRespectStatus(), AdminRolesWriteAccess()]
        # There is no list-less safety net: any other surface (including GET)
        # requires the roles read gate.
        return [IsAuthenticatedRespectStatus(), AdminRolesReadAccess()]

    def _role_or_404(self):
        code = str(self.kwargs[self.lookup_url_kwarg]).strip().upper()
        role = Role.objects.filter(code=code).first()
        if role is None:
            raise NotFound("Not found.")
        return role

    @staticmethod
    def _permission_codes(role):
        return list(
            RolePermission.objects.filter(role=role)
            .values_list("permission__code", flat=True)
            .order_by("permission__code"),
        )

    def list(self, request):
        roles = Role.objects.annotate(
            permission_count=Count("role_permissions"),
            member_count=Count("user_roles", filter=Q(user_roles__is_active=True)),
        ).order_by("code")
        page = self.paginate_queryset(list(roles))
        rows = page if page is not None else roles
        data = [
            AdminRoleSerializer(
                {
                    "code": role.code,
                    "name": role.name,
                    "is_system": role.is_system,
                    "permission_count": role.permission_count,
                    "member_count": role.member_count,
                }
            ).data
            for role in rows
        ]
        if page is not None:
            return self.get_paginated_response(data)
        return Response({"data": data, "meta": {"count": len(data)}})

    @action(detail=True, methods=["get", "post"], url_path="permissions", url_name="permissions")
    def permissions(self, request, code=None):
        role = self._role_or_404()
        if request.method.upper() == "GET":
            return Response(
                {
                    "uid": role.id,
                    "code": role.code,
                    "name": role.name,
                    "permissions": self._permission_codes(role),
                }
            )

        serializer = AdminRolePermissionIn(data=request.data)
        serializer.is_valid(raise_exception=True)
        data = serializer.validated_data
        permission = Permission.objects.filter(code=data["permission_code"]).first()
        if permission is None:
            raise ValidationError({"permission_code": "Unknown permission code."})

        grant = data["grant"]
        reason = data["reason"]
        edge_exists = RolePermission.objects.filter(
            role=role, permission=permission,
        ).exists()

        if grant:
            if edge_exists:
                raise ValidationError(
                    {"permission_code": f"{role.code} already holds {permission.code}."}
                )
            RolePermission.objects.create(role=role, permission=permission)
            record_audit(
                actor=request.user,
                action_code="admin.roles.permission_grant",
                resource_type="role",
                resource_id=role.pk,
                request=request,
                details={
                    "role": role.code,
                    "permission": permission.code,
                    "reason": reason,
                },
            )
            return Response(
                {"code": role.code, "permission": permission.code, "granted": True},
                status=http_status.HTTP_201_CREATED,
            )

        # Revoke path — fail closed before any state change.
        if not edge_exists:
            raise ValidationError(
                {"permission_code": f"{role.code} does not hold {permission.code}."}
            )
        if role.code == "SUPER_ADMIN" and permission.code in _SUPER_ADMIN_KERNEL:
            raise ValidationError(
                {
                    "permission_code": (
                        f"{permission.code} is a SUPER_ADMIN kernel permission "
                        "and cannot be revoked."
                    )
                }
            )
        RolePermission.objects.filter(role=role, permission=permission).delete()
        record_audit(
            actor=request.user,
            action_code="admin.roles.permission_revoke",
            resource_type="role",
            resource_id=role.pk,
            request=request,
            details={
                "role": role.code,
                "permission": permission.code,
                "reason": reason,
            },
        )
        return Response({"code": role.code, "permission": permission.code, "granted": False})