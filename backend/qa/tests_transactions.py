"""Transaction-integrity checks at the edges of the emergency and payment
flows (Stage 4.19 / §10-11).

Pain-points chosen so they are NOT duplicates of the per-app suites:
* SOS → cancel → replay-same-key: a cancelled request must not be
  "resurrected" into a fresh critical row via its original idempotency key.
* Double cancel → single terminal state, second attempt is a 4xx.
* Foreign cancel is refused (owner-or-operator enforcement in the view).
* Donation-made-paid path: initiate (PENDING) → success webhook → the
  campaign counter and donor receipt agree, then a full refund flips the
  donation to REFUNDED and withdraws the receipt.
"""

from decimal import Decimal

from django.core.cache import cache
from django.test import TestCase

from donations.models import Campaign, Donation, Refund
from emergencies.models import EmergencyRequest

from . import qa_helpers as h
from .tests_emergency_surface import _sos


class EmergencyReverseFlowTests(TestCase):
    def setUp(self):
        cache.clear()
        self.patient = h.orm_user("PATIENT")
        self.other = h.orm_user("PATIENT")
        self.c = h.client(self.patient)

    def test_cancel_then_replay_same_key_is_still_blocked(self):
        _sos(self.c, key="sos-replay-1")
        sos = EmergencyRequest.objects.get(requester=self.patient,
                                           idempotency_key="sos-replay-1")
        cancelled = self.c.post(f"/api/emergency/requests/{sos.uid}/cancel/")
        self.assertEqual(cancelled.status_code, 200)
        sos.refresh_from_db()
        self.assertEqual(sos.status, "CANCELLED")
        # Replaying the key must NOT create a second active request.
        replay = _sos(self.c, key="sos-replay-1")
        self.assertEqual(replay.status_code, 409)
        self.assertEqual(EmergencyRequest.objects.filter(requester=self.patient).count(), 1)

    def test_double_cancel_rejected(self):
        _sos(self.c, key="sos-replay-2")
        sos = EmergencyRequest.objects.get(requester=self.patient,
                                           idempotency_key="sos-replay-2")
        self.assertEqual(self.c.post(f"/api/emergency/requests/{sos.uid}/cancel/").status_code, 200)
        again = self.c.post(f"/api/emergency/requests/{sos.uid}/cancel/")
        self.assertIn(again.status_code, (400, 409))

    def test_foreign_patient_cannot_cancel(self):
        _sos(self.c, key="sos-replay-3")
        sos = EmergencyRequest.objects.get(requester=self.patient,
                                           idempotency_key="sos-replay-3")
        self.assertIn(h.client(self.other).post(
            f"/api/emergency/requests/{sos.uid}/cancel/").status_code, (403, 404))


class PaidFromDonationToReceiptToRefundTests(TestCase):
    def setUp(self):
        cache.clear()
        self.owner = h.orm_user("ORGANIZATION")
        self.patient = h.orm_user("PATIENT")
        self.admin = h.orm_user("ADMIN")
        self.campaign = Campaign.objects.create(
            owner=self.owner, title="Back to school", goal_amount=Decimal("500000.00"),
            status="ACTIVE",
        )
        self.patient_client = h.client(self.patient)
        self.admin_client = h.client(self.admin)

    def _complete(self, key="qa-pay-1"):
        init = self.patient_client.post(
            "/api/donations/",
            {"campaign_uid": str(self.campaign.uid), "amount": "10000.00",
             "currency": "TZS", "provider": "M_PESA"},
            HTTP_IDEMPOTENCY_KEY=key,
        )
        self.assertEqual(init.status_code, 201)
        donation = Donation.objects.get(uid=init.data["uid"])
        txn = donation.transactions.order_by("-pk").first()
        from donations.providers import build_webhook
        body, headers = build_webhook(
            "M_PESA",
            {"event": "payment.success", "transaction_ref": donation.transaction_ref,
             "provider_ref": txn.provider_ref, "amount": str(txn.amount), "currency": "TZS"},
        )
        paid = h.APIClient().post(
            "/api/webhooks/payments/M_PESA/",
            data=body,
            content_type="application/json",
            HTTP_X_PAYMENT_TIMESTAMP=headers["X-Payment-Timestamp"],
            HTTP_X_PAYMENT_SIGNATURE=headers["X-Payment-Signature"],
        )
        self.assertEqual(paid.status_code, 200)
        donation.refresh_from_db()
        return donation

    def test_campaign_receipt_and_counter_agree_after_payment(self):
        donation = self._complete()
        self.campaign.refresh_from_db()
        self.assertEqual(self.campaign.raised_amount, Decimal("10000.00"))
        receipt = self.patient_client.get(f"/api/donations/{donation.uid}/receipt/")
        self.assertEqual(receipt.status_code, 200)
        self.assertEqual(receipt.data["status"], "COMPLETED")

    def test_full_refund_withdraws_receipt_and_counter(self):
        donation = self._complete()
        refund = self.admin_client.post(
            f"/api/admin/donations/{donation.uid}/refund/",
            {"reason": "duplicate", "amount": "10000.00"}, format="json",
        )
        self.assertEqual(refund.status_code, 201)
        donation.refresh_from_db()
        self.assertEqual(donation.status, "REFUNDED")
        self.assertEqual(donation.refunds.filter(status="PROCESSED").count(), 1)
        self.campaign.refresh_from_db()
        self.assertEqual(self.campaign.raised_amount, Decimal("0.00"))
        self.assertEqual(
            self.patient_client.get(f"/api/donations/{donation.uid}/receipt/").status_code, 400)

    def test_refund_requires_admin_permission_code(self):
        donation = self._complete()
        denied = self.patient_client.post(
            f"/api/admin/donations/{donation.uid}/refund/",
            {"reason": "no", "amount": "10000.00"}, format="json",
        )
        self.assertEqual(denied.status_code, 403)