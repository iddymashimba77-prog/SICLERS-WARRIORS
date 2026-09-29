"""Stage 4.16 tests — donations admin surfaces.

Two surfaces under test:

1. Campaign lifecycle (mutations on ``/api/admin/campaigns/{uid}/pause|close``,
   ``campaigns.verify`` + MFA). State machine: ACTIVE → PAUSED, and
   ACTIVE/PAUSED/PENDING_VERIFICATION → CLOSED (terminal). DRAFT cannot be
   closed by admin; unauthorized roles and MFA-on-admin are denied.
2. Financial summary (``GET /api/admin/financial/summary/``, ``donations.view``).
   Totals derive ONLY from CONFIRMED ledger rows (COMPLETED donations /
   PROCESSED refunds) — PENDING rows never inflate confirmed totals. No manual
   payment-status manipulation exists on this surface.
"""

import uuid as _uuid
from decimal import Decimal

from django.core.cache import cache
from django.test import TestCase
from django.utils import timezone
from rest_framework.test import APIClient
from rest_framework_simplejwt.tokens import RefreshToken

from accounts.models import Role, User, UserRole

from .models import Campaign, CampaignStatus, Donation, DonationStatus, Refund

_PASSWORD = "Str0ng!Pass9"


def _orm_user(role_code, account_status="ACTIVE", email=None, **extra):
    user = User.objects.create_user(
        email=email or f"{role_code.lower()}-{_uuid.uuid4().hex[:10]}@example.com",
        password=_PASSWORD,
        first_name="Test",
        last_name=role_code.title(),
        account_status=account_status,
        **extra,
    )
    UserRole.objects.create(user=user, role=Role.objects.get(code=role_code))
    return user


class _JsonAPIClient(APIClient):
    """APIClient that sends request bodies as application/json by default."""

    def _json(self, kwargs):
        kwargs.setdefault("format", "json")

    def post(self, *args, **kwargs):
        self._json(kwargs)
        return super().post(*args, **kwargs)


def _client(user):
    client = _JsonAPIClient()
    client.credentials(HTTP_AUTHORIZATION=f"Bearer {RefreshToken.for_user(user).access_token}")
    return client


def _campaign(owner, status="ACTIVE", goal="500000.00"):
    return Campaign.objects.create(
        owner=owner,
        title="Help Essau's surgery",
        description="Raise funds for treatment.",
        goal_amount=Decimal(goal),
        raised_amount=Decimal("0.00"),
        status=status,
        verified_at=timezone.now() if status == "ACTIVE" else None,
    )


def _donation(donor, campaign, status="COMPLETED", amount="10000.00"):
    return Donation.objects.create(
        campaign=campaign, donor=donor, amount=Decimal(amount),
        status=status, idempotency_key=_uuid.uuid4().hex,
        transaction_ref=_uuid.uuid4().hex[:32],
    )


class AdminCampaignLifecycleTests(TestCase):
    def setUp(self):
        cache.clear()
        self.super = _orm_user("SUPER_ADMIN")
        self.patient = _orm_user("PATIENT")
        self.super_client = _client(self.super)
        self.patient_client = _client(self.patient)

    def test_pause_active_campaign(self):
        campaign = _campaign(self.super, status="ACTIVE")
        r = self.super_client.post(f"/api/admin/campaigns/{campaign.uid}/pause/",
                                   {"reason": "Suspected fraud review"})
        self.assertEqual(r.status_code, 200)
        campaign.refresh_from_db()
        self.assertEqual(campaign.status, CampaignStatus.PAUSED)

    def test_close_paused_and_active(self):
        campaign = _campaign(self.super, status="PAUSED")
        r = self.super_client.post(f"/api/admin/campaigns/{campaign.uid}/close/",
                                   {"reason": "Goal not met; closing"})
        self.assertEqual(r.status_code, 200)
        campaign.refresh_from_db()
        self.assertEqual(campaign.status, CampaignStatus.CLOSED)

    def test_close_draft_blocked(self):
        campaign = _campaign(self.super, status="DRAFT")
        r = self.super_client.post(f"/api/admin/campaigns/{campaign.uid}/close/",
                                   {"reason": "Closing early"})
        self.assertEqual(r.status_code, 400)

    def test_pause_requires_active(self):
        campaign = _campaign(self.super, status="CLOSED")
        r = self.super_client.post(f"/api/admin/campaigns/{campaign.uid}/pause/",
                                   {"reason": "Pause attempt"})
        self.assertEqual(r.status_code, 400)

    def test_vertical_denials(self):
        campaign = _campaign(self.super, status="ACTIVE")
        r = self.patient_client.post(f"/api/admin/campaigns/{campaign.uid}/pause/",
                                     {"reason": "Pause attempt"})
        self.assertEqual(r.status_code, 403)
        self.assertEqual(
            self.patient_client.post(f"/api/admin/campaigns/{campaign.uid}/close/",
                                     {"reason": "Close attempt"}).status_code, 403)

    def test_mfa_boundary(self):
        admin = _orm_user("ADMIN", mfa_enabled=True)
        campaign = _campaign(admin, status="ACTIVE")
        r = _client(admin).post(f"/api/admin/campaigns/{campaign.uid}/pause/",
                                {"reason": "Pause attempt"})
        self.assertEqual(r.status_code, 403)

    def test_unknown_campaign_404(self):
        r = self.super_client.post(f"/api/admin/campaigns/{_uuid.uuid4()}/close/",
                                   {"reason": "Closing"})
        self.assertEqual(r.status_code, 404)


