"""Backend tests for the Stage 4.12 donations & payments API.

Run::

    venv/bin/python manage.py test donations --settings=config.settings.ephemeral_test

Covers: public verified-only campaign stream (BR-007), campaign create submission
and verification workflow (FR-CAM-001/002, C11), donor/owner object scoping
(IDOR), donation idempotency (FR-CAM-004), webhook signed confirmation with
replay/forgery/mismatch/allowlist rejections (BR-008, FR-PAY-004/005), refund
authorization and re-aggregation (FR-CAM-006, FR-PAY-004), payment retry
(DON-006), receipts gated to confirmed donor rows (DON-008), redacted provider
refs, audit rows, and rate limits (§29).
"""

import uuid as _uuid
from decimal import Decimal

from django.core.cache import cache
from django.test import TestCase, override_settings
from django.utils import timezone
from rest_framework.test import APIClient
from rest_framework_simplejwt.tokens import RefreshToken

from accounts.models import Role, User, UserRole
from audit.models import AuditLog
from notifications.models import Notification

from .models import Campaign, CampaignStatus, Donation, DonationStatus, PaymentTransaction, Refund
from .providers import build_webhook

_PASSWORD = "Str0ng!Pass9"


def _orm_user(role_code, email=None, account_status="ACTIVE", **extra):
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


def _client(user):
    client = _JsonAPIClient()
    client.credentials(HTTP_AUTHORIZATION=f"Bearer {RefreshToken.for_user(user).access_token}")
    return client


class _JsonAPIClient(APIClient):
    """APIClient that sends request bodies as application/json by default."""

    def _json(self, kwargs):
        kwargs.setdefault("format", "json")

    def post(self, *args, **kwargs):
        self._json(kwargs)
        return super().post(*args, **kwargs)

    def put(self, *args, **kwargs):
        self._json(kwargs)
        return super().put(*args, **kwargs)

    def patch(self, *args, **kwargs):
        self._json(kwargs)
        return super().patch(*args, **kwargs)


def _campaign(owner, status="ACTIVE", goal="500000.00", title="Help Essau's surgery"):
    return Campaign.objects.create(
        owner=owner,
        title=title,
        description="Raise funds for treatment.",
        goal_amount=Decimal(goal),
        raised_amount=Decimal("0.00"),
        status=status,
        verified_at=timezone.now() if status == "ACTIVE" else None,
    )


def _donation(donor, campaign, status="COMPLETED", amount="10000.00",
              idempotency_key=None, transaction_ref=None):
    return Donation.objects.create(
        campaign=campaign, donor=donor, amount=Decimal(amount),
        status=status, idempotency_key=idempotency_key or _uuid.uuid4().hex,
        transaction_ref=transaction_ref or _uuid.uuid4().hex[:32],
    )


def _webhook_post(provider="M_PESA", **payload):
    body, headers = build_webhook(provider, payload)
    return APIClient().post(
        f"/api/webhooks/payments/{provider}/",
        data=body,
        content_type="application/json",
        HTTP_X_PAYMENT_TIMESTAMP=headers["X-Payment-Timestamp"],
        HTTP_X_PAYMENT_SIGNATURE=headers["X-Payment-Signature"],
    )


