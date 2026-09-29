"""Donations payment business logic (Stage 4.12).

Implements the approved workflows from api-design §16/§17 against the
database-design §13 tables. Highlights:

* Campaigns start DRAFT → submit → PENDING_VERIFICATION → admin VERIFIED
  (ACTIVE) or REJECTED (FR-CAM-001/002, BR-007).
* Donations are created PENDING with a caller-supplied ``Idempotency-Key``
  (FR-CAM-004) and CONFIRMED (donation COMPLETED) ONLY by a verified provider
  webhook (BR-008) — never by the client.
* Provider webhooks are idempotent: duplicate ``provider_ref`` callbacks are
  accepted and ignored (replay protection, §22).
* Refunds flow REQUESTED → APPROVED → PROCESSED (FR-CAM-006, FR-PAY-004) and
  are SUP/ADM-only, single-person approval in this stage (co-sign deferred).
"""

import logging
from decimal import Decimal

from django.db import transaction
from django.db.models import F, Sum
from django.db.models.functions import Greatest
from django.utils import timezone

from audit.services import record_audit
from notifications.services import create_notification
from rest_framework.exceptions import APIException, ValidationError

from .models import (
    Campaign,
    CampaignStatus,
    Donation,
    DonationStatus,
    PaymentTransaction,
    PaymentProvider,
    Refund,
    RefundStatus,
    TransactionStatus,
)
from .providers import PaymentProviderError, get_provider

logger = logging.getLogger(__name__)

NOTIFICATION_TYPE = "PAYMENT"


class ProviderUnavailable(APIException):
    status_code = 503
    default_detail = "Payment provider temporarily unavailable."
    default_code = "provider_unavailable"


class AlreadyRefunded(APIException):
    status_code = 409
    default_detail = "This donation has already been refunded."
    default_code = "already_refunded"


class IdempotencyConflict(APIException):
    """One Idempotency-Key reused by a different donor → 409 CONFLICT.

    Never leaks the identity of the donor who first claimed the key; it only
    rejects the conflicting request (security-design fail-closed + Block 4.20
    idempotency contract).
    """

    status_code = 409
    default_detail = "This Idempotency-Key is already in use by another donor."
    default_code = "idempotency_conflict"


# ---------------------------------------------------------------------------
# Campaign lifecycle (FR-CAM-001/002, BR-007)
# ---------------------------------------------------------------------------

def create_campaign(owner, *, title, description, goal_amount, currency="TZS"):
    if currency != "TZS":
        raise ValidationError({"currency": "Only TZS is supported at this stage."})
    goal = Decimal(str(goal_amount))
    if goal <= 0:
        raise ValidationError({"goal_amount": "Goal amount must be greater than zero."})
    campaign = Campaign.objects.create(
        owner=owner, title=title, description=description,
        goal_amount=goal, currency=currency, status=CampaignStatus.DRAFT,
    )
    record_audit(
        actor=owner, action_code="campaign.create", resource_type="campaign",
        resource_id=campaign.pk,
        details={"title": campaign.title, "goal": str(campaign.goal_amount)},
    )
    return campaign


def update_campaign(campaign, actor, *, title, description, goal_amount, pause):
    """Owner edits.

    Content edits are only allowed on DRAFT campaigns so submitted content
    stays frozen for review (queue integrity). On ACTIVE/PAUSED campaigns the
    only allowed mutation is pausing/resuming (an owner-held stop lever).
    """
    allowed = {CampaignStatus.DRAFT, CampaignStatus.ACTIVE, CampaignStatus.PAUSED}
    if campaign.status not in allowed:
        raise ValidationError(
            {"campaign": f"Campaign in '{campaign.status}' cannot be edited."}
        )

    if campaign.status in {CampaignStatus.ACTIVE, CampaignStatus.PAUSED}:
        goal = campaign.goal_amount
        if title != campaign.title or description != campaign.description:
            raise ValidationError(
                {"campaign": "Content of an active/paused campaign is frozen."}
            )
        if Decimal(str(goal_amount)) != campaign.goal_amount:
            raise ValidationError(
                {"campaign": "Goal of an active/paused campaign is frozen."}
            )
        status = CampaignStatus.ACTIVE if not pause else CampaignStatus.PAUSED
        campaign.status = status
        campaign.save(update_fields=["status", "updated_at"])
    else:  # DRAFT
        if Decimal(str(goal_amount)) <= 0:
            raise ValidationError({"goal_amount": "Goal amount must be greater than zero."})
        campaign.title = title
        campaign.description = description
        campaign.goal_amount = Decimal(str(goal_amount))
        campaign.save(update_fields=["title", "description", "goal_amount", "updated_at"])

    record_audit(
        actor=actor, action_code="campaign.update", resource_type="campaign",
        resource_id=campaign.pk, details={"status": campaign.status},
    )
    return campaign


