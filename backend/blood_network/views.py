"""Blood donation & matching API views (approved Stage 4.8).

Endpoint surface (endpoint-matrix §12 + §20):

    GET/PATCH   /api/blood/donors/me/            blood_donors.self_manage (BLD)
    GET         /api/blood/donors/               blood_donors.view (internal, no contact)
    GET/POST    /api/blood/requests/             blood_requests.view/create
    GET         /api/blood/requests/{uid}/       C8/owner (no donor PII)
    POST        /api/blood/requests/{uid}/cancel/       owner
    GET         /api/blood/requests/{uid}/matches/      blood_matches.view (C9)
    POST        /api/blood/requests/{uid}/donation-events/  STA/HOS (C7)
    POST        /api/blood/matches/{id}/respond/        blood_requests.respond (C9)
    POST        /api/admin/blood/requests/{uid}/verify|reject   blood_requests.verify (BR-005)
    POST        /api/admin/blood/run-matching/           blood_matches.run (SUP/ADM)
    GET         /api/admin/blood/verification-queue/     blood_requests.verify

Privacy (BR-005/BR-006): only verified requests are public; donor records and
match payloads carry NO contact information. Idempotency (approved §30):
duplicate POST with the same Idempotency-Key → 409.
"""

import logging

from django.db import transaction
from django.db.utils import IntegrityError
from django.utils import timezone
from drf_spectacular.utils import OpenApiTypes, extend_schema
from rest_framework import mixins, status as http_status, viewsets
from rest_framework.decorators import action
from rest_framework.exceptions import (
    APIException, NotFound, PermissionDenied, ValidationError,
)
from rest_framework.generics import GenericAPIView, ListAPIView, RetrieveUpdateAPIView
from rest_framework.parsers import JSONParser
from rest_framework.response import Response

from accounts.models import SecurityEvent
from accounts.permissions import IsAuthenticatedRespectStatus, require
from audit.services import record_audit
from core.pagination import CorePageNumberPagination
from facilities.models import Facility
from notifications.services import create_notification
from . import models, serializers, services
from .permissions import BloodAccess

logger = logging.getLogger(__name__)


class IdempotencyConflict(APIException):
    """Approved §30: duplicate Idempotency-Key → 409, not a double record."""

    status_code = http_status.HTTP_409_CONFLICT
    default_detail = "Duplicate idempotency key."
    default_code = "idempotency_conflict"


def _audit_event(user, event_type):
    try:
        SecurityEvent.objects.create(user=user, event_type=event_type)
    except Exception:
        logger.exception("SecurityEvent write failed (non-blocking): %s", event_type)


# ---------------------------------------------------------------------------
# Donor profile (BLD self-service, FR-BLD-001..004)
# ---------------------------------------------------------------------------


class BloodDonorMeView(RetrieveUpdateAPIView):
    """GET/PATCH /blood/donors/me — create-or-update own donor profile."""

    serializer_class = serializers.BloodDonorSelfSerializer
    permission_classes = [IsAuthenticatedRespectStatus, require("blood_donors.self_manage")]
    parser_classes = [JSONParser]

    def _profile(self):
        try:
            return self.request.user.blood_donor_profile
        except models.BloodDonor.DoesNotExist:
            return None

    def get_object(self):
        profile = self._profile()
        if profile is None:
            raise NotFound("No blood donor profile yet — PATCH to create one.")
        return profile

    def get(self, request, *args, **kwargs):
        return Response(self.get_serializer(self.get_object()).data)

    @transaction.atomic
    def patch(self, request, *args, **kwargs):
        profile = self._profile()
        serializer = self.get_serializer(profile, data=request.data, partial=True)
        serializer.is_valid(raise_exception=True)
        if profile is None:
            profile = serializer.save(user=request.user)
            event_type = "BLOOD_DONOR_CREATED"
        else:
            serializer.save()
            event_type = "BLOOD_DONOR_UPDATED"
        record_audit(
            actor=request.user, action_code="blood_donors.self_manage",
            resource_type="blood_donor", resource_id=profile.pk,
            request=request,
        )
        _audit_event(request.user, event_type)
        return Response(self.get_serializer(profile).data, status=http_status.HTTP_200_OK)


class BloodDonorListView(ListAPIView):
    """GET /blood/donors — internal donor directory (no public contact data)."""

    serializer_class = serializers.PublicDonorSerializer
    permission_classes = [IsAuthenticatedRespectStatus, require("blood_donors.view")]
    pagination_class = CorePageNumberPagination

    def get_queryset(self):
        qs = models.BloodDonor.objects.filter(is_verified=True)
        city = self.request.query_params.get("city", "").strip()
        if city:
            qs = qs.filter(city__iexact=city)
        blood_group = self.request.query_params.get("blood_group", "").strip()
        if blood_group:
            qs = qs.filter(blood_group__iexact=blood_group)
        return qs.order_by("-donation_count")


