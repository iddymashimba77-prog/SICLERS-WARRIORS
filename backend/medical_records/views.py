"""Consent API views (AUTH-1; api-design §consent, endpoint-matrix §9).

Surface:
    GET         /api/consents/             consents.view (owner / named grantee)
    POST        /api/consents/             consents.grant (PAT, owner)
    GET         /api/consents/active/      consents.view (grantee C2 eval)
    GET/PATCH   /api/consents/{uid}/       consents.view / consents.grant (owner)
    POST        /api/consents/{uid}/revoke/  consents.revoke (PAT, owner) — immediate
    POST        /api/consents/{uid}/renew/   consents.grant (PAT, owner) — extend

Object rules (role-perm §15):
* Owner = the patient on the consent row; a named grantee may read the detail
  the consent names them in (C3). SUP/ADM (C4) see the consent graph.
* Revocation is immediate (FR-MEDREC-005) and revoking a caregiver relationship
  also marks its consents REVOKED (caregiver view layer).
* Every grant/revoke/renew is audited both in `audit_logs` and
  `security_events` (role-perm §15, §22) — no PHI in log payloads.
"""

from django.db.models import Q
from django.utils import timezone
from rest_framework import mixins, status as http_status, viewsets
from rest_framework.decorators import action
from rest_framework.exceptions import NotFound, PermissionDenied, ValidationError
from rest_framework.parsers import JSONParser
from rest_framework.response import Response

from accounts.models import Role, SecurityEvent, User
from accounts.permissions import IsAuthenticatedRespectStatus, require
from audit.services import record_audit
from patients.models import Patient
from . import models, serializers, services


def _resolve_user(uid) -> User:
    user = User.objects.filter(uid=uid, deleted_at__isnull=True).first()
    if user is None:
        raise NotFound("Grantee not found.")
    return user


