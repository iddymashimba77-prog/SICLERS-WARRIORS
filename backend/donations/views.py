"""Donations & payments API views (approved Stage 4.12).

Endpoint baseline (api-design §16/§17, endpoint-matrix §14/§15; base is the
project's ``/api/`` convention as used by every implemented stage):

    GET    /api/campaigns/                     public, verified only (BR-007)
    POST   /api/campaigns/                     campaigns.create -> DRAFT (FR-CAM-001)
    GET    /api/campaigns/{uid}/               public verified / owner any status
    PATCH  /api/campaigns/{uid}/               owner (draft edit / pause)
    POST   /api/campaigns/{uid}/submit/        owner -> PENDING_VERIFICATION
    GET    /api/admin/campaigns/               campaigns.verify (SUP/ADM/VO)
    GET    /api/admin/campaigns/verification-queue/  campaigns.verify
    POST   /api/admin/campaigns/{uid}/verify/  campaigns.verify -> ACTIVE|REJECTED

    POST   /api/donations/                     donations.create + Idempotency-Key
    GET    /api/donations/                     own history (donor) / oversight
    GET    /api/donations/{uid}/               donor or donations.view
    GET    /api/donations/{uid}/receipt/       donor only, COMPLETED only (DON-008)
    POST   /api/admin/donations/{uid}/refund/  donations.refund (SUP/ADM)

    GET    /api/payments/                      own txns / payments.view oversight
    GET    /api/payments/{id}/                 donor or payments.view (FR-PAY-003)
    POST   /api/payments/{id}/retry/           donor, PENDING/FAILED only

    POST   /api/webhooks/payments/{provider}/  signed webhook — the ONLY path
                                               that marks a donation COMPLETED
                                               (BR-008, FR-PAY-004/005)

Security posture: every fallible endpoint is throttled; donation confirmation
happens solely via a verified provider webhook; provider references are
redacted for non-owners; reads deny by default.
"""

import uuid as _uuid

from django.db import transaction
from django.db.models import Q
from drf_spectacular.utils import (
    OpenApiParameter,
    OpenApiTypes,
    extend_schema,
    extend_schema_view,
)
from rest_framework import permissions, status as http_status, viewsets
from rest_framework.decorators import action
from rest_framework.exceptions import NotFound, ValidationError
from rest_framework.parsers import JSONParser
from rest_framework.response import Response
from rest_framework.views import APIView

from accounts.permissions import IsAuthenticatedRespectStatus
from core.pagination import CorePageNumberPagination

from . import models, serializers, services
from .permissions import (
    AdminCampaignAccess,
    CampaignOwnerAccess,
    DonationDetailAccess,
    DonationReceiptAccess,
    DonationRefundAccess,
    PaymentDetailAccess,
    PaymentRetryAccess,
    PaymentWebhookAccess,
    PublicCampaignAccess,
    require,
)
from .throttles import (
    CampaignDonationBurstThrottle,
    CampaignWriteThrottle,
    DonationInitiateThrottle,
)