class DonationApiTests(TestCase):
    @classmethod
    def setUpTestData(cls):
        pass

    def setUp(self):
        cache.clear()
        self.owner = _orm_user("ORGANIZATION")
        self.patient = _orm_user("PATIENT")
        self.caregiver = _orm_user("CAREGIVER")
        self.financial = _orm_user("FINANCIAL_DONOR")
        self.admin = _orm_user("ADMIN")
        self.vo = _orm_user("VERIFICATION_OFFICER")
        self.doctor = _orm_user("DOCTOR")
        self.campaign = _campaign(self.owner, status="ACTIVE")
        self.owner_client = _client(self.owner)
        self.patient_client = _client(self.patient)
        self.caregiver_client = _client(self.caregiver)
        self.financial_client = _client(self.financial)
        self.admin_client = _client(self.admin)
        self.vo_client = _client(self.vo)
        self.doctor_client = _client(self.doctor)

    # --- campaign public surface (BR-007) ------------------------------------
    def test_public_list_shows_only_verified(self):
        _campaign(self.owner, status="DRAFT", title="Hidden draft")
        _campaign(self.owner, status="PENDING_VERIFICATION", title="Pending")
        resp = APIClient().get("/api/campaigns/")
        self.assertEqual(resp.status_code, 200)
        titles = [c["title"] for c in resp.data["results"]]
        self.assertIn(self.campaign.title, titles)
        self.assertNotIn("Hidden draft", titles)
        self.assertNotIn("Pending", titles)

    def test_public_detail_hides_unverified(self):
        draft = _campaign(self.owner, status="DRAFT")
        self.assertEqual(APIClient().get(f"/api/campaigns/{draft.uid}/").status_code, 404)
        self.assertEqual(
            APIClient().get(f"/api/campaigns/{self.campaign.uid}/").status_code, 200
        )

    def test_public_projection_has_no_owner_pii(self):
        resp = APIClient().get(f"/api/campaigns/{self.campaign.uid}/")
        data = resp.data
        self.assertEqual(set(data["owner"].keys()), {"uid", "display_name"})
        self.assertNotIn("email", data)
        self.assertNotIn("rejection_reason", data)

    def test_campaign_create_requires_permission_and_creates_draft(self):
        ok = self.patient_client.post(
            "/api/campaigns/",
            {"title": "Warrior fundraiser", "description": "Support for care.",
             "goal_amount": "250000.00", "currency": "TZS"},
        )
        self.assertEqual(ok.status_code, 201)
        self.assertEqual(ok.data["status"], "DRAFT")
        self.assertTrue(ok.data["is_owner"])

        denied = self.doctor_client.post(
            "/api/campaigns/",
            {"title": "x", "goal_amount": "1.00", "currency": "TZS"},
        )
        self.assertEqual(denied.status_code, 403)

    def test_owner_can_submit_and_pause(self):
        draft = self.patient_client.post(
            "/api/campaigns/",
            {"title": "My campaign", "goal_amount": "100000.00", "currency": "TZS"},
        ).data
        sub = self.patient_client.post(f"/api/campaigns/{draft['uid']}/submit/")
        self.assertEqual(sub.status_code, 200)
        self.assertEqual(sub.data["status"], "PENDING_VERIFICATION")

        pause = self.owner_client.patch(
            f"/api/campaigns/{self.campaign.uid}/", {"pause": True}, format="json",
        )
        self.assertEqual(pause.status_code, 200)
        self.assertEqual(pause.data["status"], "PAUSED")

    def test_non_owner_cannot_edit_or_submit(self):
        other = self.caregiver_client.patch(f"/api/campaigns/{self.campaign.uid}/", {"pause": True})
        self.assertIn(other.status_code, (403, 404))
        sub = self.caregiver_client.post(f"/api/campaigns/{self.campaign.uid}/submit/")
        self.assertIn(sub.status_code, (403, 404))

    def test_active_content_frozen(self):
        self.campaign.status = CampaignStatus.ACTIVE
        self.campaign.save()
        resp = self.owner_client.patch(
            f"/api/campaigns/{self.campaign.uid}/",
            {"title": "new-title"}, format="json",
        )
        self.assertEqual(resp.status_code, 400)

    def test_owner_sees_draft_but_others_404(self):
        draft = self.patient_client.post(
            "/api/campaigns/",
            {"title": "private", "goal_amount": "1.00", "currency": "TZS"},
        ).data
        self.assertEqual(self.caregiver_client.get(f"/api/campaigns/{draft['uid']}/").status_code, 404)
        self.assertEqual(self.patient_client.get(f"/api/campaigns/{draft['uid']}/").status_code, 200)

    # --- admin verification queue -------------------------------------------
    def test_verification_queue_and_verify_flow(self):
        draft = self.patient_client.post(
            "/api/campaigns/",
            {"title": "Approve me", "goal_amount": "100.00", "currency": "TZS"},
        ).data
        self.patient_client.post(f"/api/campaigns/{draft['uid']}/submit/")
        queue = self.vo_client.get("/api/admin/campaigns/verification-queue/")
        self.assertEqual(queue.status_code, 200)
        self.assertIn(draft["uid"], [c["uid"] for c in queue.data["results"]])

        approved = self.vo_client.post(
            f"/api/admin/campaigns/{draft['uid']}/verify/", {"approve": True}, format="json",
        )
        self.assertEqual(approved.status_code, 200)
        self.assertEqual(Campaign.objects.get(uid=draft["uid"]).status, "ACTIVE")
        self.assertIsNotNone(Campaign.objects.get(uid=draft["uid"]).verified_at)

        rejected = self.vo_client.post(
            f"/api/admin/campaigns/{draft['uid']}/verify/", {"approve": False}, format="json",
        )
        self.assertEqual(rejected.status_code, 400)  # already ACTIVE

    def test_verify_requires_campaigns_verify(self):
        draft = self.patient_client.post(
            "/api/campaigns/",
            {"title": "queue me", "goal_amount": "100.00", "currency": "TZS"},
        ).data
        self.patient_client.post(f"/api/campaigns/{draft['uid']}/submit/")
        denied = self.doctor_client.post(
            f"/api/admin/campaigns/{draft['uid']}/verify/", {"approve": True}, format="json",
        )
        self.assertEqual(denied.status_code, 403)
        self.assertEqual(self.admin_client.get("/api/admin/campaigns/").status_code, 200)

    def test_reject_requires_reason(self):
        draft = _campaign(self.owner, status="PENDING_VERIFICATION")
        r = self.vo_client.post(f"/api/admin/campaigns/{draft.uid}/verify/",
                                {"approve": False}, format="json")
        self.assertEqual(r.status_code, 400)
        r = self.vo_client.post(f"/api/admin/campaigns/{draft.uid}/verify/",
                                {"approve": False, "reason": "Missing docs"}, format="json")
        self.assertEqual(r.status_code, 200)
        self.assertEqual(Campaign.objects.get(pk=draft.pk).status, "REJECTED")

    # --- donation creation (FR-CAM-004) -------------------------------------
    def test_donate_only_to_verified_campaign(self):
        draft = _campaign(self.owner, status="PENDING_VERIFICATION")
        r = self.patient_client.post(
            "/api/donations/",
            {"campaign_uid": str(draft.uid), "amount": "1000.00", "currency": "TZS",
             "provider": "M_PESA"},
            HTTP_IDEMPOTENCY_KEY="k-abc",
        )
        self.assertEqual(r.status_code, 400)

    def test_donate_requires_idempotency_key(self):
        r = self.patient_client.post(
            "/api/donations/",
            {"campaign_uid": str(self.campaign.uid), "amount": "1000.00",
             "currency": "TZS", "provider": "M_PESA"},
        )
        self.assertEqual(r.status_code, 400)

    def test_donation_creation_is_idempotent(self):
        self.patient_client.post(
            "/api/donations/",
            {"campaign_uid": str(self.campaign.uid), "amount": "1000.00",
             "currency": "TZS", "provider": "M_PESA"},
            HTTP_IDEMPOTENCY_KEY="k-123",
        )
        again = self.patient_client.post(
            "/api/donations/",
            {"campaign_uid": str(self.campaign.uid), "amount": "9999.99",
             "currency": "TZS", "provider": "M_PESA"},
            HTTP_IDEMPOTENCY_KEY="k-123",
        )
        self.assertEqual(again.status_code, 200)
        self.assertEqual(Donation.objects.filter(idempotency_key="k-123").count(), 1)

    def test_idempotency_key_is_user_scoped(self):
        self.patient_client.post(
            "/api/donations/",
            {"campaign_uid": str(self.campaign.uid), "amount": "1000.00",
             "currency": "TZS", "provider": "M_PESA"},
            HTTP_IDEMPOTENCY_KEY="k-scoped",
        )
        r = self.caregiver_client.post(
            "/api/donations/",
            {"campaign_uid": str(self.campaign.uid), "amount": "1000.00",
             "currency": "TZS", "provider": "M_PESA"},
            HTTP_IDEMPOTENCY_KEY="k-scoped",
        )
        # Stage 4.20: cross-principal reuse of one key is the documented
        # 409 CONFLICT (never 400), and must not leak the donor's identity.
        self.assertEqual(r.status_code, 409)
        self.assertEqual(Donation.objects.filter(idempotency_key="k-scoped").count(), 1)

    def test_donation_history_scoping_and_idor(self):
        donation = _donation(self.patient, self.campaign, status="PENDING")
        mine = self.patient_client.get("/api/donations/")
        self.assertIn(str(donation.uid), [d["uid"] for d in mine.data["results"]])

        detail = self.patient_client.get(f"/api/donations/{donation.uid}/")
        self.assertEqual(detail.status_code, 200)
        # IDOR: a caregiver who is not the donor cannot read another's donation.
        other = self.caregiver_client.get(f"/api/donations/{donation.uid}/")
        self.assertIn(other.status_code, (403, 404))

    def test_financial_donor_oversight_views_all_donations(self):
        donation = _donation(self.patient, self.campaign, status="PENDING")
        resp = self.financial_client.get("/api/donations/")
        self.assertIn(str(donation.uid), [d["uid"] for d in resp.data["results"]])

    def test_suspended_user_cannot_donate(self):
        blocked = _orm_user("PATIENT", account_status="SUSPENDED")
        r = _client(blocked).post(
            "/api/donations/",
            {"campaign_uid": str(self.campaign.uid), "amount": "100.00",
             "currency": "TZS", "provider": "M_PESA"},
            HTTP_IDEMPOTENCY_KEY="k-susp",
        )
        self.assertEqual(r.status_code, 403)

    # --- receipt (DON-008) ---------------------------------------------------
    def test_receipt_only_when_confirmed_and_for_donor(self):
        don = _donation(self.patient, self.campaign, status="COMPLETED")
        receipt = self.patient_client.get(f"/api/donations/{don.uid}/receipt/")
        self.assertEqual(receipt.status_code, 200)
        self.assertTrue(receipt.data["receipt_number"].startswith("WARRIOR-RCP-"))
        self.assertEqual(receipt.data["status"], "COMPLETED")

        # A pending donation has no receipt.
        pending = _donation(self.patient, self.campaign, status="PENDING")
        self.assertEqual(
            self.patient_client.get(f"/api/donations/{pending.uid}/receipt/").status_code, 400,
        )
        # Non-donor cannot fetch another's receipt.
        self.assertIn(
            self.caregiver_client.get(f"/api/donations/{don.uid}/receipt/").status_code,
            (403, 404),
        )

    # --- payment status surface (FR-PAY-003) --------------------------------
    def test_payment_list_scope_and_retry(self):
        don = _donation(self.patient, self.campaign, status="PENDING")
        PaymentTransaction.objects.create(
            donation=don, provider="M_PESA", provider_ref=f"SANDBOX-{_uuid.uuid4().hex[:16].upper()}",
            status="PENDING", amount=don.amount, attempt=1,
        )
        txn = PaymentTransaction.objects.get(donation=don)

        mine = self.patient_client.get("/api/payments/")
        self.assertIn(txn.id, [p["id"] for p in mine.data["results"]])
        other = self.caregiver_client.get(f"/api/payments/{txn.id}/")
        self.assertIn(other.status_code, (403, 404))

        retry = self.patient_client.post(f"/api/payments/{txn.id}/retry/")
        self.assertEqual(retry.status_code, 200)
        self.assertEqual(retry.data["attempt"], 2)
        self.assertEqual(retry.data["status"], "PENDING")

    def test_retry_rejected_for_terminal_donation(self):
        don = _donation(self.patient, self.campaign, status="COMPLETED")
        txn = PaymentTransaction.objects.create(
            donation=don, provider="M_PESA", provider_ref="X-1",
            status="SUCCESS", amount=don.amount, attempt=1,
        )
        self.assertEqual(
            self.patient_client.post(f"/api/payments/{txn.id}/retry/").status_code, 400,
        )