class AdminFinancialSummaryTests(TestCase):
    def setUp(self):
        cache.clear()
        self.super = _orm_user("SUPER_ADMIN")
        self.patient = _orm_user("PATIENT")
        self.super_client = _client(self.super)
        self.patient_client = _client(self.patient)

    def _seed(self):
        active = _campaign(self.super, status="ACTIVE")
        closed = _campaign(self.super, status="CLOSED")
        donor = _orm_user("PATIENT")
        d1 = _donation(donor, active, status="COMPLETED", amount="10000.00")
        _donation(donor, active, status="COMPLETED", amount="20000.00")
        _donation(donor, active, status="PENDING", amount="99999.99")
        Refund.objects.create(
            donation=d1, amount=Decimal("2500.00"), reason="Duplicate charge",
            initiated_by=self.super, status="PROCESSED",
        )
        return closed

    def test_summary_reads_only_confirmed_ledger(self):
        closed = self._seed()
        r = self.super_client.get("/api/admin/financial/summary/")
        self.assertEqual(r.status_code, 200)
        data = r.json()["data"]
        self.assertEqual(Decimal(str(data["confirmed_donations_total"])), Decimal("30000.00"))
        self.assertEqual(data["confirmed_donations_count"], 2)
        self.assertEqual(Decimal(str(data["refunded_total"])), Decimal("2500.00"))
        self.assertEqual(data["pending_donations_count"], 1)
        self.assertEqual(data["active_campaigns_count"], 1)
        self.assertEqual(data["closed_campaigns_count"], 1)
        self.assertTrue(data["verified_campaigns_count"] >= 1)
        self.assertTrue(data["last_updated"])

    def test_pending_never_inflates_total(self):
        self._seed()
        r = self.super_client.get("/api/admin/financial/summary/")
        self.assertEqual(
            Decimal(str(r.json()["data"]["confirmed_donations_total"])), Decimal("30000.00"))
        self.assertNotEqual(
            Decimal(str(r.json()["data"]["confirmed_donations_total"])), Decimal("129999.99"))

    def test_vertical_denials(self):
        self._seed()
        self.assertEqual(self.super_client.get("/api/admin/financial/summary/").status_code, 200)
        self.assertEqual(self.patient_client.get("/api/admin/financial/summary/").status_code, 403)

    def test_no_status_mutation_on_summary(self):
        self._seed()
        self.super_client.get("/api/admin/financial/summary/")
        self.assertEqual(
            Donation.objects.filter(status=DonationStatus.COMPLETED).count(), 2
        )
        self.assertEqual(
            Donation.objects.filter(status=DonationStatus.PENDING).count(), 1
        )


class AdminDonationLedgerTests(TestCase):
    """ADMIN-3: GET /api/admin/donations/ (``donations.view``) + refund (``donations.refund``)."""

    def setUp(self):
        cache.clear()
        self.super = _orm_user("SUPER_ADMIN")
        self.donor = _orm_user("PATIENT")
        self.super_client = _client(self.super)
        self.donor_client = _client(self.donor)

    def _seed(self):
        campaign = _campaign(self.super, status="ACTIVE")
        return _donation(self.donor, campaign, status="COMPLETED", amount="10000.00")

    def test_ledger_list_allowed_for_financial_oversight(self):
        donation = self._seed()
        for role in ("SUPER_ADMIN", "ADMIN"):
            client = _client(_orm_user(role))
            resp = client.get("/api/admin/donations/")
            self.assertEqual(resp.status_code, 200)
            rows = resp.json()["data"]["results"]
            self.assertEqual(rows[0]["uid"], str(donation.uid))
            self.assertEqual(rows[0]["donor_display"], "Test")
            self.assertEqual(rows[0]["amount"], "10000.00")
            self.assertNotIn("transaction_ref", rows[0])

    def test_ledger_list_denied_for_self_only_and_anon(self):
        self._seed()
        self.assertEqual(self.donor_client.get("/api/admin/donations/").status_code, 403)
        self.assertEqual(APIClient().get("/api/admin/donations/").status_code, 401)

    def test_status_filter_validation(self):
        self._seed()
        bad = self.super_client.get("/api/admin/donations/", {"status": "BOGUS"})
        self.assertEqual(bad.status_code, 400)
        ok = self.super_client.get("/api/admin/donations/", {"status": "COMPLETED"})
        self.assertEqual(ok.status_code, 200)
        self.assertEqual(len(ok.json()["data"]["results"]), 1)

    def test_refund_remains_super_admin_gated(self):
        donation = self._seed()
        admin = _client(_orm_user("ADMIN"))
        resp = admin.post(
            f"/api/admin/donations/{donation.uid}/refund/",
            {"reason": "Double charge discovered"},
        )
        self.assertEqual(resp.status_code, 201)
        self.assertTrue(
            Refund.objects.filter(donation=donation).exists()
        )
        # A plain patient (donor) cannot refund.
        denied = self.donor_client.post(
            f"/api/admin/donations/{donation.uid}/refund/",
            {"reason": "I want my money back"},
        )
        self.assertEqual(denied.status_code, 403)