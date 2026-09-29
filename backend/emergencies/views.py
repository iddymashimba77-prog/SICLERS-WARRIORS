"""Emergency API views (approved Stage 4.8, endpoint-matrix §13).

    POST        /api/emergency/requests/          emergency_requests.create (rate-limited, idempotent)
    GET         /api/emergency/requests/          emergency_requests.view (owner/responder)
    GET         /api/emergency/requests/{uid}/    emergency_requests.view
    POST        /api/emergency/requests/{uid}/validate/  emergency_requests.manage
    POST        /api/emergency/requests/{uid}/respond/   emergency_requests.manage (C)
    POST        /api/emergency/requests/{uid}/escalate/  emergency_requests.manage
    POST        /api/emergency/requests/{uid}/resolve/   emergency_requests.resolve
    POST        /api/emergency/requests/{uid}/cancel/    owner/operator
    GET         /api/emergency/access-grants/     C10 patient context
    GET         /api/admin/emergency/             SUP/ADM monitoring (C4, FR-EMG-005/006)

Deny by default: a caller only ever sees requests they own or actively respond
to; there is no EMERGENCY=BYPASS-ALL rule (§16). Every request created by a
patient is that patient's self; staff/hospital may create on behalf of a known
patient (C14 bounded).
"""

import logging

from django.db import IntegrityError, transaction
from django.db.models import Q
from rest_framework import mixins, status as http_status, viewsets
from rest_framework.decorators import action
from rest_framework.exceptions import (
    APIException, NotFound, PermissionDenied, ValidationError,
)
from rest_framework.generics import GenericAPIView, ListAPIView
from rest_framework.parsers import JSONParser
from rest_framework.response import Response

from accounts.models import SecurityEvent, User
from accounts.permissions import IsAdmin, IsAuthenticatedRespectStatus, require
from audit.services import record_audit
from core.pagination import CorePageNumberPagination
from . import models, serializers, services
from .throttles import EmergencyCreateThrottle

logger = logging.getLogger(__name__)


class IdempotencyConflict(APIException):
    status_code = http_status.HTTP_409_CONFLICT
    default_detail = "Duplicate idempotency key."
    default_code = "idempotency_conflict"


def _audit_event(user, event_type):
    try:
        SecurityEvent.objects.create(user=user, event_type=event_type)
    except Exception:
        logger.exception("SecurityEvent write failed (non-blocking): %s", event_type)