class CampaignViewSet(viewsets.GenericViewSet):
    """Public campaign stream + owner workflow (FR-CAM-001..003, BR-007)."""

    lookup_field = "uid"
    lookup_url_kwarg = "uid"
    parser_classes = [JSONParser]
    pagination_class = CorePageNumberPagination
    serializer_class = serializers.CampaignPublicSerializer
    permission_classes = [PublicCampaignAccess]

    def get_permissions(self):
        action = getattr(self, "action", None)
        if action == "create":
            return [require("campaigns.create")()]
        if action in ("partial_update", "update", "submit"):
            return [IsAuthenticatedRespectStatus(), CampaignOwnerAccess()]
        return [PublicCampaignAccess()]

    def get_throttles(self):
        action = getattr(self, "action", None)
        if action in ("create", "partial_update", "update", "submit"):
            return [CampaignWriteThrottle()]
        return []

    def get_serializer_class(self):
        action = getattr(self, "action", None)
        if action == "create":
            return serializers.CampaignCreateSerializer
        if action in ("partial_update", "update"):
            return serializers.CampaignUpdateSerializer
        return serializers.CampaignPublicSerializer

    def _base_queryset(self):
        return models.Campaign.objects.select_related("owner").exclude(
            deleted_at__isnull=False,
        )

    def get_queryset(self):
        # Public list: verified/closed campaigns only (BR-007).
        return self._base_queryset().filter(
            status__in=[models.CampaignStatus.ACTIVE, models.CampaignStatus.CLOSED],
        )

    def get_object(self):
        try:
            _uuid.UUID(str(self.kwargs[self.lookup_url_kwarg]))
        except ValueError:
            raise NotFound("Not found.")
        user = self.request.user
        is_owner = bool(user and user.is_authenticated)
        qs = self._base_queryset().filter(
            **{self.lookup_field: self.kwargs[self.lookup_url_kwarg]},
        )
        if is_owner:
            qs = qs.filter(
                Q(status__in=sorted(PublicCampaignAccess.PUBLIC_STATUSES))
                | Q(owner=user)
            )
        else:
            qs = qs.filter(status__in=sorted(PublicCampaignAccess.PUBLIC_STATUSES))
        obj = qs.first()
        if obj is None:
            raise NotFound("Not found.")
        self.check_object_permissions(self.request, obj)
        return obj

    def list(self, request):
        qs = self.get_queryset()
        query = (request.query_params.get("q") or request.query_params.get("search") or "").strip()
        if query:
            qs = qs.filter(Q(title__icontains=query) | Q(description__icontains=query))
        qs = qs.order_by("-created_at")
        page = self.paginate_queryset(qs)
        serializer = serializers.CampaignPublicSerializer(
            page, many=True, context={"request": request},
        )
        return self.get_paginated_response(serializer.data)

    def retrieve(self, request, uid=None):
        obj = self.get_object()
        is_owner = bool(request.user.is_authenticated and obj.owner_id == request.user.pk)
        serializer_class = serializers.CampaignOwnerSerializer if is_owner \
            else serializers.CampaignPublicSerializer
        return Response(serializer_class(obj, context={"request": request}).data)

    @transaction.atomic
    def create(self, request):
        serializer = serializers.CampaignCreateSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        data = serializer.validated_data
        campaign = services.create_campaign(
            owner=request.user, title=data["title"],
            description=data.get("description", ""), goal_amount=data["goal_amount"],
            currency=data["currency"],
        )
        return Response(
            serializers.CampaignOwnerSerializer(campaign, context={"request": request}).data,
            status=http_status.HTTP_201_CREATED,
        )

    @transaction.atomic
    def partial_update(self, request, uid=None):
        obj = self.get_object()
        serializer = serializers.CampaignUpdateSerializer(data=request.data, partial=True)
        serializer.is_valid(raise_exception=True)
        data = serializer.validated_data
        campaign = services.update_campaign(
            obj, actor=request.user,
            title=data.get("title", obj.title),
            description=data.get("description", obj.description),
            goal_amount=data.get("goal_amount", obj.goal_amount),
            pause=data.get("pause", False),
        )
        return Response(
            serializers.CampaignOwnerSerializer(campaign, context={"request": request}).data,
        )

    def update(self, request, uid=None):
        return self.partial_update(request, uid=uid)

    @action(detail=True, methods=["post"], url_path="submit")
    @transaction.atomic
    def submit(self, request, uid=None):
        obj = self.get_object()
        campaign = services.submit_campaign(obj, actor=request.user)
        return Response(
            serializers.CampaignOwnerSerializer(campaign, context={"request": request}).data,
        )


