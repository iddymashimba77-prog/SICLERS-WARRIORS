"""Donations, payments & financial transparency models (Stage 4.12).

Mapping (database-design.md §13):
    ``organizations`` / ``organization_members``  -> schema-only (no API in
        scope; ``campaigns.organization_id`` is nullable for a future ORG stage)
    ``campaigns``                                -> FR-CAM-001..006, BR-007
    ``donations``                                -> FR-CAM-004/005, BR-008
    ``payment_transactions``                     -> FR-PAY-001..005
    ``refunds``                                  -> FR-PAY-004

Storage statuses are the DB CHECK vocabularies and are canonical. UI display
vocabularies (mobile INITIATED/CONFIRMED, admin VERIFIED/SUSPENDED labels) are
mapped on top and never stored.
"""
import uuid

from decimal import Decimal


def _default_transaction_ref():
    return uuid.uuid4().hex[:32]

from django.conf import settings
from django.db import models
from django.utils import timezone


class CampaignStatus(models.TextChoices):
    DRAFT = "DRAFT", "Draft"
    PENDING_VERIFICATION = "PENDING_VERIFICATION", "Pending verification"
    ACTIVE = "ACTIVE", "Active"
    PAUSED = "PAUSED", "Paused"
    CLOSED = "CLOSED", "Closed"
    REJECTED = "REJECTED", "Rejected"


class DonationStatus(models.TextChoices):
    PENDING = "PENDING", "Pending"
    COMPLETED = "COMPLETED", "Completed"
    FAILED = "FAILED", "Failed"
    REFUNDED = "REFUNDED", "Refunded"
    CANCELLED = "CANCELLED", "Cancelled"


class TransactionStatus(models.TextChoices):
    PENDING = "PENDING", "Pending"
    SUCCESS = "SUCCESS", "Success"
    FAILED = "FAILED", "Failed"
    REFUNDED = "REFUNDED", "Refunded"


class RefundStatus(models.TextChoices):
    REQUESTED = "REQUESTED", "Requested"
    APPROVED = "APPROVED", "Approved"
    PROCESSED = "PROCESSED", "Processed"
    REJECTED = "REJECTED", "Rejected"


class PaymentProvider(models.TextChoices):
    M_PESA = "M_PESA", "M-Pesa"
    AIRTEL = "AIRTEL", "Airtel Money"
    TIGO = "TIGO", "Tigo Pesa"
    CLICKPESA = "CLICKPESA", "ClickPesa"
    SELCOM = "SELCOM", "Selcom"


CURRENCY_DEFAULT = "TZS"

# Terminal / actionable status sets (shared by services + views).
_TERMINAL_DONATION = {DonationStatus.COMPLETED, DonationStatus.REFUNDED}
_TERMINAL_TRANSACTION = {TransactionStatus.SUCCESS, TransactionStatus.FAILED, TransactionStatus.REFUNDED}


class TimestampedModel(models.Model):
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        abstract = True


class Organization(TimestampedModel):
    """Schema-only: no Organization API is in scope (future ORG stage).

    Mirrors the ``organizations`` table in the donations/payments ERD so that
    ``campaigns.organization_id`` can be satisfied now without inventing
    endpoints the approved API design does not define.
    """

    uid = models.UUIDField(default=uuid.uuid4, editable=False, unique=True)
    name = models.CharField(max_length=200)
    org_type = models.CharField(max_length=40, default="NGO")
    contact_email = models.EmailField(blank=True, default="")
    is_verified = models.BooleanField(default=False)
    verified_by = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.PROTECT, null=True, blank=True,
        related_name="+",
    )
    verified_at = models.DateTimeField(null=True, blank=True)

    class Meta:
        db_table = "organizations"
        ordering = ["name"]

    def __str__(self):
        return self.name


class OrganizationMember(TimestampedModel):
    """Schema-only organizational membership (ERD ``organization_members``)."""

    organization = models.ForeignKey(Organization, on_delete=models.PROTECT, related_name="members")
    user = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.PROTECT, related_name="organization_memberships")
    member_role = models.CharField(max_length=40, default="STAFF")
    is_active = models.BooleanField(default=True)
    granted_by = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.PROTECT, null=True, blank=True,
        related_name="+",
    )

    class Meta:
        db_table = "organization_members"
        constraints = [
            models.UniqueConstraint(fields=["organization", "user"], name="org_member_uniq"),
        ]

    def __str__(self):
        return f"{self.user_id} @ {self.organization_id}"