# ---------------------------------------------------------------------------
# Blood requests
# ---------------------------------------------------------------------------


class BloodRequestViewSet(
    mixins.ListModelMixin,
    mixins.RetrieveModelMixin,
    mixins.CreateModelMixin,
    viewsets.GenericViewSet,
):
    lookup_field = "uid"
    serializer_class = serializers.BloodRequestSerializer
    permission_classes = [IsAuthenticatedRespectStatus, BloodAccess]
    parser_classes = [JSONParser]
    pagination_class = CorePageNumberPagination

    def _uses_donor_eligible_queryset(self, user) -> bool:
        """Whether the queryset serves the donor-eligible (public) branch.

        Mirrors ``get_queryset`` so the donor-facing list is rendered with the
        PublicBloodRequestSerializer and never leaks requester contact data
        (Stage 4.17 §16 / BR-006 — REAL donor PII disclosure fix).
        """
        if not (user and user.is_authenticated):
            return False
        if user.is_admin or user.is_patient:
            return False
        return bool(getattr(user, "is_blood_donor", False))

    def get_serializer_class(self):
        if getattr(self, "action", None) == "list" and self._uses_donor_eligible_queryset(
            getattr(self.request, "user", None)
        ):
            return serializers.PublicBloodRequestSerializer
        return serializers.BloodRequestSerializer

    def get_queryset(self):
        user = self.request.user
        if not (user and user.is_authenticated):
            return models.BloodRequest.objects.none()
        if user.is_admin:
            return models.BloodRequest.objects.all()
        if user.is_patient:
            return models.BloodRequest.objects.filter(created_by=user)
        if user.is_blood_donor:
            eligible = [
                request.pk
                for request in models.BloodRequest.objects.filter(
                    status__in=("ACTIVE", "MATCHING", "MATCHED"),
                )
                if services.eligible_donor(request, user)
            ]
            return models.BloodRequest.objects.filter(pk__in=eligible).distinct()
        return models.BloodRequest.objects.none()

    def retrieve(self, request, *args, **kwargs):
        """Owner/admin → full row; eligible donor → public subset (C8)."""
        request_obj = self.get_object()
        user = request.user
        is_owner = request_obj.created_by_id == user.id
        if is_owner or user.is_admin:
            return Response(serializers.BloodRequestSerializer(request_obj).data)
        if user.is_blood_donor and services.eligible_donor(request_obj, user):
            return Response(serializers.PublicBloodRequestSerializer(request_obj).data)
        raise PermissionDenied("This request is not available to you.")

    @transaction.atomic
    def perform_create(self, serializer):
        user = self.request.user
        if not (user.is_patient or user.is_admin):
            raise PermissionDenied("Only patients (or administrators) can create blood requests.")
        key = serializer.validated_data.get("idempotency_key") or self.request.headers.get(
            "Idempotency-Key", ""
        )
        if key:
            if models.BloodRequest.objects.filter(created_by=user, idempotency_key=key).exists():
                raise IdempotencyConflict({"idempotency_key": "Duplicate idempotency key."})
        try:
            # Stage 4.20: persist a header-supplied key on the row so a
            # duplicate submission (same key) is caught by the unique column
            # both here and on the DB — previously header keys were only read,
            # never saved, so repeats created 201 duplicates instead of 409.
            request_obj = serializer.save(
                created_by=user,
                patient=user if user.is_patient else user,
                idempotency_key=key or None,
            )
        except IntegrityError as exc:
            if key and "idempotency_key" in str(exc):
                raise IdempotencyConflict({"idempotency_key": "Duplicate idempotency key."})
            raise
        services.record_decision(
            request_obj, decision="SUBMITTED", actor=user,
            from_status="", to_status=request_obj.status,
            details={
                "blood_group_needed": request_obj.blood_group_needed,
                "units": request_obj.units,
                "urgency": request_obj.urgency,
            },
        )
        record_audit(
            actor=user, action_code="blood_requests.create",
            resource_type="blood_request", resource_id=request_obj.pk,
            request=self.request,
            details={"blood_group_needed": request_obj.blood_group_needed, "units": request_obj.units},
        )
        _audit_event(user, "BLOOD_REQUEST_CREATED")

    @action(detail=True, methods=["post"], url_path="cancel")
    def cancel(self, request, uid=None):
        """POST /blood/requests/{uid}/cancel — owner only → CANCELLED (audited)."""
        request_obj = self.get_object()
        user = request.user
        if request_obj.created_by_id != user.id and not user.is_admin:
            raise PermissionDenied("Only the requester can cancel this request.")
        if request_obj.status in ("FULFILLED", "EXPIRED", "CANCELLED", "REJECTED"):
            raise ValidationError({"status": "This request is already closed."})
        reason = request.data.get("reason", "")
        previous_status = request_obj.status
        models.BloodRequest.objects.filter(pk=request_obj.pk).update(
            status="CANCELLED", updated_at=timezone.now(),
        )
        # Stage 4.20: a cancelled request must not leave open matches active —
        # cascade SUGGESTED/NOTIFIED/ACCEPTED → EXPIRED so the match surfaces
        # never show live matches against a closed request (consistency).
        expired_matches = models.BloodMatch.objects.filter(
            request=request_obj,
            status__in=("SUGGESTED", "NOTIFIED", "ACCEPTED"),
        ).update(status="EXPIRED")
        services.record_decision(
            request_obj, decision="CANCELLED", actor=user,
            from_status=previous_status, to_status="CANCELLED",
            reason=str(reason)[:2000],
            details={"expired_matches": expired_matches},
        )
        record_audit(
            actor=user, action_code="blood_requests.cancel",
            resource_type="blood_request", resource_id=request_obj.pk,
            request=request, details={"reason": reason[:500]},
        )
        _audit_event(user, "BLOOD_REQUEST_CANCELLED")
        request_obj.status = "CANCELLED"
        return Response(
            serializers.BloodRequestSerializer(request_obj).data,
            status=http_status.HTTP_200_OK,
        )

    @action(detail=True, methods=["get"], url_path="matches")
    def matches(self, request, uid=None):
        """GET /blood/requests/{uid}/matches — own request (C9) or admin (C4).

        Donor rows are the non-contact PublicDonorSerializer; a donor may only
        read their OWN match on a request (C9).
        """
        request_obj = self.get_object()
        user = request.user
        qs = models.BloodMatch.objects.filter(request=request_obj).select_related("donor").order_by(
            "-match_score", "id"
        )
        if request_obj.created_by_id != user.id:
            if user.is_admin:
                pass
            else:
                try:
                    donor = user.blood_donor_profile
                except models.BloodDonor.DoesNotExist:
                    raise PermissionDenied("Only the requester can view these matches.")
                qs = qs.filter(donor=donor)
                record_audit(
                    actor=user, action_code="blood_matches.view",
                    resource_type="blood_match_request", resource_id=request_obj.pk,
                    request=request,
                )
        page = self.paginate_queryset(qs)
        data = serializers.BloodMatchSerializer(
            page if page is not None else qs, many=True
        ).data
        if page is not None:
            return self.get_paginated_response(data)
        return Response({"data": data, "meta": {}})

    @action(detail=True, methods=["post"], url_path="donation-events")
    def donation_events(self, request, uid=None):
        """POST /blood/requests/{uid}/donation-events — STA/HOS (C7), immutable history.

        C7 is a role-level grant (the STA/HOS patient-attachment condition is a
        consent surface that lands later); the request row is resolved by uid
        rather than the owner-scoped queryset so staff/hospital can record.
        """
        user = request.user
        if not user._has_active_role("HEALTHCARE_STAFF", "HOSPITAL"):
            raise PermissionDenied("Only healthcare staff/hospital may record donations.")
        request_obj = models.BloodRequest.objects.filter(uid=uid).first()
        if request_obj is None:
            raise NotFound("Request not found.")
        serializer = serializers.DonationEventCreateSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        data = serializer.validated_data
        donor = models.BloodDonor.objects.get(pk=data["donor_id"])
        facility = Facility.objects.get(uid=data["facility_uid"])
        # Chain-of-custody (Stage 4.17 §17): a COMPLETED donation must trace to
        # an ACCEPTED match so staff/hospital cannot fabricate a fulfillment
        # from any donor against any request. Non-complete outcomes (deferred/
        # failed) remain recordable without a prior match.
        if data["outcome"] == "COMPLETED":
            has_accepted_match = models.BloodMatch.objects.filter(
                request=request_obj,
                donor=donor,
                status__in=("ACCEPTED", "FULFILLED"),
            ).exists()
            if not has_accepted_match:
                raise ValidationError(
                    {"donor_id": "This donor has no accepted match for this request."}
                )
        request_obj = services.record_donation(
            donor=donor,
            request=request_obj,
            facility=facility,
            units=data["units"],
            donated_at=data["donated_at"],
            outcome=data["outcome"],
            recorded_by=user,
            donation_serial=data.get("donation_serial") or "",
        )
        event = models.BloodDonationEvent.objects.filter(donor=donor).order_by("-created_at").first()
        if event is None:
            raise ValidationError({"non_field_errors": "Donation not recorded."})
        if data["outcome"] == "COMPLETED" and request_obj is not None:
            create_notification(
                recipient=request_obj.created_by,
                type_="BLOOD",
                title="Your blood request has been fulfilled",
                body="The donation was completed. Thank you.",
                related_resource_type="blood_request",
                related_resource_id=str(request_obj.uid),
                delivery_key=f"blood:fulfilled:{event.pk}",
            )
        record_audit(
            actor=user, action_code="blood_donation_events.create",
            resource_type="blood_donation_event", resource_id=event.pk,
            request=request,
            details={"outcome": data["outcome"], "units": data["units"], "donation_serial": event.donation_serial},
        )
        _audit_event(user, "DONATION_RECORDED")
        return Response(
            serializers.BloodDonationEventSerializer(event).data,
            status=http_status.HTTP_201_CREATED,
        )

    @action(detail=True, methods=["get"], url_path="decisions",
            permission_classes=[IsAuthenticatedRespectStatus, BloodAccess],
            parser_classes=[JSONParser])
    def decisions(self, request, uid=None, **kwargs):
        """GET /blood/requests/{uid}/decisions — the append-only trail (FR-BLD-012).

        Scoped through `get_object()`, so the owner/admin read gate applies and an
        ineligible donor is refused before any row is serialized. This is what
        makes "why was my request rejected?" answerable after the fact: the
        `BloodRequest` row only remembers the latest decision.
        """
        request_obj = self.get_object()
        user = request.user
        is_owner = request_obj.created_by_id == user.id
        if not (is_owner or user.is_admin):
            if not (user.is_blood_donor and services.eligible_donor(request_obj, user)):
                raise PermissionDenied("This request is not available to you.")
        rows = request_obj.decisions.select_related("actor").order_by(
            "-decided_at", "-pk",
        )
        return Response(
            serializers.BloodRequestDecisionSerializer(rows, many=True).data,
        )

    @action(detail=False, methods=["get"], url_path="verification-queue")
    def verification_queue(self, request):
        """GET /admin/blood/verification-queue — PENDING_VERIFICATION (BR-005)."""
        page = self.paginate_queryset(
            models.BloodRequest.objects.filter(status="PENDING_VERIFICATION")
        )
        rows = page if page is not None else models.BloodRequest.objects.none()
        data = serializers.BloodRequestSerializer(rows, many=True).data
        if page is not None:
            return self.get_paginated_response(data)
        return Response({"data": data, "meta": {}})


