"""Phase 7 — finance: campaigns, donations, transactions, refunds (TZS)."""

from __future__ import annotations

import datetime as _dt
from decimal import Decimal

from django.utils import timezone

from donations.models import (
    Campaign, CampaignStatus, Donation, DonationStatus, PaymentProvider,
    PaymentTransaction, Refund, RefundStatus, TransactionStatus,
)

from .base import TAG, uuid_for

PROVIDERS = [p.value for p in PaymentProvider]
PROVIDER_NAMES = ["M-Pesa", "Tigo Pesa", "Airtel Money", "Halopesa", "CRDB"]


def seed(ctx) -> None:
    ctx.log("## Finance")
    rng = ctx.rng
    today = timezone.now().date()
    owners = ctx.users_of("ORGANIZATION") + ctx.users_of("SOCIAL_SUPPORT")
    donors = ctx.users_of("FINANCIAL_DONOR") + ctx.users_of("PATIENT")
    if not owners or not donors:
        ctx.log("- skipped (need organizations + donors)")
        return

    active_campaigns = []
    pending_campaigns = []
    for i, owner in enumerate(owners, start=1):
        for k in range(1, 3):
            if i <= 3 and k == 1:
                status = "PENDING_VERIFICATION"
            else:
                status = ["ACTIVE", "ACTIVE", "CLOSED", "DRAFT", "PAUSED", "REJECTED"][(i + k) % 6]
            goal = Decimal(500000 * (1 + (i + k) % 5))
            campaign, _ = Campaign.objects.update_or_create(
                uid=uuid_for("campaign", i, k),
                defaults={
                    "owner": owner,
                    "organization": ctx.organizations[(i + k) % len(ctx.organizations)] if ctx.organizations else None,
                    "title": f"{TAG} {['Emergency support', 'Clinic supplies', 'Awareness drive'][k % 3]} #{i}-{k}",
                    "description": f"{TAG} synthetic campaign for QA of the donations module.",
                    "goal_amount": goal,
                    "currency": "TZS",
                    "status": status,
                    "verified_by": ctx.admin if status in ("ACTIVE", "CLOSED") else None,
                    "verified_at": timezone.now() - _dt.timedelta(days=10) if status in ("ACTIVE", "CLOSED") else None,
                    "rejection_reason": f"{TAG} incomplete documentation." if status == "REJECTED" else "",
                    "start_date": today - _dt.timedelta(days=20),
                    "end_date": today + _dt.timedelta(days=40),
                },
            )
            ctx.track("campaigns")
            if status == "ACTIVE":
                active_campaigns.append(campaign)
            elif status == "PENDING_VERIFICATION":
                pending_campaigns.append(campaign)

    dindex = 0
    for campaign in active_campaigns:
        for donor in donors[: max(3, len(donors) // 3)]:
            dindex += 1
            status = ["COMPLETED", "COMPLETED", "PENDING", "FAILED", "REFUNDED"][dindex % 5]
            amount = Decimal(10000 * (1 + (dindex % 8)))
            donation, _ = Donation.objects.update_or_create(
                idempotency_key=f"{TAG}-DON-{dindex}",
                defaults={
                    "campaign": campaign,
                    "donor": donor,
                    "amount": amount,
                    "currency": "TZS",
                    "status": status,
                    "transaction_ref": f"{TAG}{dindex:08d}",
                },
            )
            ctx.track("donations")
            txn_status = {
                "COMPLETED": TransactionStatus.SUCCESS,
                "PENDING": TransactionStatus.PENDING,
                "FAILED": TransactionStatus.FAILED,
                "REFUNDED": TransactionStatus.REFUNDED,
            }[status]
            PaymentTransaction.objects.get_or_create(
                provider_ref=f"{TAG}-TXN-{dindex}",
                defaults={
                    "donation": donation,
                    "provider": PROVIDERS[dindex % len(PROVIDERS)],
                    "status": txn_status,
                    "amount": amount,
                    "currency": "TZS",
                    "payload": {"method": "mobile_money", "masked": "2557****" + str(dindex).zfill(3)},
                    "attempt": 1,
                },
            )
            ctx.track("payment_transactions")
            if status == "REFUNDED" and dindex % 3 == 0:
                Refund.objects.get_or_create(
                    donation=donation,
                    defaults={
                        "transaction": donation.transactions.first(),
                        "amount": amount,
                        "reason": f"{TAG} donor requested refund.",
                        "initiated_by": donor,
                        "approved_by": ctx.admin,
                        "status": RefundStatus.REQUESTED,
                    },
                )
                ctx.track("refunds")

    for i, campaign in enumerate(active_campaigns + pending_campaigns, start=1):
        if campaign.status == CampaignStatus.ACTIVE:
            raised = sum(
                (d.amount for d in campaign.donations.filter(status=DonationStatus.COMPLETED)),
                Decimal("0.00"),
            )
            refunded = sum(
                (r.amount for r in Refund.objects.filter(
                    donation__campaign=campaign,
                    status__in=[RefundStatus.APPROVED, RefundStatus.PROCESSED],
                )),
                Decimal("0.00"),
            )
            campaign.raised_amount = max(Decimal("0.00"), raised - refunded)
            campaign.save(update_fields=["raised_amount"])

    ctx.log(
        f"- campaigns={ctx.counts.get('campaigns', 0)} "
        f"donations={ctx.counts.get('donations', 0)} "
        f"transactions={ctx.counts.get('payment_transactions', 0)} "
        f"refunds={ctx.counts.get('refunds', 0)}"
    )