def pending_review_set(reviewer):
    """Verification-queue querysets by role (VO vs SUP/ADM)."""
    base = Campaign.objects.exclude(status__in={CampaignStatus.CLOSED, CampaignStatus.REJECTED})
    return base


def submit_campaign(campaign, actor):
    """Owner submits a draft/rejected campaign for verification."""
    if campaign.status not in {CampaignStatus.DRAFT, CampaignStatus.REJECTED}:
        raise ValidationError(
            {"campaign": f"Campaign in '{campaign.status}' cannot be submitted."}
        )
    if not campaign.title.strip():
        raise ValidationError({"title": "A title is required."})
    campaign.status = CampaignStatus.PENDING_VERIFICATION
    campaign.rejection_reason = ""
    campaign.save(update_fields=["status", "rejection_reason", "updated_at"])
    record_audit(
        actor=actor, action_code="campaign.submit", resource_type="campaign",
        resource_id=campaign.pk,
    )
    return campaign


def verify_campaign(campaign, reviewer, *, approve, reason=""):
    """Admin/VO approval — the only gate into the public stream (BR-007).
    Approving sets the verified_by/verified_at milestone; rejecting records
    a rejection_reason the owner can read and act on."""
    if campaign.status != CampaignStatus.PENDING_VERIFICATION:
        raise ValidationError(
            {"campaign": "Only PENDING_VERIFICATION campaigns can be verified."}
        )
    if approve:
        campaign.status = CampaignStatus.ACTIVE
        campaign.verified_by = reviewer
        campaign.verified_at = timezone.now()
        campaign.rejection_reason = ""
        campaign.save(
            update_fields=["status", "verified_by", "verified_at", "rejection_reason", "updated_at"]
        )
        record_audit(
            actor=reviewer, action_code="campaign.approve", resource_type="campaign",
            resource_id=campaign.pk, result="SUCCESS",
        )
        if campaign.owner_id and campaign.owner_id != reviewer.pk:
            create_notification(
                recipient=campaign.owner,
                type_=NOTIFICATION_TYPE,
                title="Campaign approved",
                body="Your campaign was approved and is now live.",
                data={"route": "donations", "resource_type": "campaign"},
                related_resource_type="campaign",
                related_resource_id=str(campaign.uid),
                delivery_key=f"campaign:approved:{campaign.uid}",
            )
    else:
        if not reason.strip():
            raise ValidationError({"reason": "A rejection reason is required."})
        campaign.status = CampaignStatus.REJECTED
        campaign.rejection_reason = reason.strip()
        campaign.save(update_fields=["status", "rejection_reason", "updated_at"])
        record_audit(
            actor=reviewer, action_code="campaign.reject", resource_type="campaign",
            resource_id=campaign.pk, result="FAILURE",
            details={"reason": campaign.rejection_reason},
        )
        if campaign.owner_id and campaign.owner_id != reviewer.pk:
            create_notification(
                recipient=campaign.owner,
                type_=NOTIFICATION_TYPE,
                title="Campaign needs review",
                body="Your submitted campaign needs changes before it can go live.",
                data={"route": "donations", "resource_type": "campaign"},
                related_resource_type="campaign",
                related_resource_id=str(campaign.uid),
                delivery_key=f"campaign:rejected:{campaign.uid}",
            )
    return campaign