class AdminCampaignViewSet(viewsets.GenericViewSet):
    """Verification/approval surface (campaigns.verify — SUP/ADM/VO)."""

    lookup_field = "uid"
    lookup_url_kwarg = "uid"
    parser_classes = [JSONParser]
    pagination_class = CorePageNumberPagination
    serializer_class = serializers.CampaignAdminSerializer
    permission_classes = [AdminCampaignAccess]

    def _base_queryset(self):
        return models.Campaign.objects.select_related(
            "owner", "verified_by",
        ).exclude(deleted_at__isnull=False)

    def get_queryset(self):
        qs = self._base_queryset()
        status_filter = (self.request.query_params.get("status") or "").strip()
        if status_filter:
            if status_filter not in models.CampaignStatus.values:
                raise ValidationError({"status": "Unsupported status."})
            qs = qs.filter(status=status_filter)
        return qs

    def get_object(self):
        try:
            _uuid.UUID(str(self.kwargs[self.lookup_url_kwarg]))
        except ValueError:
            raise NotFound("Not found.")
        obj = self._base_queryset().filter(
            **{self.lookup_field: self.kwargs[self.lookup_url_kwarg]},
        ).first()
        if obj is None:
            raise NotFound("Not found.")
        self.check_object_permissions(self.request, obj)
        return obj

    def list(self, request):
        page = self.paginate_queryset(self.get_queryset().order_by("-created_at"))
        serializer = serializers.CampaignAdminSerializer(
            page, many=True, context={"request": request},
        )
        return self.get_paginated_response(serializer.data)

    @action(detail=False, methods=["get"], url_path="verification-queue")
    def verification_queue(self, request):
        qs = self._base_queryset().filter(
            status=models.CampaignStatus.PENDING_VERIFICATION,
        ).order_by("-created_at")
        page = self.paginate_queryset(qs)
        serializer = serializers.CampaignAdminSerializer(
            page, many=True, context={"request": request},
        )
        return self.get_paginated_response(serializer.data)

    @action(detail=True, methods=["post"], url_path="verify")
    @transaction.atomic
    def verify(self, request, uid=None):
        obj = self.get_object()
        serializer = serializers.VerifySerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        data = serializer.validated_data
        campaign = services.verify_campaign(
            obj, reviewer=request.user,
            approve=data["approve"], reason=data.get("reason", ""),
        )
        return Response(
            serializers.CampaignAdminSerializer(campaign, context={"request": request}).data,
        )

    @action(detail=True, methods=["post"], url_path="pause")
    @transaction.atomic
    def pause(self, request, uid=None):
        obj = self.get_object()
        serializer = serializers.LifecycleReasonSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        campaign = services.admin_pause_campaign(
            obj, request.user, reason=serializer.validated_data.get("reason", ""),
        )
        return Response(
            serializers.CampaignAdminSerializer(campaign, context={"request": request}).data,
        )

    @action(detail=True, methods=["post"], url_path="close")
    @transaction.atomic
    def close(self, request, uid=None):
        obj = self.get_object()
        serializer = serializers.LifecycleReasonSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        campaign = services.admin_close_campaign(
            obj, request.user, reason=serializer.validated_data.get("reason", ""),
        )
        return Response(
            serializers.CampaignAdminSerializer(campaign, context={"request": request}).data,
        )


