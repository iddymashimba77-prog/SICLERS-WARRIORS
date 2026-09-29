"""Facility API views (approved §6 endpoint surface).

    GET   /api/facilities/            public — verified only (matrix auth=P)
    GET   /api/facilities/{uid}/      authenticated — verified only
    GET/PATCH /api/facilities/me/     HOSPITAL operator (C7) own facility
    POST  /api/admin/facilities/{uid}/verify   VO/ADM (C6)

Facility verification is required before a facility can host blood-request
donations or appear in the venue picker.
"""

from django.utils import timezone
from rest_framework import permissions, status as http_status
from rest_framework.exceptions import NotFound, PermissionDenied, ValidationError
from rest_framework.generics import ListAPIView, RetrieveAPIView, RetrieveUpdateAPIView, GenericAPIView
from rest_framework.parsers import JSONParser
from rest_framework.response import Response

from accounts.models import SecurityEvent
from accounts.permissions import IsAuthenticatedRespectStatus, require
from audit.services import record_audit
from core.pagination import CorePageNumberPagination
from .models import Facility
from .serializers import (
    FacilityAdminSerializer,
    FacilityMeSerializer,
    FacilitySerializer,
    FacilityVerifySerializer,
)


def _audit_event(user, event_type):
    try:
        SecurityEvent.objects.create(user=user, event_type=event_type)
    except Exception:
        pass


class FacilityListView(ListAPIView):
    """GET /facilities — public directory of verified facilities."""

    serializer_class = FacilitySerializer
    permission_classes = [permissions.AllowAny]
    pagination_class = CorePageNumberPagination

    def get_queryset(self):
        return Facility.objects.filter(is_verified=True)


class FacilityDetailView(RetrieveAPIView):
    """GET /facilities/{uid} — verified detail, no clinical data."""

    lookup_field = "uid"
    serializer_class = FacilitySerializer
    permission_classes = [IsAuthenticatedRespectStatus]
    queryset = Facility.objects.filter(is_verified=True)


class FacilityMeView(RetrieveUpdateAPIView):
    """GET/PATCH /facilities/me — HOSPITAL operator profile (C7)."""

    serializer_class = FacilityMeSerializer
    permission_classes = [IsAuthenticatedRespectStatus]
    parser_classes = [JSONParser]

    def _operator_scope(self):
        user = self.request.user
        if not user.is_authenticated or not user._has_active_role("HOSPITAL"):
            raise PermissionDenied("A HOSPITAL operator is required to manage a facility.")
        try:
            return user.operated_facility
        except Facility.DoesNotExist:
            raise NotFound("No facility is linked to your operator account.")

    def get_object(self):
        return self._operator_scope()

    def perform_update(self, serializer):
        facility = serializer.save()
        _audit_event(self.request.user, "PROFILE_UPDATED")


class AdminFacilityListView(ListAPIView):
    """GET /api/admin/facilities/ — review directory (ADMIN-3, facilities.verify).

    VO/ADM/SUP list every filing (pending, verified, unverified) so the
    Organizations admin section is a real backend surface, not a stub. Filters:
    ``status`` (verified|pending), ``q`` (name), ``facility_type``."""

    serializer_class = FacilityAdminSerializer
    permission_classes = [IsAuthenticatedRespectStatus, require("facilities.verify")]
    pagination_class = CorePageNumberPagination

    def get_queryset(self):
        qs = Facility.objects.select_related("operator", "verified_by")
        params = self.request.query_params
        status_filter = (params.get("status") or "").strip().lower()
        if status_filter == "verified":
            qs = qs.filter(is_verified=True)
        elif status_filter == "pending":
            qs = qs.filter(is_verified=False)
        elif status_filter:
            raise ValidationError({"status": "Unsupported status."})
        q = (params.get("q") or "").strip()
        if q:
            qs = qs.filter(name__icontains=q)
        facility_type = (params.get("facility_type") or "").strip().upper()
        if facility_type:
            qs = qs.filter(facility_type=facility_type)
        return qs


class FacilityVerifyView(GenericAPIView):
    """POST /admin/facilities/{uid}/verify — VO/ADM (C6). Reason required when rejecting."""

    lookup_field = "uid"
    permission_classes = [IsAuthenticatedRespectStatus, require("facilities.verify")]
    parser_classes = [JSONParser]
    queryset = Facility.objects.all()

    def post(self, request, uid=None):
        facility = self.get_object()
        data = FacilityVerifySerializer(data=request.data)
        data.is_valid(raise_exception=True)
        validate = data.validated_data
        approve = validate["approve"]
        reason = validate.get("reason", "")
        if not approve and not reason:
            raise ValidationError({"reason": "A rejection reason is required."})
        facility.is_verified = approve
        facility.verified_by = request.user
        facility.verified_at = timezone.now() if approve else None
        facility.save(update_fields=["is_verified", "verified_by", "verified_at", "updated_at"])
        record_audit(
            actor=request.user, action_code="facilities.verify",
            resource_type="facility", resource_id=facility.pk,
            request=request,
            details={"approve": approve, "reason": reason[:500]},
        )
        _audit_event(request.user, "ADMIN_ACTION")
        return Response(
            FacilitySerializer(facility).data
            if approve else {"status": "rejected", "reason": reason},
            status=http_status.HTTP_200_OK,
        )