def close_campaign(campaign, actor):
    """Lifecycle/administrative closure."""
    if campaign.status in {CampaignStatus.CLOSED, CampaignStatus.REJECTED}:
        return campaign
    campaign.status = CampaignStatus.CLOSED
    campaign.save(update_fields=["status", "updated_at"])
    record_audit(
        actor=actor, action_code="campaign.close", resource_type="campaign",
        resource_id=campaign.pk,
    )
    return campaign


# ---------------------------------------------------------------------------
# Donations (FR-CAM-004/005, BR-008)
# ---------------------------------------------------------------------------

def initiate_donation(donor, *, campaign_uid, amount, currency, provider, idempotency_key, request=None):
    """Create a PENDING donation + first payment attempt.

    Idempotency: re-sending the same ``Idempotency-Key`` for the same donor
    returns the existing donation untouched (repeated submits never duplicate);
    the same key used by a different donor is a 409 conflict.
    """
    if not idempotency_key:
        raise ValidationError({"idempotency_key": "Idempotency-Key header is required."})
    if currency != "TZS":
        raise ValidationError({"currency": "Only TZS is supported at this stage."})
    if provider not in {c for c, _ in PaymentProvider.choices}:
        raise ValidationError({"provider": "Unknown payment provider."})

    amount_dec = Decimal(str(amount))
    if amount_dec <= 0:
        raise ValidationError({"amount": "Amount must be greater than zero."})
    if amount_dec > Decimal("99999999.99"):
        raise ValidationError({"amount": "Amount exceeds the maximum supported."})

    try:
        campaign = Campaign.objects.get(uid=campaign_uid, deleted_at=None)
    except (Campaign.DoesNotExist, ValidationError):
        raise ValidationError({"campaign_uid": "Campaign not found."})
    if campaign.status != CampaignStatus.ACTIVE:
        raise ValidationError(
            {"campaign_uid": "Donations are only accepted on verified, active campaigns."}
        )

    existing = Donation.objects.filter(idempotency_key=idempotency_key).first()
    if existing is not None:
        if existing.donor_id != donor.id:
            raise IdempotencyConflict(
                {"idempotency_key": "This Idempotency-Key is already in use by another donor."},
            )
        record_audit(
            actor=donor, action_code="donations.create", resource_type="donation",
            resource_id=existing.pk, result="SUCCESS",
            details={"idempotent": True},
        )
        return existing, existing.transactions.order_by("-attempt", "-pk").first()

    provider_adapter = get_provider(provider)
    failure = None
    with transaction.atomic():
        donation = Donation.objects.create(
            campaign=campaign, donor=donor, amount=amount_dec,
            currency=currency, status=DonationStatus.PENDING,
            idempotency_key=idempotency_key,
        )
        attempt = 1
        try:
            provider_ref = provider_adapter.initiate(
                transaction_ref=donation.transaction_ref,
                amount=str(amount_dec), currency=currency, attempt=attempt,
            )
        except PaymentProviderError as exc:
            logger.warning("provider %s refused initiate: %s", provider, exc)
            # Stage 4.20 (§20/§22): a refused initiate must FAIL CLOSED but
            # stay auditable. Capturing the failure here and materialising the
            # FAILED donation *outside* this atomic keeps the record alive even
            # though the 503 propagates — previously the exception rolled the
            # whole attempt back, silently losing the FAILED row + FAILURE audit.
            failure = (donation, str(exc), attempt)
        else:
            txn = PaymentTransaction.objects.create(
                donation=donation, provider=provider,
                provider_ref=provider_ref, status=TransactionStatus.PENDING,
                amount=amount_dec, currency=currency, attempt=attempt,
            )
            record_audit(
                actor=donor, action_code="payments.initiate", resource_type="donation",
                resource_id=donation.pk,
                details={"provider": provider, "provider_ref": provider_ref, "amount": str(amount_dec)},
            )
            return donation, txn

    if failure is not None:
        donation, error, attempt = failure
        txn = PaymentTransaction.objects.create(
            donation=donation, provider=provider,
            status=TransactionStatus.FAILED, amount=amount_dec,
            currency=currency, attempt=attempt,
        )
        donation.status = DonationStatus.FAILED
        donation.save(update_fields=["status", "updated_at"])
        record_audit(
            actor=donor, action_code="payments.initiate", resource_type="donation",
            resource_id=donation.pk, result="FAILURE",
            details={"provider": provider, "error": error},
        )
        raise ProviderUnavailable("Payment provider temporarily unavailable.")

    return donation, txn