# ---------------------------------------------------------------------------
# Admin verify / reject + matching runner
# ---------------------------------------------------------------------------


@extend_schema(
    request=OpenApiTypes.OBJECT,
    responses=serializers.BloodRequestSerializer,
)
class BloodRequestVerifyView(GenericAPIView):
    """POST /admin/blood/requests/{uid}/verify — VO/ADM (C6, BR-005)."""

    lookup_field = "uid"
    queryset = models.BloodRequest.objects.all()
    serializer_class = serializers.BloodRequestSerializer
    permission_classes = [IsAuthenticatedRespectStatus, require("blood_requests.verify")]
    parser_classes = [JSONParser]

    def post(self, request, uid=None):
        request_obj = self.get_object()
        if request_obj.status != "PENDING_VERIFICATION":
            raise ValidationError({"status": "Only pending requests can be verified."})
        previous_status = request_obj.status
        request_obj.status = "ACTIVE"
        request_obj.verified_by = request.user
        request_obj.verified_at = timezone.now()
        request_obj.save(update_fields=["status", "verified_by", "verified_at", "updated_at"])
        services.record_decision(
            request_obj, decision="VERIFIED", actor=request.user,
            from_status=previous_status, to_status="ACTIVE",
            reason=str((request.data or {}).get("reason", ""))[:2000],
        )
        record_audit(
            actor=request.user, action_code="blood_requests.verify",
            resource_type="blood_request", resource_id=request_obj.pk,
            request=request,
        )
        _audit_event(request.user, "BLOOD_REQUEST_VERIFIED")
        return Response(serializers.BloodRequestSerializer(request_obj).data)