@extend_schema_view(
    retrieve=extend_schema(
        parameters=[
            OpenApiParameter(
                name="uid", type=OpenApiTypes.STR, location=OpenApiParameter.PATH,
            ),
        ],
    ),
    receipt=extend_schema(
        parameters=[
            OpenApiParameter(
                name="uid", type=OpenApiTypes.STR, location=OpenApiParameter.PATH,
            ),
        ],
    ),
)
class DonationViewSet(viewsets.GenericViewSet):
    """Donation lifecycle (FR-CAM-004/005, FR-PAY, BR-008)."""

    lookup_field = "uid"
    lookup_url_kwarg = "uid"
    parser_classes = [JSONParser]
    pagination_class = CorePageNumberPagination
    serializer_class = serializers.DonationSerializer
    permission_classes = [IsAuthenticatedRespectStatus, DonationDetailAccess]
    # Swapped per action (receipt -> donor-only).
    object_permission_class = DonationDetailAccess

    def get_permissions(self):
        if getattr(self, "action", None) == "create":
            return [require("donations.create")()]
        return [IsAuthenticatedRespectStatus(), self.object_permission_class()]

    def get_throttles(self):
        if getattr(self, "action", None) == "create":
            return [DonationInitiateThrottle(), CampaignDonationBurstThrottle()]
        return []

    def _base_queryset(self):
        return models.Donation.objects.select_related("campaign", "donor")

    def get_queryset(self):
        qs = self._base_queryset()
        if not self.request.user.has_perm_code("donations.view"):
            qs = qs.filter(donor=self.request.user)
        campaign_uid = (self.request.query_params.get("campaign_uid") or "").strip()
        if campaign_uid:
            qs = qs.filter(campaign__uid=campaign_uid)
        status_filter = (self.request.query_params.get("status") or "").strip()
        if status_filter:
            if status_filter not in models.DonationStatus.values:
                raise ValidationError({"status": "Unsupported status."})
            qs = qs.filter(status=status_filter)
        return qs

    def get_object(self):
        try:
            _uuid.UUID(str(self.kwargs[self.lookup_url_kwarg]))
        except ValueError:
            raise NotFound("Not found.")
        obj = self._base_queryset().filter(
            **{self.lookup_field: self.kwargs[self.lookup_url_kwarg]},
        ).first()
        if obj is None:
            raise NotFound("Not found.")
        if not self.object_permission_class().has_object_permission(self.request, self, obj):
            raise NotFound("Not found.")
        return obj

    def list(self, request):
        page = self.paginate_queryset(self.get_queryset().order_by("-created_at"))
        serializer = serializers.DonationSerializer(
            page, many=True, context={"request": request},
        )
        return self.get_paginated_response(serializer.data)

    def retrieve(self, request, uid=None):
        obj = self.get_object()
        return Response(serializers.DonationSerializer(obj, context={"request": request}).data)

    @transaction.atomic
    def create(self, request):
        key = request.META.get("HTTP_IDEMPOTENCY_KEY", "") or ""
        serializer = serializers.DonationCreateSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        data = serializer.validated_data

        replay = False
        if key:
            existing = models.Donation.objects.filter(idempotency_key=key).first()
            replay = existing is not None and existing.donor_id == request.user.pk

        try:
            donation, _txn = services.initiate_donation(
                donor=request.user, campaign_uid=str(data["campaign_uid"]),
                amount=data["amount"], currency=data["currency"], provider=data["provider"],
                idempotency_key=key, request=request,
            )
        except services.ProviderUnavailable:
            # Stage 4.20: a provider-initiate outage must NOT roll the whole
            # attempt back. The service already wrote a FAILED donation +
            # FAILURE audit inside its own atomic block; catching here keeps
            # those commits intact (the donor sees the failed attempt and can
            # retry from history) while the client still gets a fail-locked
            # 503 SERVICE_UNAVAILABLE (envelope re-raises nothing).
            failed = None
            if key:
                failed = models.Donation.objects.filter(
                    idempotency_key=key, donor=request.user,
                ).first()
            if failed is None:
                raise
            return Response(
                serializers.DonationSerializer(failed, context={"request": request}).data,
                status=http_status.HTTP_503_SERVICE_UNAVAILABLE,
            )

        return Response(
            serializers.DonationSerializer(donation, context={"request": request}).data,
            status=http_status.HTTP_200_OK if replay else http_status.HTTP_201_CREATED,
        )

    @action(detail=True, methods=["get"], url_path="receipt")
    def receipt(self, request, uid=None):
        self.object_permission_class = DonationReceiptAccess
        obj = self.get_object()
        if obj.status != models.DonationStatus.COMPLETED:
            raise ValidationError(
                {"receipt": "Receipts are only available after the donation is confirmed."}
            )
        return Response(
            serializers.ReceiptSerializer({"donation": obj}).data
        )