class PaymentWebhookTests(TestCase):
    def setUp(self):
        cache.clear()
        self.owner = _orm_user("ORGANIZATION")
        self.patient = _orm_user("PATIENT")
        self.client_user = _client(self.patient)
        self.campaign = _campaign(self.owner, status="ACTIVE", goal="500000.00")

    def _initiate(self, key="k-web", amount="10000.00"):
        r = self.client_user.post(
            "/api/donations/",
            {"campaign_uid": str(self.campaign.uid), "amount": amount,
             "currency": "TZS", "provider": "M_PESA"},
            HTTP_IDEMPOTENCY_KEY=key,
        )
        self.assertEqual(r.status_code, 201)
        donation = Donation.objects.get(uid=r.data["uid"])
        txn = donation.transactions.order_by("-pk").first()
        return donation, txn

    def _sign_for(self, txn, event="payment.success", amount=None, currency="TZS",
                  provider_ref=None, provider="M_PESA"):
        return _webhook_post(
            provider=provider,
            event=event,
            transaction_ref=txn.donation.transaction_ref,
            provider_ref=provider_ref or txn.provider_ref,
            amount=amount if amount is not None else str(txn.amount),
            currency=currency,
        )

    def test_success_webhook_confirms_donation(self):
        donation, txn = self._initiate()
        resp = self._sign_for(txn)
        self.assertEqual(resp.status_code, 200)
        donation.refresh_from_db()
        txn.refresh_from_db()
        self.assertEqual(donation.status, "COMPLETED")
        self.assertEqual(txn.status, "SUCCESS")
        self.campaign.refresh_from_db()
        self.assertEqual(self.campaign.raised_amount, Decimal("10000.00"))
        self.assertTrue(
            Notification.objects.filter(
                recipient=self.patient, type="PAYMENT",
                delivery_key=f"pay:confirm:{txn.pk}",
            ).exists()
        )

    def test_duplicate_webhook_is_idempotent(self):
        donation, txn = self._initiate()
        self._sign_for(txn)
        again = self._sign_for(txn)
        self.assertEqual(again.status_code, 200)
        donation.refresh_from_db()
        self.campaign.refresh_from_db()
        self.assertEqual(self.campaign.raised_amount, Decimal("10000.00"))

    def test_forged_signature_rejected(self):
        donation, txn = self._initiate()
        body, headers = build_webhook("M_PESA", {
            "event": "payment.success",
            "transaction_ref": donation.transaction_ref,
            "provider_ref": txn.provider_ref,
            "amount": "10000.00", "currency": "TZS",
        })
        forged = APIClient().post(
            "/api/webhooks/payments/M_PESA/", data=body, content_type="application/json",
            HTTP_X_PAYMENT_TIMESTAMP=headers["X-Payment-Timestamp"],
            HTTP_X_PAYMENT_SIGNATURE="0" * 64,
        )
        self.assertEqual(forged.status_code, 401)
        donation.refresh_from_db()
        self.assertEqual(donation.status, "PENDING")

    def test_stale_webhook_rejected(self):
        import time as _time

        donation, txn = self._initiate()
        ts = int(_time.time()) - 3600
        resp = _webhook_post(
            timestamp=ts,
            event="payment.success", transaction_ref=donation.transaction_ref,
            provider_ref=txn.provider_ref, amount="10000.00", currency="TZS",
        )
        self.assertEqual(resp.status_code, 401)
        donation.refresh_from_db()
        self.assertEqual(donation.status, "PENDING")

    def test_amount_mismatch_rejected(self):
        donation, txn = self._initiate()
        resp = self._sign_for(txn, amount="1.00")
        self.assertEqual(resp.status_code, 400)
        donation.refresh_from_db()
        self.assertEqual(donation.status, "PENDING")
        self.campaign.refresh_from_db()
        self.assertEqual(self.campaign.raised_amount, Decimal("0.00"))

    def test_unknown_transaction_ref_rejected(self):
        _donation(self.patient, self.campaign, status="PENDING")
        resp = _webhook_post(
            event="payment.success", transaction_ref="deadbeefdeadbeefdeadbeefdeadbeef",
            provider_ref="SANDBOX-UNKNOWN", amount="100.00", currency="TZS",
        )
        self.assertEqual(resp.status_code, 400)

    def test_failed_event_marks_donation_failed(self):
        donation, txn = self._initiate()
        resp = self._sign_for(txn, event="payment.failed")
        self.assertEqual(resp.status_code, 200)
        donation.refresh_from_db()
        txn.refresh_from_db()
        self.assertEqual(donation.status, "FAILED")
        self.assertEqual(txn.status, "FAILED")
        self.campaign.refresh_from_db()
        self.assertEqual(self.campaign.raised_amount, Decimal("0.00"))

    def test_ip_allowlist_blocks_other_origin(self):
        donation, txn = self._initiate()
        with override_settings(PAYMENT_ALLOWED_IPS=["10.0.0.1"]):
            resp = self._sign_for(txn)
        self.assertEqual(resp.status_code, 401)
        donation.refresh_from_db()
        self.assertEqual(donation.status, "PENDING")

    def test_webhook_requires_no_jwt(self):
        donation, txn = self._initiate()
        resp = self._sign_for(txn)
        self.assertEqual(resp.status_code, 200)


