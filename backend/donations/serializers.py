"""Donations / payments serializers (approved Stage 4.12).

Data boundary (§ api-design §16/§17, endpoint-matrix §14/§15):
* Public campaign surface returns only verified campaigns (BR-007) and never
  exposes owner email/phone/PHI (``uid + display_name`` per the community
  convention).
* Donation/payment projections expose the payer-facing ``redacted_ref``
  unless the caller holds ``payments.view`` (SUP/ADM/FIN/ORG), in which case
  the full provider reference is returned for reconciliation.
* Receipts are donor-only and produced only for COMPLETED donations (DON-008).
"""

from decimal import Decimal

from rest_framework import serializers

from community.sanitizers import sanitize_html
from community.serializers import display_name

from . import models

TITLE_MAX = 120
DESCRIPTION_MAX = 20000
REASON_MAX = 500
AMOUNT_MAX = Decimal("99999999.99")


class UserBriefSerializer(serializers.Serializer):
    """Stable identity projection (never email/phone/PHI)."""

    uid = serializers.UUIDField(read_only=True)
    display_name = serializers.SerializerMethodField()

    def get_display_name(self, obj) -> str:
        return display_name(obj)


class CampaignBriefSerializer(serializers.ModelSerializer):
    class Meta:
        model = models.Campaign
        fields = [
            "uid", "title", "goal_amount", "raised_amount", "currency",
            "status", "progress",
        ]
        read_only_fields = fields


class CampaignPublicSerializer(serializers.ModelSerializer):
    """Public verified-campaign projection (FR-CAM-003, BR-007)."""

    owner = UserBriefSerializer(read_only=True)
    progress = serializers.FloatField(read_only=True)

    class Meta:
        model = models.Campaign
        fields = [
            "uid", "title", "description", "goal_amount", "raised_amount",
            "currency", "status", "progress", "owner", "created_at",
        ]
        read_only_fields = fields


class CampaignOwnerSerializer(CampaignPublicSerializer):
    """Owner projection — adds the rejection/verification milestones."""

    is_owner = serializers.SerializerMethodField()

    class Meta:
        model = models.Campaign
        fields = CampaignPublicSerializer.Meta.fields + [
            "rejection_reason", "note", "start_date", "end_date", "is_owner",
        ]
        read_only_fields = fields

    def get_is_owner(self, obj) -> bool:
        request = self.context.get("request")
        return bool(
            request and request.user.is_authenticated and obj.owner_id == request.user.pk
        )


class CampaignAdminSerializer(CampaignOwnerSerializer):
    """Reviewer projection (campaigns.verify) — full workflow state."""

    verified_by = UserBriefSerializer(read_only=True)

    class Meta:
        model = models.Campaign
        fields = CampaignOwnerSerializer.Meta.fields + ["verified_by", "verified_at"]
        read_only_fields = fields


class CampaignCreateSerializer(serializers.Serializer):
    title = serializers.CharField(max_length=TITLE_MAX)
    description = serializers.CharField(
        max_length=DESCRIPTION_MAX, required=False, allow_blank=True, default="",
    )
    goal_amount = serializers.DecimalField(
        max_digits=14, decimal_places=2, min_value=Decimal("0.01"),
    )
    currency = serializers.CharField(max_length=3, default="TZS")

    def validate_title(self, value):
        cleaned = sanitize_html(value, max_length=TITLE_MAX)
        if not cleaned.strip():
            raise serializers.ValidationError("A title is required.")
        return cleaned

    def validate_description(self, value):
        return sanitize_html(value, max_length=DESCRIPTION_MAX)

    def validate_currency(self, value):
        if value.strip().upper() != "TZS":
            raise serializers.ValidationError("Only TZS is supported at this stage.")
        return value.strip().upper()


class CampaignUpdateSerializer(serializers.Serializer):
    """Owner edit — draft content; pause/resume for active campaigns."""

    title = serializers.CharField(max_length=TITLE_MAX, required=False)
    description = serializers.CharField(max_length=DESCRIPTION_MAX, required=False)
    goal_amount = serializers.DecimalField(
        max_digits=14, decimal_places=2, min_value=Decimal("0.01"),
        required=False,
    )
    pause = serializers.BooleanField(required=False, default=False)

    def validate_title(self, value):
        cleaned = sanitize_html(value, max_length=TITLE_MAX)
        if not cleaned.strip():
            raise serializers.ValidationError("A title is required.")
        return cleaned

    def validate_description(self, value):
        return sanitize_html(value, max_length=DESCRIPTION_MAX)


class VerifySerializer(serializers.Serializer):
    approve = serializers.BooleanField(required=True)
    reason = serializers.CharField(
        max_length=REASON_MAX, required=False, allow_blank=True, default="",
    )

    def validate_reason(self, value):
        return sanitize_html(value, max_length=REASON_MAX)


class LifecycleReasonSerializer(serializers.Serializer):
    reason = serializers.CharField(
        max_length=REASON_MAX, required=False, allow_blank=True, default="",
    )

    def validate_reason(self, value):
        return sanitize_html(value, max_length=REASON_MAX)