class AdminDonationViewSet(viewsets.GenericViewSet):
    """SUP/ADM oversight surface (ADMIN-3, FR-CAM-006, FR-PAY-004).

    GET    /api/admin/donations/                donations.view      — ledger list
    POST   /api/admin/donations/{uid}/refund/   donations.refund    — refund
    """

    lookup_field = "uid"
    lookup_url_kwarg = "uid"
    parser_classes = [JSONParser]
    serializer_class = serializers.AdminDonationSerializer
    pagination_class = CorePageNumberPagination

    def get_permissions(self):
        if getattr(self, "action", None) == "list":
            return [IsAuthenticatedRespectStatus(), AdminFinancialAccess()]
        return [IsAuthenticatedRespectStatus(), DonationRefundAccess()]

    def _base_queryset(self):
        return models.Donation.objects.select_related("campaign", "donor")

    def get_queryset(self):
        qs = self._base_queryset()
        status_filter = (self.request.query_params.get("status") or "").strip().upper()
        if status_filter:
            if status_filter not in models.DonationStatus.values:
                raise ValidationError({"status": "Unsupported status."})
            qs = qs.filter(status=status_filter)
        return qs

    def get_object(self):
        try:
            _uuid.UUID(str(self.kwargs[self.lookup_url_kwarg]))
        except ValueError:
            raise NotFound("Not found.")
        obj = self._base_queryset().filter(
            **{self.lookup_field: self.kwargs[self.lookup_url_kwarg]},
        ).first()
        if obj is None:
            raise NotFound("Not found.")
        self.check_object_permissions(self.request, obj)
        return obj

    def list(self, request):
        page = self.paginate_queryset(self.get_queryset().order_by("-created_at"))
        serializer = serializers.AdminDonationSerializer(
            page, many=True, context={"request": request},
        )
        return self.get_paginated_response(serializer.data)

    @action(detail=True, methods=["post"], url_path="refund")
    @transaction.atomic
    def refund(self, request, uid=None):
        obj = self.get_object()
        serializer = serializers.RefundInputSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        data = serializer.validated_data
        refund = services.refund_donation(
            request.user, obj, reason=data["reason"], amount=data.get("amount"),
            request=request,
        )
        return Response(
            serializers.RefundSerializer(refund).data,
            status=http_status.HTTP_201_CREATED,
        )