class RefundApiTests(TestCase):
    def setUp(self):
        cache.clear()
        self.owner = _orm_user("ORGANIZATION")
        self.patient = _orm_user("PATIENT")
        self.admin = _orm_user("ADMIN")
        self.doctor = _orm_user("DOCTOR")
        self.campaign = _campaign(self.owner, status="ACTIVE")
        self.admin_client = _client(self.admin)
        self.doctor_client = _client(self.doctor)
        self.patient_client = _client(self.patient)

    def _complete(self, amount="10000.00"):
        donation = _donation(self.patient, self.campaign, status="COMPLETED",
                             amount=amount, idempotency_key=_uuid.uuid4().hex)
        PaymentTransaction.objects.create(
            donation=donation, provider="M_PESA", provider_ref=f"PAY-{_uuid.uuid4().hex[:10]}",
            status="SUCCESS", amount=donation.amount, attempt=1,
        )
        self.campaign.raised_amount = Decimal(amount)
        self.campaign.save()
        return donation

    def test_refund_requires_donations_refund(self):
        donation = self._complete()
        denied = self.doctor_client.post(
            f"/api/admin/donations/{donation.uid}/refund/", {"reason": "mistake"}, format="json")
        self.assertEqual(denied.status_code, 403)
        ok = self.admin_client.post(
            f"/api/admin/donations/{donation.uid}/refund/", {"reason": "mistake"}, format="json")
        self.assertEqual(ok.status_code, 201)

    def test_full_refund_adjusts_campaign_counter(self):
        donation = self._complete()
        r = self.admin_client.post(
            f"/api/admin/donations/{donation.uid}/refund/", {"reason": "duplicate"}, format="json")
        self.assertEqual(r.status_code, 201)
        donation.refresh_from_db()
        self.assertEqual(donation.status, "REFUNDED")
        self.assertEqual(donation.refunds.get().status, "PROCESSED")
        self.campaign.refresh_from_db()
        self.assertEqual(self.campaign.raised_amount, Decimal("0.00"))

    def test_only_completed_donations_refundable(self):
        pending = _donation(self.patient, self.campaign, status="PENDING")
        r = self.admin_client.post(
            f"/api/admin/donations/{pending.uid}/refund/", {"reason": "x"}, format="json")
        self.assertEqual(r.status_code, 400)

    def test_double_refund_rejected(self):
        donation = self._complete()
        self.admin_client.post(
            f"/api/admin/donations/{donation.uid}/refund/", {"reason": "one"}, format="json")
        again = self.admin_client.post(
            f"/api/admin/donations/{donation.uid}/refund/", {"reason": "two"}, format="json")
        self.assertEqual(again.status_code, 409)

    def test_partial_refund_supported(self):
        donation = self._complete(amount="10000.00")
        r = self.admin_client.post(
            f"/api/admin/donations/{donation.uid}/refund/",
            {"reason": "partial", "amount": "3000.00"}, format="json")
        self.assertEqual(r.status_code, 201)
        donation.refresh_from_db()
        self.assertEqual(donation.status, "COMPLETED")
        self.campaign.refresh_from_db()
        self.assertEqual(self.campaign.raised_amount, Decimal("7000.00"))