class Campaign(TimestampedModel):
    KEY_FIELDS = {"title", "description", "goal_amount"}

    uid = models.UUIDField(default=uuid.uuid4, editable=False, unique=True)
    owner = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.PROTECT, related_name="campaigns",
    )
    organization = models.ForeignKey(
        Organization, on_delete=models.PROTECT, related_name="campaigns",
        null=True, blank=True,
    )
    title = models.CharField(max_length=120)
    description = models.TextField(blank=True, default="")
    goal_amount = models.DecimalField(max_digits=14, decimal_places=2)
    raised_amount = models.DecimalField(
        max_digits=14, decimal_places=2, default=Decimal("0.00"),
        help_text="Materialised counter of confirmed (COMPLETED) donations, "
                  "decremented on refunds. Aggregations remain the source of truth "
                  "for reporting.",
    )
    currency = models.CharField(max_length=3, default=CURRENCY_DEFAULT)
    status = models.CharField(
        max_length=20, choices=CampaignStatus.choices, default=CampaignStatus.DRAFT,
    )
    verified_by = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.PROTECT, null=True, blank=True,
        related_name="+",
    )
    verified_at = models.DateTimeField(null=True, blank=True)
    rejection_reason = models.TextField(blank=True, default="")
    start_date = models.DateField(null=True, blank=True)
    end_date = models.DateField(null=True, blank=True)
    deleted_at = models.DateTimeField(null=True, blank=True)
    # Optional workflow levers a reviewer may set on approval.
    note = models.TextField(blank=True, default="")

    class Meta:
        db_table = "campaigns"
        ordering = ["-created_at"]
        constraints = [
            models.CheckConstraint(
                condition=models.Q(goal_amount__gt=0),
                name="don_campaign_goal_positive",
            ),
            models.CheckConstraint(
                condition=models.Q(raised_amount__gte=0),
                name="don_campaign_raised_nonnegative",
            ),
            models.CheckConstraint(
                condition=models.Q(status__in=CampaignStatus.values),
                name="don_campaign_status_check",
            ),
        ]
        indexes = [
            models.Index(fields=["status"], name="don_campaign_status_idx"),
            models.Index(fields=["owner", "-created_at"], name="don_campaign_owner_idx"),
        ]

    def __str__(self):
        return self.title

    @property
    def is_verified(self) -> bool:
        return self.verified_at is not None and self.status == CampaignStatus.ACTIVE

    @property
    def progress(self) -> float:
        if not self.goal_amount:
            return 0.0
        return round(float(self.raised_amount or 0) / float(self.goal_amount) * 100, 2)

    @property
    def public_status(self):
        """Display status for the public stream (FR-CAM-003: verified only)."""
        if self.status == CampaignStatus.ACTIVE:
            return CampaignStatus.ACTIVE
        if self.status == CampaignStatus.CLOSED:
            return CampaignStatus.CLOSED
        return None


class Donation(TimestampedModel):
    uid = models.UUIDField(default=uuid.uuid4, editable=False, unique=True)
    campaign = models.ForeignKey(Campaign, on_delete=models.PROTECT, related_name="donations")
    donor = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.PROTECT, related_name="donations",
    )
    amount = models.DecimalField(max_digits=14, decimal_places=2)
    currency = models.CharField(max_length=3, default=CURRENCY_DEFAULT)
    status = models.CharField(
        max_length=20, choices=DonationStatus.choices, default=DonationStatus.PENDING,
    )
    transaction_ref = models.CharField(
        max_length=40, unique=True, default=_default_transaction_ref,
    )
    idempotency_key = models.CharField(max_length=200, unique=True)

    class Meta:
        db_table = "donations"
        ordering = ["-created_at"]
        constraints = [
            models.CheckConstraint(
                condition=models.Q(amount__gt=0),
                name="don_donation_amount_positive",
            ),
            models.CheckConstraint(
                condition=models.Q(status__in=DonationStatus.values),
                name="don_donation_status_check",
            ),
        ]
        indexes = [
            models.Index(fields=["donor", "-created_at"], name="don_donation_donor_idx"),
            models.Index(fields=["campaign", "status"], name="don_donation_campaign_status"),
        ]

    def __str__(self):
        return f"{self.uid} {self.amount} {self.currency}"

    @property
    def is_terminal(self) -> bool:
        return self.status in _TERMINAL_DONATION

    @property
    def display_status(self):
        """Mobile display vocabulary (INITIATED / CONFIRMED / … state badge)."""
        if self.status == DonationStatus.COMPLETED:
            return "CONFIRMED"
        if self.status == DonationStatus.PENDING:
            return "INITIATED"
        return self.status