@extend_schema(
    request=OpenApiTypes.OBJECT,
    responses=serializers.BloodRequestSerializer,
)
class BloodRequestRejectView(GenericAPIView):
    """POST /admin/blood/requests/{uid}/reject — VO/ADM (C6, BR-005)."""

    lookup_field = "uid"
    queryset = models.BloodRequest.objects.all()
    serializer_class = serializers.BloodRequestSerializer
    permission_classes = [IsAuthenticatedRespectStatus, require("blood_requests.verify")]
    parser_classes = [JSONParser]

    def post(self, request, uid=None):
        request_obj = self.get_object()
        reason = request.data.get("reason", "").strip()
        if request_obj.status != "PENDING_VERIFICATION":
            raise ValidationError({"status": "Only pending requests can be rejected."})
        if not reason:
            raise ValidationError({"reason": "A rejection reason is required."})
        previous_status = request_obj.status
        request_obj.status = "REJECTED"
        request_obj.verified_by = request.user
        request_obj.verified_at = timezone.now()
        request_obj.rejection_reason = reason
        request_obj.save(update_fields=["status", "verified_by", "verified_at", "rejection_reason", "updated_at"])
        services.record_decision(
            request_obj, decision="REJECTED", actor=request.user,
            from_status=previous_status, to_status="REJECTED", reason=reason[:2000],
        )
        record_audit(
            actor=request.user, action_code="blood_requests.reject",
            resource_type="blood_request", resource_id=request_obj.pk,
            request=request, details={"reason": reason[:500]},
        )
        _audit_event(request.user, "BLOOD_REQUEST_REJECTED")
        return Response(serializers.BloodRequestSerializer(request_obj).data)