class DonationCreateSerializer(serializers.Serializer):
    campaign_uid = serializers.UUIDField()
    amount = serializers.DecimalField(
        max_digits=14, decimal_places=2, min_value=Decimal("0.01"), max_value=AMOUNT_MAX,
    )
    currency = serializers.CharField(max_length=3, default="TZS")
    provider = serializers.ChoiceField(
        choices=[(c, c) for c in models.PaymentProvider.values],
    )

    def validate_currency(self, value):
        if value.strip().upper() != "TZS":
            raise serializers.ValidationError("Only TZS is supported at this stage.")
        return value.strip().upper()


class PaymentTransactionSerializer(serializers.ModelSerializer):
    donation_uid = serializers.UUIDField(source="donation.uid", read_only=True)
    provider_ref = serializers.SerializerMethodField()
    redacted_ref = serializers.CharField(read_only=True)

    class Meta:
        model = models.PaymentTransaction
        fields = [
            "id", "donation_uid", "provider", "status", "amount", "currency",
            "provider_ref", "redacted_ref", "attempt", "created_at",
        ]
        read_only_fields = fields

    def get_provider_ref(self, obj) -> str:
        request = self.context.get("request")
        user = getattr(request, "user", None) if request else None
        if user and user.is_authenticated and user.has_perm_code("payments.view"):
            return obj.provider_ref or ""
        return obj.redacted_ref


class DonationSerializer(serializers.ModelSerializer):
    campaign = CampaignBriefSerializer(read_only=True)
    donor = UserBriefSerializer(read_only=True)
    display_status = serializers.CharField(read_only=True)
    latest_transaction = serializers.SerializerMethodField()

    class Meta:
        model = models.Donation
        fields = [
            "uid", "campaign", "donor", "amount", "currency", "status",
            "display_status", "transaction_ref", "latest_transaction", "created_at",
        ]
        read_only_fields = fields

    def get_latest_transaction(self, obj):
        txn = obj.transactions.select_related("donation").order_by("-attempt", "-pk").first()
        if txn is None:
            return None
        return PaymentTransactionSerializer(txn, context=self.context).data


class ReceiptSerializer(serializers.Serializer):
    """Donor-only receipt (FR-CAM-006, DON-008). Never includes provider secrets."""

    receipt_number = serializers.SerializerMethodField()
    donation_uid = serializers.UUIDField(source="donation.uid", read_only=True)
    campaign_title = serializers.CharField(source="donation.campaign.title", read_only=True)
    amount = serializers.DecimalField(
        source="donation.amount", max_digits=14, decimal_places=2, read_only=True,
    )
    currency = serializers.CharField(source="donation.currency", read_only=True)
    status = serializers.CharField(source="donation.status", read_only=True)
    transaction_ref = serializers.CharField(source="donation.transaction_ref", read_only=True)
    donated_at = serializers.DateTimeField(source="donation.created_at", read_only=True)

    def get_receipt_number(self, obj) -> str:
        donation = obj["donation"]
        return f"WARRIOR-RCP-{donation.transaction_ref}"


class RefundInputSerializer(serializers.Serializer):
    reason = serializers.CharField(max_length=REASON_MAX)
    amount = serializers.DecimalField(
        max_digits=14, decimal_places=2, min_value=Decimal("0.01"),
        required=False,
    )

    def validate_reason(self, value):
        cleaned = sanitize_html(value, max_length=REASON_MAX)
        if not cleaned.strip():
            raise serializers.ValidationError("A reason is required.")
        return cleaned


class RefundSerializer(serializers.ModelSerializer):
    donation_uid = serializers.UUIDField(source="donation.uid", read_only=True)
    initiated_by = UserBriefSerializer(read_only=True)
    approved_by = UserBriefSerializer(read_only=True)

    class Meta:
        model = models.Refund
        fields = [
            "id", "donation_uid", "amount", "reason", "status",
            "initiated_by", "approved_by", "created_at",
        ]
        read_only_fields = fields


class AdminDonationSerializer(serializers.ModelSerializer):
    """Financial-oversight row (ADMIN-3, ``donations.view``).

    Identity (donor) + confirmed-ledger state only — never payer/provider
    secrets beyond visibility the financial-oversight role is approved for."""

    campaign_uid = serializers.UUIDField(source="campaign.uid", read_only=True)
    campaign_title = serializers.CharField(source="campaign.title", read_only=True)
    donor_uid = serializers.UUIDField(source="donor.uid", read_only=True)
    donor_display = serializers.SerializerMethodField()
    is_refunded = serializers.SerializerMethodField()

    class Meta:
        model = models.Donation
        fields = [
            "uid", "campaign_uid", "campaign_title", "donor_uid",
            "donor_display", "amount", "currency", "status",
            "is_refunded", "created_at",
        ]
        read_only_fields = fields

    def get_donor_display(self, obj):
        donor = obj.donor
        return display_name(donor)

    def get_is_refunded(self, obj) -> bool:
        return obj.refunds.filter(
            status__in=[
                models.RefundStatus.REQUESTED,
                models.RefundStatus.APPROVED,
                models.RefundStatus.PROCESSED,
            ],
        ).exists()