class PaymentTransaction(TimestampedModel):
    donation = models.ForeignKey(Donation, on_delete=models.PROTECT, related_name="transactions")
    provider = models.CharField(max_length=12, choices=PaymentProvider.choices)
    provider_ref = models.CharField(max_length=120, unique=True, null=True, blank=True)
    status = models.CharField(
        max_length=10, choices=TransactionStatus.choices, default=TransactionStatus.PENDING,
    )
    amount = models.DecimalField(max_digits=14, decimal_places=2)
    currency = models.CharField(max_length=3, default=CURRENCY_DEFAULT)
    payload = models.JSONField(default=dict, blank=True, help_text="Redacted provider payload (no PAN/tokens).")
    attempt = models.PositiveIntegerField(default=1)

    class Meta:
        db_table = "payment_transactions"
        ordering = ["-created_at"]
        constraints = [
            models.CheckConstraint(
                condition=models.Q(status__in=TransactionStatus.values),
                name="don_paytxn_status_check",
            ),
            models.CheckConstraint(
                condition=models.Q(provider__in=PaymentProvider.values),
                name="don_paytxn_provider_check",
            ),
        ]
        indexes = [
            models.Index(fields=["status", "created_at"], name="don_paytxn_status_idx"),
        ]

    def __str__(self):
        return f"{self.provider}:{self.provider_ref or '(unref)'} {self.status} {self.amount}"

    @property
    def is_terminal(self) -> bool:
        return self.status in _TERMINAL_TRANSACTION

    @property
    def redacted_ref(self) -> str:
        """Payer-facing reference with the reconcilable suffix redacted."""
        if not self.provider_ref:
            return ""
        ref = self.provider_ref
        if len(ref) <= 7:
            return ref
        return f"{ref[:4]}…{ref[-4:]}"


class Refund(TimestampedModel):
    donation = models.ForeignKey(Donation, on_delete=models.PROTECT, related_name="refunds")
    transaction = models.ForeignKey(
        PaymentTransaction, on_delete=models.PROTECT, null=True, blank=True,
        related_name="+",
    )
    amount = models.DecimalField(max_digits=14, decimal_places=2)
    reason = models.TextField()
    initiated_by = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.PROTECT, related_name="+",
    )
    approved_by = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.PROTECT, null=True, blank=True,
        related_name="+",
    )
    status = models.CharField(
        max_length=10, choices=RefundStatus.choices, default=RefundStatus.REQUESTED,
    )

    class Meta:
        db_table = "refunds"
        ordering = ["-created_at"]
        constraints = [
            models.CheckConstraint(
                condition=models.Q(amount__gt=0),
                name="don_refund_amount_positive",
            ),
            models.CheckConstraint(
                condition=models.Q(status__in=RefundStatus.values),
                name="don_refund_status_check",
            ),
        ]

    def __str__(self):
        return f"{self.donation_id} {self.amount} {self.status}"


def close_expired_campaigns(now=None):
    """Lifecycle helper (management command / scheduler).

    ACTIVE campaigns past ``end_date`` become CLOSED. Returns the count.
    """
    now = now or timezone.now()
    past = models.Q(end_date__lt=now.date())
    live = ~models.Q(end_date=None)
    updated = Campaign.objects.filter(
        live & past, status=CampaignStatus.ACTIVE,
    ).update(status=CampaignStatus.CLOSED, updated_at=timezone.now())
    return updated