class ConsentViewSet(
    mixins.ListModelMixin,
    mixins.RetrieveModelMixin,
    mixins.UpdateModelMixin,
    viewsets.GenericViewSet,
):
    lookup_field = "uid"
    lookup_url_kwarg = "uid"
    serializer_class = serializers.ConsentSerializer
    permission_classes = [IsAuthenticatedRespectStatus, require("consents.view")]
    parser_classes = [JSONParser]

    def _is_owner(self, consent) -> bool:
        return consent.patient_profile.user_id == self.request.user.id

    def _owner_patient(self) -> Patient:
        if not self.request.user.is_patient:
            raise PermissionDenied("A PATIENT identity is required for this action.")
        patient, _ = Patient.objects.get_or_create(user=self.request.user)
        return patient

    def get_queryset(self):
        user = self.request.user
        if not (user and user.is_authenticated):
            return models.Consent.objects.none()
        qs = models.Consent.objects.select_related("patient_profile__user", "granted_to")
        if user.is_admin:
            return qs
        patient = Patient.objects.filter(user=user).first()
        mine = Q(patient_profile=patient) if patient else Q(pk__in=[])
        named = Q(granted_to=user)
        return qs.filter(mine | named)

    def get_object(self):
        consent = self.get_queryset().filter(uid=self.kwargs[self.lookup_url_kwarg]).first()
        if consent is None:
            raise NotFound("Consent not found.")
        return consent

    def create(self, request, *args, **kwargs):
        if not request.user.has_perm_code("consents.grant"):
            raise PermissionDenied("Only the patient can grant consent.")
        serializer = serializers.ConsentCreateSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        data = serializer.validated_data
        patient = self._owner_patient()
        granted_to = _resolve_user(data["granted_to_uid"])
        if granted_to.id == request.user.id:
            raise ValidationError({"granted_to_uid": "You cannot grant consent to yourself."})
        role = None
        if data.get("authorized_role_code"):
            role = Role.objects.filter(code=data["authorized_role_code"].upper()).first()
            if role is None:
                raise ValidationError({"authorized_role_code": "Unknown role."})
        try:
            consent = services.grant(
                patient=patient,
                granted_to=granted_to,
                permission_scope=data["permission_scope"],
                resource_type=data["resource_type"],
                resource_ids=data.get("resource_ids"),
                purpose=data.get("purpose", ""),
                start_date=data.get("start_date"),
                expires_at=data["expires_at"],
                authorized_role=role,
            )
        except ValueError as exc:
            raise ValidationError({"expires_at": str(exc)})
        record_audit(
            actor=request.user, action_code="consents.grant",
            resource_type="consent", resource_id=consent.pk, request=request,
            details={
                "grantee": str(granted_to.uid), "resource_type": consent.resource_type,
                "permission_scope": consent.permission_scope,
            },
        )
        _event(request.user, "CONSENT_GRANTED", {"grantee": str(granted_to.uid)})
        return Response(
            serializers.ConsentSerializer(consent).data, status=http_status.HTTP_201_CREATED,
        )

    def partial_update(self, request, *args, **kwargs):
        if not request.user.has_perm_code("consents.grant"):
            raise PermissionDenied("Only the patient can amend consent.")
        consent = self.get_object()
        if not self._is_owner(consent):
            raise PermissionDenied("Only the granting patient can amend this consent.")
        serializer = serializers.ConsentPatchSerializer(data=request.data, partial=True)
        serializer.is_valid(raise_exception=True)
        data = serializer.validated_data
        if data.get("permission_scope") is not None:
            consent.permission_scope = [str(c) for c in data["permission_scope"]]
        if data.get("purpose") is not None:
            consent.purpose = data["purpose"]
        if data.get("expires_at") is not None:
            if data["expires_at"] <= timezone.now():
                raise ValidationError({"expires_at": "expires_at must be in the future."})
            consent.expires_at = data["expires_at"]
        consent.save()
        record_audit(
            actor=request.user, action_code="consents.grant",
            resource_type="consent", resource_id=consent.pk, request=request,
            details={"action": "amend", "permission_scope": consent.permission_scope},
        )
        return Response(serializers.ConsentSerializer(consent).data)

    @action(detail=False, methods=["get"], url_path="active")
    def active(self, request):
        """C2 evaluation for the caller: union of ACTIVE permission scopes."""
        services.expire_due()
        user = request.user
        nown = timezone.now()
        rows = models.Consent.objects.filter(
            status="ACTIVE", start_date__lte=nown, expires_at__gt=nown,
        ).select_related("patient_profile", "granted_to")
        if not user.is_admin:
            patient = Patient.objects.filter(user=user).first()
            mine = Q(patient_profile=patient) if patient else Q(pk__in=[])
            named = Q(granted_to=user)
            rows = rows.filter(mine | named)
        codes: set[str] = set()
        for row in rows:
            for c in row.permission_scope or []:
                codes.add(str(c))
        return Response({
            "permission_scope": sorted(codes),
            "count": rows.count(),
        })

    @action(detail=True, methods=["post"], url_path="revoke")
    def revoke(self, request, uid=None):
        if not request.user.has_perm_code("consents.revoke"):
            raise PermissionDenied("Only the patient can revoke consent.")
        consent = self.get_object()
        if not self._is_owner(consent):
            raise PermissionDenied("Only the granting patient can revoke this consent.")
        reason = (request.data or {}).get("reason", "")
        row = services.revoke(consent, actor=request.user)
        record_audit(
            actor=request.user, action_code="consents.revoke",
            resource_type="consent", resource_id=row.pk, request=request,
            details={"reason": str(reason)[:500]},
        )
        _event(request.user, "CONSENT_REVOKED", {"consent": str(row.uid)})
        return Response(serializers.ConsentSerializer(row).data)

    @action(detail=True, methods=["post"], url_path="renew")
    def renew(self, request, uid=None):
        if not request.user.has_perm_code("consents.grant"):
            raise PermissionDenied("Only the patient can renew consent.")
        consent = self.get_object()
        if not self._is_owner(consent):
            raise PermissionDenied("Only the granting patient can renew this consent.")
        serializer = serializers.ConsentRenewSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        try:
            row = services.renew(
                consent, expires_at=serializer.validated_data["expires_at"], actor=request.user,
            )
        except ValueError as exc:
            raise ValidationError({"expires_at": str(exc)})
        record_audit(
            actor=request.user, action_code="consents.grant",
            resource_type="consent", resource_id=row.pk, request=request,
            details={"action": "renew", "expires_at": row.expires_at.isoformat()},
        )
        _event(request.user, "CONSENT_RENEWED", {"consent": str(row.uid)})
        return Response(serializers.ConsentSerializer(row).data)


def _event(user, event_type, detail=None):
    try:
        SecurityEvent.objects.create(user=user, event_type=event_type, detail=dict(detail or {}))
    except Exception:
        pass