class EmergencyRequestViewSet(
    mixins.ListModelMixin,
    mixins.RetrieveModelMixin,
    viewsets.GenericViewSet,
):
    lookup_field = "uid"
    serializer_class = serializers.EmergencyRequestSerializer
    permission_classes = [IsAuthenticatedRespectStatus, require("emergency_requests.view")]
    parser_classes = [JSONParser]
    pagination_class = CorePageNumberPagination

    def get_serializer_class(self):
        # Detail carries the responder timeline (EMG-004); list stays lean.
        if getattr(self, "action", None) == "retrieve":
            return serializers.EmergencyDetailSerializer
        return serializers.EmergencyRequestSerializer

    def retrieve(self, request, *args, **kwargs):
        """Read one request + responder timeline; access is audited (FR-EMG-006)."""
        instance = self.get_object()
        record_audit(
            actor=request.user, action_code="emergency_requests.view",
            resource_type="emergency_request", resource_id=instance.pk,
            request=request,
        )
        _audit_event(request.user, "EMERGENCY_VIEWED")
        serializer = self.get_serializer(instance)
        return Response(serializer.data)

    def initial(self, request, *args, **kwargs):
        super().initial(request, *args, **kwargs)
        if getattr(self, "action", None) != "create":
            return

    def get_throttles(self):
        if getattr(self, "action", None) == "create":
            return [EmergencyCreateThrottle()]
        return []

    def get_queryset(self):
        user = self.request.user
        if not (user and user.is_authenticated):
            return models.EmergencyRequest.objects.none()
        # Stage 4.18: serializer reads requester.email/patient.email per row →
        # select_related (one query, not 2×N).
        base = models.EmergencyRequest.objects.select_related("requester", "patient")
        if user.is_admin or user._has_active_role("HOSPITAL"):
            return base
        return base.filter(
            Q(requester=user) | Q(responders__responder=user)
        ).distinct()

    @transaction.atomic
    def create(self, request):
        user = request.user
        create_allowed = user.has_perm_code("emergency_requests.create")
        if not create_allowed:
            raise PermissionDenied("You may not submit emergency requests.")
        serialized = serializers.EmergencyCreateSerializer(data=request.data)
        serialized.is_valid(raise_exception=True)
        data = serialized.validated_data
        # C14: a patient reports self; staff/hospital may report a known patient.
        if data.get("patient_uid"):
            if not user._has_active_role("HEALTHCARE_STAFF", "HOSPITAL", "DOCTOR"):
                raise PermissionDenied("You may only create an emergency for yourself.")
            patient = User.objects.get(uid=data["patient_uid"])
        else:
            patient = user
        key = data.get("idempotency_key") or request.headers.get("Idempotency-Key", "")
        if key and models.EmergencyRequest.objects.filter(requester=user, idempotency_key=key).exists():
            raise IdempotencyConflict({"idempotency_key": "Duplicate idempotency key."})
        try:
            emergency, grant = services.create_emergency(
                requester=user,
                patient=patient,
                severity=data["severity"],
                type_=data["type"],
                location=data["location"],
                description=data.get("description", ""),
                idempotency_key=key,
            )
        except IntegrityError as exc:
            if key and "idempotency_key" in str(exc):
                raise IdempotencyConflict({"idempotency_key": "Duplicate idempotency key."})
            raise
        record_audit(
            actor=user, action_code="emergency_requests.create",
            resource_type="emergency_request", resource_id=emergency.pk,
            request=request,
            details={"type": emergency.type, "severity": emergency.severity},
        )
        _audit_event(user, "EMERGENCY_CREATED")
        return Response(
            serializers.EmergencyRequestSerializer(emergency).data,
            status=http_status.HTTP_201_CREATED,
        )

    @action(detail=True, methods=["post"], url_path="validate")
    def validate(self, request, uid=None):
        """→ VALIDATING (operator/system telephone + severity checks, §13)."""
        user = request.user
        if not user.has_perm_code("emergency_requests.manage"):
            raise PermissionDenied("You may not validate this request.")
        emergency = self.get_object()
        try:
            services.validate(emergency, actor=user)
        except ValueError as exc:
            raise ValidationError({"status": str(exc)})
        record_audit(
            actor=user, action_code="emergency_requests.validate",
            resource_type="emergency_request", resource_id=emergency.pk,
            request=request,
        )
        _audit_event(user, "EMERGENCY_VALIDATED")
        return Response(serializers.EmergencyRequestSerializer(emergency).data)

    @action(detail=True, methods=["post"], url_path="respond")
    def respond(self, request, uid=None):
        """→ RESPONDING (emergency_requests.manage or existing responder scope)."""
        user = request.user
        emergency = self.get_object()
        has_manage = user.has_perm_code("emergency_requests.manage")
        already_responder = emergency.responders.filter(responder=user).exists()
        if not (has_manage or already_responder):
            raise PermissionDenied("You are not part of this response.")
        role = request.data.get("role", "OTHER")
        role = role if role in {"STAFF", "ADMIN", "CAREGIVER", "DONOR", "OTHER"} else "OTHER"
        services.respond(emergency, user, role=role)
        record_audit(
            actor=user, action_code="emergency_requests.respond",
            resource_type="emergency_request", resource_id=emergency.pk,
            request=request, details={"role": role},
        )
        _audit_event(user, "EMERGENCY_RESPONDED")
        return Response(serializers.EmergencyRequestSerializer(emergency).data)

    @action(detail=True, methods=["post"], url_path="escalate")
    def escalate(self, request, uid=None):
        """→ ESCALATED (emergency_requests.manage)."""
        user = request.user
        if not user.has_perm_code("emergency_requests.manage"):
            raise PermissionDenied("You may not escalate this request.")
        emergency = self.get_object()
        try:
            services.escalate(emergency, actor=user)
        except ValueError as exc:
            raise ValidationError({"status": str(exc)})
        record_audit(
            actor=user, action_code="emergency_requests.escalate",
            resource_type="emergency_request", resource_id=emergency.pk,
            request=request,
        )
        _audit_event(user, "EMERGENCY_ESCALATED")
        return Response(serializers.EmergencyRequestSerializer(emergency).data)

    @action(detail=True, methods=["post"], url_path="resolve")
    def resolve(self, request, uid=None):
        """→ RESOLVED (emergency_requests.resolve)."""
        user = request.user
        if not user.has_perm_code("emergency_requests.resolve"):
            raise PermissionDenied("You may not resolve this request.")
        emergency = self.get_object()
        try:
            services.resolve(emergency, actor=user)
        except ValueError as exc:
            raise ValidationError({"status": str(exc)})
        record_audit(
            actor=user, action_code="emergency_requests.resolve",
            resource_type="emergency_request", resource_id=emergency.pk,
            request=request,
        )
        _audit_event(user, "EMERGENCY_RESOLVED")
        return Response(serializers.EmergencyRequestSerializer(emergency).data)

    @action(detail=True, methods=["post"], url_path="cancel")
    def cancel(self, request, uid=None):
        """→ CANCELLED (owner or operator)."""
        user = request.user
        emergency = self.get_object()
        if emergency.requester_id != user.id and not user.has_perm_code("emergency_requests.manage"):
            raise PermissionDenied("Only the requester (or an operator) can cancel.")
        try:
            services.cancel(emergency, actor=user)
        except ValueError as exc:
            raise ValidationError({"status": str(exc)})
        record_audit(
            actor=user, action_code="emergency_requests.cancel",
            resource_type="emergency_request", resource_id=emergency.pk,
            request=request,
        )
        _audit_event(user, "EMERGENCY_CANCELLED")
        return Response(serializers.EmergencyRequestSerializer(emergency).data)