class AuditAndTransparencyTests(TestCase):
    def setUp(self):
        cache.clear()
        self.owner = _orm_user("ORGANIZATION")
        self.patient = _orm_user("PATIENT")
        self.admin = _orm_user("ADMIN")
        self.campaign = _campaign(self.owner, status="ACTIVE")
        self.patient_client = _client(self.patient)
        self.admin_client = _client(self.admin)

    def test_audit_rows_written_for_core_events(self):
        begin = AuditLog.objects.count()
        self.patient_client.post(
            "/api/donations/",
            {"campaign_uid": str(self.campaign.uid), "amount": "100.00",
             "currency": "TZS", "provider": "M_PESA"},
            HTTP_IDEMPOTENCY_KEY="k-audit",
        )
        self.assertGreater(AuditLog.objects.filter(action_code="payments.initiate").count(), 0)

    def test_redacted_provider_ref_for_non_owners(self):
        donation = _donation(self.patient, self.campaign, status="PENDING")
        PaymentTransaction.objects.create(
            donation=donation, provider="M_PESA",
            provider_ref=f"SANDBOX-{_uuid.uuid4().hex[:16].upper()}",
            status="PENDING", amount=donation.amount, attempt=1,
        )
        txn = PaymentTransaction.objects.get(donation=donation)
        own = self.patient_client.get(f"/api/payments/{txn.id}/")
        self.assertFalse(own.data["provider_ref"].startswith("SANDBOX-"))
        # admin (payments.view) sees the full reconciliation reference
        admin_view = self.admin_client.get(f"/api/payments/{txn.id}/")
        self.assertTrue(admin_view.data["provider_ref"].startswith("SANDBOX-"))

    def test_totals_exclude_unconfirmed(self):
        _donation(self.patient, self.campaign, status="PENDING", amount="90000.00")
        confirmed = _donation(self.patient, self.campaign, status="COMPLETED", amount="5000.00")
        from .services import campaign_totals

        totals = campaign_totals(self.campaign)
        self.assertEqual(totals["raised_amount"], Decimal("5000.00"))
        self.assertEqual(totals["donation_count"], 1)