def retry_donation(donor, donation, request=None):
    """Donor retries a PENDING/FAILED donation with a fresh payment attempt."""
    if donation.donor_id != donor.id:
        raise ValidationError({"donation": "You do not own this donation."}, code="permission_denied")
    if donation.is_terminal:
        raise ValidationError(
            {"donation": f"Donation in '{donation.status}' cannot be retried."}
        )
    latest = donation.transactions.order_by("-attempt", "-pk").first()
    attempt = (latest.attempt if latest else 0) + 1
    provider = latest.provider if latest else PaymentProvider.M_PESA
    provider_adapter = get_provider(provider)
    with transaction.atomic():
        try:
            provider_ref = provider_adapter.initiate(
                transaction_ref=donation.transaction_ref,
                amount=str(donation.amount), currency=donation.currency, attempt=attempt,
            )
        except PaymentProviderError as exc:
            raise ProviderUnavailable("Payment provider temporarily unavailable.")
        txn = PaymentTransaction.objects.create(
            donation=donation, provider=provider, provider_ref=provider_ref,
            status=TransactionStatus.PENDING, amount=donation.amount,
            currency=donation.currency, attempt=attempt,
        )
        if donation.status != DonationStatus.PENDING:
            donation.status = DonationStatus.PENDING
            donation.save(update_fields=["status", "updated_at"])
        record_audit(
            actor=donor, action_code="payments.initiate", resource_type="donation",
            resource_id=donation.pk,
            details={"provider": provider, "provider_ref": provider_ref, "attempt": attempt},
        )
    return donation, txn


def confirm_payment(provider_name, payload, request=None):
    """Confirm a payment from a VERIFIED webhook payload (BR-008).

    Idempotent by ``provider_ref``; terminal duplicates return ``"duplicate"``
    without side effects. A success is communicated to the donor as a generic
    PAYMENT notification (never amount/ref in the body).
    """
    event = payload["event"]
    success = event == "payment.success"
    transaction_ref = payload["transaction_ref"]
    provider_ref = payload["provider_ref"]
    webhook_amount = Decimal(str(payload["amount"]))
    webhook_currency = payload.get("currency", "TZS")

    txn = PaymentTransaction.objects.select_related("donation__campaign", "donation__donor").filter(
        provider=provider_name, provider_ref=provider_ref,
    ).first()
    if txn is None:
        donation = Donation.objects.filter(transaction_ref=transaction_ref).select_related("campaign", "donor").first()
        if donation is None:
            record_audit(
                actor=None, action_code="payments.webhook_received", resource_type="payment",
                resource_id=None, result="FAILURE",
                details={"provider": provider_name, "provider_ref": provider_ref, "error": "unknown transaction_ref"},
            )
            raise ValidationError({"webhook": "Unknown transaction reference."})
        txn = donation.transactions.order_by("-attempt", "-pk").first()

    if txn.is_terminal:
        record_audit(
            actor=None, action_code="payments.webhook_received", resource_type="payment",
            resource_id=txn.pk, result="SUCCESS",
            details={"provider": provider_name, "duplicate": True, "status": txn.status},
        )
        return {"status": "duplicate", "donation_uid": str(txn.donation.uid)}

    if txn.amount != webhook_amount or txn.currency != webhook_currency:
        record_audit(
            actor=None, action_code="payments.webhook_received", resource_type="payment",
            resource_id=txn.pk, result="FAILURE",
            details={"provider": provider_name, "error": "amount/currency mismatch"},
        )
        raise ValidationError({"webhook": "Webhook amount does not match the payment."})

    donation = txn.donation
    with transaction.atomic():
        txn = PaymentTransaction.objects.select_for_update().get(pk=txn.pk)
        if not txn.is_terminal:
            txn.status = TransactionStatus.SUCCESS if success else TransactionStatus.FAILED
            txn.save(update_fields=["status", "updated_at"])

        donation = Donation.objects.select_for_update().get(pk=donation.pk)
        if donation.status == DonationStatus.PENDING:
            donation.status = DonationStatus.COMPLETED if success else DonationStatus.FAILED
            donation.save(update_fields=["status", "updated_at"])

        if success and donation.status == DonationStatus.COMPLETED:
            Campaign.objects.filter(pk=donation.campaign_id).update(
                raised_amount=F("raised_amount") + txn.amount,
                updated_at=timezone.now(),
            )
            record_audit(
                actor=None, action_code="payments.webhook_received", resource_type="payment",
                resource_id=txn.pk, result="SUCCESS",
                details={"provider": provider_name, "donation": str(donation.uid)},
            )
            create_notification(
                recipient=donation.donor, type_=NOTIFICATION_TYPE,
                title="Payment confirmed",
                body="Your donation was successfully processed. Thank you for supporting a warrior.",
                related_resource_type="donation", related_resource_id=str(donation.uid),
                delivery_key=f"pay:confirm:{txn.pk}",
            )
        else:
            record_audit(
                actor=None, action_code="payments.webhook_received", resource_type="payment",
                resource_id=txn.pk, result="FAILURE",
                details={"provider": provider_name, "donation": str(donation.uid), "event": event},
            )
            create_notification(
                recipient=donation.donor, type_=NOTIFICATION_TYPE,
                title="Payment failed",
                body="Your donation could not be processed. You can retry from your donation history.",
                related_resource_type="donation", related_resource_id=str(donation.uid),
                delivery_key=f"pay:fail:{txn.pk}",
            )
    return {"status": "processed", "donation_uid": str(donation.uid)}