class EmergencyAccessGrantViewSet(
    mixins.ListModelMixin,
    mixins.RetrieveModelMixin,
    viewsets.GenericViewSet,
):
    """GET /emergency/access-grants — C10 bounded override, patient context."""

    lookup_field = "uid"
    serializer_class = serializers.EmergencyAccessGrantSerializer
    permission_classes = [IsAuthenticatedRespectStatus]
    pagination_class = CorePageNumberPagination

    def get_queryset(self):
        user = self.request.user
        if not (user and user.is_authenticated):
            return models.EmergencyAccessGrant.objects.none()
        # Stage 4.18: the serializers read patient.email/grantee.email per row;
        # select_related turns that into one query instead of 2 per row.
        base = models.EmergencyAccessGrant.objects.select_related("patient", "grantee")
        if user.is_admin:
            return base
        return base.filter(
            Q(patient=user) | Q(grantee=user)
        ).distinct()


class EmergencyAdminMonitoringView(GenericAPIView):
    """GET /admin/emergency — SUP/ADM (C4) live feed (FR-EMG-005/006).

    Stage 4.18: the serializer reads ``requester.email``/``patient.email`` per
    row, so the feed is materialized with ``select_related`` (one query, not
    2×N). The serialized window is bounded (latest 100) so the monitor stays
    cheap under load while ``meta.count`` still reports the full live queue;
    NFR-PERF-002 bounded-feed.
    """

    permission_classes = [IsAuthenticatedRespectStatus, IsAdmin]
    # Hard cap on how many live rows a single monitoring poll serializes.
    MONITOR_FEED_LIMIT = 100

    def get(self, request):
        from django.utils import timezone

        qs = (
            models.EmergencyRequest.objects.select_related("requester", "patient")
            .filter(
                status__in=("CREATED", "VALIDATING", "ACTIVE", "RESPONDING", "ESCALATED"),
            )
            .order_by("-created_at")
        )
        feed = qs[: self.MONITOR_FEED_LIMIT]
        serializer = serializers.EmergencyRequestSerializer(feed, many=True)
        record_audit(
            actor=request.user, action_code="emergency_requests.monitor",
            resource_type="emergency_request_queue", resource_id=None,
            request=request,
        )
        return Response({"data": serializer.data, "meta": {"count": qs.count()}})