class DonationThrottleTests(TestCase):
    def setUp(self):
        cache.clear()
        self.owner = _orm_user("ORGANIZATION")
        self.patient = _orm_user("PATIENT")
        self.campaign_a = _campaign(self.owner, status="ACTIVE")
        self.campaign_b = _campaign(self.owner, status="ACTIVE", title="Another")
        self.client_user = _client(self.patient)

    def _donate(self, campaign, key):
        return self.client_user.post(
            "/api/donations/",
            {"campaign_uid": str(campaign.uid), "amount": "100.00",
             "currency": "TZS", "provider": "M_PESA"},
            HTTP_IDEMPOTENCY_KEY=key,
        )

    def test_donation_initiate_throttle_10_per_hour(self):
        campaigns = [self.campaign_a] + [
            _campaign(self.owner, status="ACTIVE", title=f"Hourly-{i}")
            for i in range(1, 10)
        ]
        for i, campaign in enumerate(campaigns):
            self.assertEqual(self._donate(campaign, f"t-{i}").status_code, 201)
        eleventh = self._donate(self.campaign_b, "t-10")
        self.assertEqual(eleventh.status_code, 429)

    def test_campaign_burst_throttle(self):
        self._donate(self.campaign_a, "b-0")
        self._donate(self.campaign_a, "b-1")
        third = self._donate(self.campaign_a, "b-2")
        self.assertEqual(third.status_code, 429)
        # a different campaign is not blocked by the same key.
        self.assertEqual(self._donate(self.campaign_b, "b-3").status_code, 201)