def refund_donation(admin, donation, *, reason, amount=None, request=None):
    """SUP/ADM refund workflow (FR-CAM-006, FR-PAY-004).

    Stage 4.17 §29 (TOCTOU): the refundable-remaining computation and the
    already-refunded guard run INSIDE a ``select_for_update`` lock on the
    donation row so two concurrent refunds can never double-issue money.
    """
    if not reason.strip():
        raise ValidationError({"reason": "A reason is required."})

    with transaction.atomic():
        donation = Donation.objects.select_for_update().get(pk=donation.pk)

        processed = donation.refunds.filter(status=RefundStatus.PROCESSED).first()
        if processed is not None:
            raise AlreadyRefunded("This donation has already been refunded.")

        if donation.status != DonationStatus.COMPLETED:
            raise ValidationError(
                {"donation": "Only completed donations can be refunded."}
            )

        refunded_so_far = donation.refunds.filter(
            status__in={RefundStatus.APPROVED, RefundStatus.PROCESSED},
        ).aggregate(total=Sum("amount"))["total"] or Decimal("0.00")

        remaining = donation.amount - refunded_so_far
        refund_amount = Decimal(str(amount)) if amount is not None else remaining
        if refund_amount <= 0 or refund_amount > remaining:
            raise ValidationError(
                {"amount": f"Refund amount must be between 0.01 and {remaining}."}
            )

        confirmed_txn = donation.transactions.filter(status=TransactionStatus.SUCCESS).order_by("-pk").first()

        refund = Refund.objects.create(
            donation=donation, transaction=confirmed_txn, amount=refund_amount,
            reason=reason.strip(), initiated_by=admin, status=RefundStatus.REQUESTED,
        )
        refund.approved_by = admin
        refund.status = RefundStatus.APPROVED
        refund.save(
            update_fields=["approved_by", "status", "updated_at"]
        )
        if refund_amount >= remaining:
            if confirmed_txn is not None:
                confirmed_txn.status = TransactionStatus.REFUNDED
                confirmed_txn.save(update_fields=["status", "updated_at"])
            donation.status = DonationStatus.REFUNDED
            donation.save(update_fields=["status", "updated_at"])
        Campaign.objects.filter(pk=donation.campaign_id).update(
            raised_amount=Greatest(F("raised_amount") - refund_amount, F("raised_amount") * 0),
            updated_at=timezone.now(),
        )
        refund.status = RefundStatus.PROCESSED
        refund.save(update_fields=["status", "updated_at"])

        record_audit(
            actor=admin, action_code="payments.refund", resource_type="donation",
            resource_id=donation.pk, result="SUCCESS",
            details={"amount": str(refund_amount), "reason": refund.reason},
        )
        create_notification(
            recipient=donation.donor, type_=NOTIFICATION_TYPE,
            title="Refund issued",
            body="A refund for a recent donation was issued. Please contact support with any questions.",
            related_resource_type="donation", related_resource_id=str(donation.uid),
            delivery_key=f"pay:refund:{refund.pk}",
        )
    return refund