@extend_schema_view(
    retrieve=extend_schema(
        parameters=[
            OpenApiParameter(
                name="transaction_id", type=OpenApiTypes.STR, location=OpenApiParameter.PATH,
            ),
        ],
    ),
    retry=extend_schema(
        parameters=[
            OpenApiParameter(
                name="transaction_id", type=OpenApiTypes.STR, location=OpenApiParameter.PATH,
            ),
        ],
    ),
)
class PaymentViewSet(viewsets.GenericViewSet):
    """Payment transaction surface (FR-PAY-001..005)."""

    lookup_field = "pk"
    lookup_url_kwarg = "transaction_id"
    parser_classes = [JSONParser]
    pagination_class = CorePageNumberPagination
    serializer_class = serializers.PaymentTransactionSerializer
    permission_classes = [IsAuthenticatedRespectStatus, PaymentDetailAccess]
    object_permission_class = PaymentDetailAccess

    def get_permissions(self):
        return [IsAuthenticatedRespectStatus(), self.object_permission_class()]

    def get_throttles(self):
        if getattr(self, "action", None) == "retry":
            return [DonationInitiateThrottle()]
        return []

    def _base_queryset(self):
        return models.PaymentTransaction.objects.select_related(
            "donation__campaign", "donation__donor",
        )

    def get_queryset(self):
        qs = self._base_queryset()
        if not self.request.user.has_perm_code("payments.view"):
            qs = qs.filter(donation__donor=self.request.user)
        donation_uid = (self.request.query_params.get("donation_uid") or "").strip()
        if donation_uid:
            qs = qs.filter(donation__uid=donation_uid)
        status_filter = (self.request.query_params.get("status") or "").strip()
        if status_filter:
            if status_filter not in models.TransactionStatus.values:
                raise ValidationError({"status": "Unsupported status."})
            qs = qs.filter(status=status_filter)
        return qs

    def _get_transaction(self, transaction_id):
        try:
            int(str(transaction_id))
        except ValueError:
            raise NotFound("Not found.")
        obj = self._base_queryset().filter(pk=int(str(transaction_id))).first()
        if obj is None:
            raise NotFound("Not found.")
        if not self.object_permission_class().has_object_permission(self.request, self, obj):
            raise NotFound("Not found.")
        return obj

    def list(self, request):
        page = self.paginate_queryset(self.get_queryset().order_by("-created_at"))
        serializer = serializers.PaymentTransactionSerializer(
            page, many=True, context={"request": request},
        )
        return self.get_paginated_response(serializer.data)

    def retrieve(self, request, transaction_id=None):
        obj = self._get_transaction(transaction_id)
        return Response(
            serializers.PaymentTransactionSerializer(obj, context={"request": request}).data
        )

    @action(detail=True, methods=["post"], url_path="retry")
    @transaction.atomic
    def retry(self, request, transaction_id=None):
        self.object_permission_class = PaymentRetryAccess
        txn = self._get_transaction(transaction_id)
        donation, new_txn = services.retry_donation(
            request.user, txn.donation, request=request,
        )
        return Response(
            serializers.PaymentTransactionSerializer(new_txn, context={"request": request}).data
        )


@extend_schema(request=None, responses={200: OpenApiTypes.OBJECT})
class PaymentWebhookView(APIView):
    """Provider callback (payments.verify — service-internal, BR-008).

    No JWT/session auth: access is gated by HMAC signature + timestamp TTL +
    optional IP allowlist in ``PaymentWebhookAccess``. Accepts fast (200) and
    delegates confirmation to the (idempotent) service layer.
    """

    authentication_classes = []
    permission_classes = [PaymentWebhookAccess]

    def post(self, request, provider):
        payload = getattr(request, "validated_payload", None)
        if payload is None:  # pragma: no cover — access class sets it
            raise NotFound("Payment provider unavailable.")
        result = services.confirm_payment(provider, payload, request=request)
        return Response(
            {"status": "ok", "donation_uid": result["donation_uid"]},
            status=http_status.HTTP_200_OK,
        )


class AdminFinancialAccess(permissions.BasePermission):
    """donations.view (SUP/ADM/FIN/ORG) + status gate + MFA boundary.

    Read-only financial administration — this class never grants a mutation;
    refund/verification writable surfaces keep their own permission codes.
    """

    message = "You do not have permission to view financial summaries."

    def has_permission(self, request, view):
        user = getattr(request, "user", None)
        if not (user and user.is_authenticated):
            return False
        if not IsAuthenticatedRespectStatus().has_permission(request, view):
            return False
        if not user.has_perm_code("donations.view"):
            return False
        from accounts.mfa import MfaPolicy

        return MfaPolicy().is_compliant(request, user)


@extend_schema(responses={200: OpenApiTypes.OBJECT})
class AdminFinancialSummaryView(APIView):
    """GET /api/admin/financial/summary/ — confirmed-ledger aggregates (§4.16).

    Totals read ONLY from CONFIRMED donation/refund rows (the same source used
    by public campaign totals). No manual payment-status manipulation exists on
    this surface: payment confirmation stays provider-webhook-only (BR-008).
    """

    permission_classes = [IsAuthenticatedRespectStatus, AdminFinancialAccess]

    def get(self, request):
        return Response(services.admin_financial_summary(), status=http_status.HTTP_200_OK)