@extend_schema(
    request=serializers.BloodMatchRespondSerializer,
    responses=serializers.BloodMatchSerializer,
)
class BloodMatchRespondView(GenericAPIView):
    """POST /blood/matches/{id}/respond — donor C9 own-match response (FR-BLD-009)."""

    permission_classes = [IsAuthenticatedRespectStatus, require("blood_requests.respond")]
    parser_classes = [JSONParser]
    queryset = models.BloodMatch.objects.select_related("request", "donor")
    serializer_class = serializers.BloodMatchSerializer

    def post(self, request, match_id=None):
        if not self.request.user.is_blood_donor:
            raise PermissionDenied("A blood donor identity is required.")
        try:
            match = self.queryset.get(pk=match_id)
        except models.BloodMatch.DoesNotExist:
            raise NotFound("Match not found.")
        if match.donor.user_id != request.user.id:
            raise PermissionDenied("This match does not belong to you.")
        serializer = serializers.BloodMatchRespondSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        accept = serializer.validated_data["action"] == "ACCEPT"
        try:
            match = services.respond_to_match(match, match.donor, accept=accept)
        except ValueError as exc:
            raise ValidationError({"status": str(exc)})
        record_audit(
            actor=request.user, action_code="blood_requests.respond",
            resource_type="blood_match", resource_id=match.pk,
            request=request, details={"action": serializer.validated_data["action"]},
        )
        _audit_event(request.user, "BLOOD_MATCH_RESPONDED")
        return Response(serializers.BloodMatchSerializer(match).data)


@extend_schema(
    request=OpenApiTypes.OBJECT,
    responses=OpenApiTypes.OBJECT,
)
class RunMatchingView(GenericAPIView):
    """POST /admin/blood/run-matching — SUP/ADM (C6), FR-BLD-008.

    Optional body ``{"request_uid": "..."}`` runs one request; an empty body
    runs the matcher across every ACTIVE request. Re-runs are idempotent.
    """

    permission_classes = [IsAuthenticatedRespectStatus, require("blood_matches.run")]
    parser_classes = [JSONParser]
    queryset = models.BloodRequest.objects.all()
    serializer_class = serializers.BloodRequestSerializer

    def post(self, request):
        request_uid = (request.data or {}).get("request_uid")
        if request_uid:
            request_obj = models.BloodRequest.objects.filter(uid=request_uid).first()
            if request_obj is None:
                raise NotFound("Request not found.")
            created = services.run_matching(request_obj, actor=request.user)
            counts = {str(request_obj.uid): len(created)}
        else:
            counts = services.run_matching_for_all(actor=request.user)
        record_audit(
            actor=request.user, action_code="blood_matches.run",
            resource_type="blood_request_count", resource_id=None,
            request=request, details={"created_counts": counts},
        )
        _audit_event(request.user, "BLOOD_MATCH_RUN")
        return Response({"created": counts})