def campaign_totals(campaign):
    """Transparency aggregation over CONFIRMED funds only.

    Excludes PENDING (unconfirmed), FAILED and CANCELLED rows from totals so
    public figures never overstate committed money.
    """
    from django.db.models import Count

    completed = campaign.donations.filter(status=DonationStatus.COMPLETED)
    agg = completed.aggregate(
        total=Sum("amount", default=Decimal("0.00")),
        count=Count("id"),
    )
    return {"raised_amount": agg["total"], "donation_count": agg["count"]}

# ---------------------------------------------------------------------------
# Admin lifecycle + financial administration (Stage 4.16 §14/§15)
# ---------------------------------------------------------------------------

def admin_pause_campaign(campaign, actor, *, reason=""):
    """Admin pause — ACTIVE → PAUSED (stop receiving new confirmed money)."""
    if campaign.status != CampaignStatus.ACTIVE:
        raise ValidationError({"campaign": "Only ACTIVE campaigns can be paused."})
    campaign.status = CampaignStatus.PAUSED
    campaign.save(update_fields=["status", "updated_at"])
    record_audit(
        actor=actor, action_code="campaign.pause", resource_type="campaign",
        resource_id=campaign.pk, details={"reason": reason or ""},
    )
    return campaign


def admin_close_campaign(campaign, actor, *, reason=""):
    """Admin close — ACTIVE/PAUSED → CLOSED (terminal; removed from public
    stream; financial totals remain frozen as confirmed)."""
    if campaign.status not in {
        CampaignStatus.ACTIVE, CampaignStatus.PAUSED, CampaignStatus.PENDING_VERIFICATION,
    }:
        raise ValidationError(
            {"campaign": f"Campaign in '{campaign.status}' cannot be closed."}
        )
    campaign.status = CampaignStatus.CLOSED
    campaign.save(update_fields=["status", "updated_at"])
    record_audit(
        actor=actor, action_code="campaign.close", resource_type="campaign",
        resource_id=campaign.pk, details={"reason": reason or ""},
    )
    return campaign


def admin_financial_summary():
    """Read-only financial administration aggregates (Stage 4.16 §15).

    Every figure derives from CONFIRMED ledger rows (COMPLETED donations /
    PROCESSED refunds) exactly like the transparency totals used elsewhere —
    no client-supplied numbers, no new aggregation engine. Amounts are Decimal.
    """
    completed = Donation.objects.filter(status=DonationStatus.COMPLETED)
    agg = completed.aggregate(total=Sum("amount", default=Decimal("0.00")))
    refunded = Refund.objects.filter(status=RefundStatus.PROCESSED).aggregate(
        total=Sum("amount", default=Decimal("0.00"))
    )
    last_updated = completed.order_by("-created_at").values_list("created_at", flat=True).first()
    return {
        "confirmed_donations_total": agg["total"],
        "confirmed_donations_count": completed.count(),
        "refunded_total": refunded["total"],
        "pending_donations_count": Donation.objects.filter(status=DonationStatus.PENDING).count(),
        "active_campaigns_count": Campaign.objects.filter(status=CampaignStatus.ACTIVE).count(),
        "closed_campaigns_count": Campaign.objects.filter(status=CampaignStatus.CLOSED).count(),
        "verified_campaigns_count": Campaign.objects.exclude(verified_at__isnull=True).count(),
        "last_updated": last_updated,
    }
