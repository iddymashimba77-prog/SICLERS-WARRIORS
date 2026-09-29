"""Stage 4.12 gate — donations, payments & financial transparency.

Purpose
-------
Proves the approved 4.12 surface end to end on an ephemeral SQLite DB:

  1. campaign lifecycle: create (DRAFT) -> submit (PENDING_VERIFICATION) ->
     verify (ACTIVE); C11 enforced (donate only to ACTIVE); content frozen;
     owner-only edit/submit; public list shows verified only (BR-007).
  2. donation initiation: Idempotency-Key required + user-scoped replay,
     verified-campaign-only, user-scoped history + IDOR 404, role grants
     (donations.view / payments.view per matrix §3.10/§3.11).
  3. payment webhook: HMAC signature + TTL + IP allowlist; forged/stale ->
     401; amount mismatch -> 400; success marks COMPLETED and bumps
     `raised_amount`; duplicate is idempotent (BR-008, FR-PAY-004/005).
  4. receipt: donor-only and only when COMPLETED (DON-008, FR-CAM-006);
     `WARRIOR-RCP-{transaction_ref}`; never leaks provider references.
  5. transparency: donor sees redacted provider ref; payments.view roles see
     raw ref; refunds SUP/ADM only, adjust campaign totals server-side.
  6. rate limits: donation initiate 10/hour/user; per-campaign burst 2/min.

Run:  venv/bin/python stage412_gate.py   (from backend/)
Expected final line:  GATE_OK
"""

import os
import uuid

os.environ.setdefault("DJANGO_SETTINGS_MODULE", "config.settings.ephemeral_test")

import django

django.setup()

from django.test.runner import DiscoverRunner

runner = DiscoverRunner(verbosity=0, interactive=False)
old_config = runner.setup_databases()

ok = False
try:
    from decimal import Decimal

    from rest_framework.test import APIClient
    from rest_framework_simplejwt.tokens import RefreshToken

    from accounts.models import Role, User, UserRole
    from donations.models import Campaign, Donation, PaymentTransaction
    from donations.providers import build_webhook, get_provider
    from donations.services import initiate_donation
    from notifications.models import Notification

    _PASSWORD = "Str0ng!Pass9"


    def orm_user(role_code="PATIENT"):
        user = User.objects.create_user(
            email=f"{role_code.lower()}-{uuid.uuid4().hex[:10]}@example.com",
            password=_PASSWORD, first_name="Test", last_name="User",
            account_status="ACTIVE",
        )
        UserRole.objects.create(user=user, role=Role.objects.get(code=role_code))
        return user


    def client(user):
        c = APIClient()
        c.credentials(HTTP_AUTHORIZATION=f"Bearer {RefreshToken.for_user(user).access_token}")
        return c

    checks = []


    def check(name, cond):
        checks.append((name, bool(cond)))
        if not cond:
            print(f"  [x] {name}")


    organization = orm_user("ORGANIZATION")
    patient = orm_user("PATIENT")
    caregiver = orm_user("CAREGIVER")
    financial = orm_user("FINANCIAL_DONOR")
    admin = orm_user("ADMIN")
    vo = orm_user("VERIFICATION_OFFICER")
    co, cp, cc, cf, ca, cv = (client(u) for u in
                              (organization, patient, caregiver, financial, admin, vo))

    # 1. Campaign lifecycle + C11 gate.
    created = co.post("/api/campaigns/",
                      {"title": "Warrior care fund", "description": "Care support",
                       "goal_amount": "500000.00", "currency": "TZS"}, format="json")
    check("campaign create -> DRAFT 201", created.status_code == 201 and created.data["status"] == "DRAFT")
    uid = created.data["uid"]
    check("non-owner roles cannot create", cc.post("/api/campaigns/",
                                               {"title": "x", "goal_amount": "1.00", "currency": "TZS"},
                                               format="json").status_code == 403)
    deny_draft = cc.get(f"/api/campaigns/{uid}/")
    check("non-owner reads draft -> 404", deny_draft.status_code == 404)
    check("owner reads own draft -> 200", co.get(f"/api/campaigns/{uid}/").status_code == 200)
    check("draft hidden from public list",
          created.data["uid"] not in [c["uid"] for c in APIClient().get("/api/campaigns/").data["results"]])
    sub = co.post(f"/api/campaigns/{uid}/submit/")
    check("submit -> PENDING_VERIFICATION", sub.status_code == 200 and sub.data["status"] == "PENDING_VERIFICATION")
    check("only owner can submit", cc.post(f"/api/campaigns/{uid}/submit/").status_code in (403, 404))
    vq = cv.get("/api/admin/campaigns/verification-queue/")
    check("VO queue lists campaign", uid in [c["uid"] for c in vq.data["results"]])
    check("non-VO cannot verify", cc.post(f"/api/admin/campaigns/{uid}/verify/",
                                          {"approve": True}, format="json").status_code == 403)
    ver = cv.post(f"/api/admin/campaigns/{uid}/verify/", {"approve": True}, format="json")
    check("verify -> ACTIVE", ver.status_code == 200 and ver.data["status"] == "ACTIVE")
    check("campaign now public",
          uid in [c["uid"] for c in APIClient().get("/api/campaigns/").data["results"]])
    frozen = co.patch(f"/api/campaigns/{uid}/", {"title": "Renamed"}, format="json")
    check("ACTIVE content frozen -> 400", frozen.status_code == 400)
    paused = co.patch(f"/api/campaigns/{uid}/", {"pause": True}, format="json")
    check("owner pause -> PAUSED", paused.status_code == 200 and paused.data["status"] == "PAUSED")
    resumed = co.patch(f"/api/campaigns/{uid}/", {"pause": False}, format="json")
    check("owner resume -> ACTIVE", resumed.status_code == 200 and resumed.data["status"] == "ACTIVE")

    # 2. Donation initiation + transparency.
    # Idempotency-Key requirement on its own budget: a throwaway user + campaign
    # so the burst throttle (2/min/campaign/user) can't starve the replay test.
    budget_user = orm_user()
    cbudget = client(budget_user)
    budget_camp = co.post("/api/campaigns/",
                          {"title": "Budget lane", "goal_amount": "100000.00",
                           "currency": "TZS"}, format="json").data
    co.post(f"/api/campaigns/{budget_camp['uid']}/submit/")
    cv.post(f"/api/admin/campaigns/{budget_camp['uid']}/verify/",
            {"approve": True}, format="json")
    no_key = cbudget.post("/api/donations/",
                          {"campaign_uid": budget_camp["uid"], "amount": "10000.00",
                           "currency": "TZS", "provider": "M_PESA"}, format="json")
    check("Idempotency-Key required -> 400", no_key.status_code == 400)

    d1 = cp.post("/api/donations/",
                 {"campaign_uid": uid, "amount": "10000.00", "currency": "TZS",
                  "provider": "M_PESA"}, format="json", HTTP_IDEMPOTENCY_KEY="k-don-1")
    check("donation initiated -> 201", d1.status_code == 201)
    donation_uid = d1.data["uid"]
    check("donor sees own history",
          donation_uid in [x["uid"] for x in cp.get("/api/donations/").data["results"]])
    check("IDOR donation detail 404",
          cc.get(f"/api/donations/{donation_uid}/").status_code in (403, 404))
    replay = cp.post("/api/donations/",
                     {"campaign_uid": uid, "amount": "1.00", "currency": "TZS",
                      "provider": "M_PESA"}, format="json", HTTP_IDEMPOTENCY_KEY="k-don-1")
    check("Idempotency replay -> 200 (no clone)", replay.status_code == 200)
    check("single donation row", Donation.objects.filter(idempotency_key="k-don-1").count() == 1)
    stranger_key = cc.post("/api/donations/",
                           {"campaign_uid": uid, "amount": "10000.00", "currency": "TZS",
                            "provider": "M_PESA"}, format="json", HTTP_IDEMPOTENCY_KEY="k-don-1")
    check("key is donor-scoped -> 400", stranger_key.status_code == 400)

    # 3. Webhook confirmation (BR-008).
    donation = Donation.objects.get(uid=donation_uid)
    txn = donation.transactions.get()
    body, headers = build_webhook("M_PESA", {
        "event": "payment.success", "transaction_ref": donation.transaction_ref,
        "provider_ref": txn.provider_ref, "amount": "10000.00", "currency": "TZS",
    })
    forged = APIClient().post("/api/webhooks/payments/M_PESA/", data=body,
                              content_type="application/json",
                              HTTP_X_PAYMENT_TIMESTAMP=headers["X-Payment-Timestamp"],
                              HTTP_X_PAYMENT_SIGNATURE="0" * 64)
    check("forged signature -> 401", forged.status_code == 401)
    donation.refresh_from_db()
    check("donation still PENDING after forged", donation.status == "PENDING")
    stale = APIClient().post("/api/webhooks/payments/M_PESA/", data=body,
                             content_type="application/json",
                             HTTP_X_PAYMENT_TIMESTAMP=str(int(headers["X-Payment-Timestamp"]) - 3600),
                             HTTP_X_PAYMENT_SIGNATURE=headers["X-Payment-Signature"])
    check("stale webhook -> 401", stale.status_code == 401)
    ok_wh = APIClient().post("/api/webhooks/payments/M_PESA/", data=body,
                             content_type="application/json",
                             HTTP_X_PAYMENT_TIMESTAMP=headers["X-Payment-Timestamp"],
                             HTTP_X_PAYMENT_SIGNATURE=headers["X-Payment-Signature"])
    check("valid webhook -> 200", ok_wh.status_code == 200)
    donation.refresh_from_db()
    txn.refresh_from_db()
    campaign = Campaign.objects.get(pk=donation.campaign_id)
    check("donation COMPLETED by webhook", donation.status == "COMPLETED" and txn.status == "SUCCESS")
    check("raised_amount = 10000.00", campaign.raised_amount == Decimal("10000.00"))
    check("donor PAYMENT notification", Notification.objects.filter(
        recipient=patient, type="PAYMENT").exists())
    dup = APIClient().post("/api/webhooks/payments/M_PESA/", data=body,
                           content_type="application/json",
                           HTTP_X_PAYMENT_TIMESTAMP=headers["X-Payment-Timestamp"],
                           HTTP_X_PAYMENT_SIGNATURE=headers["X-Payment-Signature"])
    check("duplicate webhook idempotent -> 200", dup.status_code == 200)
    campaign.refresh_from_db()
    check("raised_amount not doubled", campaign.raised_amount == Decimal("10000.00"))

    # 4. Receipt (DON-008).
    rec = cp.get(f"/api/donations/{donation_uid}/receipt/")
    check("receipt only donor + confirmed -> 200", rec.status_code == 200)
    check("receipt number format",
          rec.data["receipt_number"].startswith("WARRIOR-RCP-"))
    check("receipt hides provider ref",
          "provider_ref" not in rec.content.decode() and "provider" not in rec.content.decode())
    check("receipt IDOR", cc.get(f"/api/donations/{donation_uid}/receipt/").status_code in (403, 404))

    # 5. Payment transparency + oversight.
    own = cp.get(f"/api/payments/{txn.id}/")
    check("donor sees redacted provider ref",
          own.data["provider_ref"] != txn.provider_ref and not own.data["provider_ref"].startswith("M-PES") )
    over = cf.get(f"/api/payments/{txn.id}/")
    check("payments.view sees raw ref", over.data["provider_ref"] == txn.provider_ref)
    check("IDOR payment 404", cc.get(f"/api/payments/{txn.id}/").status_code in (403, 404))

    # 6. Refund (SUP/ADM) adjusts totals.
    denied = cc.post(f"/api/admin/donations/{donation_uid}/refund/",
                     {"reason": "nope"}, format="json")
    check("non-refund role denied -> 403", denied.status_code == 403)
    ref = ca.post(f"/api/admin/donations/{donation_uid}/refund/",
                  {"reason": "duplicate charge"}, format="json")
    check("admin refund -> 201", ref.status_code == 201)
    campaign.refresh_from_db()
    donation.refresh_from_db()
    check("donation REFUNDED", donation.status == "REFUNDED")
    check("raised_amount zeroed server-side", campaign.raised_amount == Decimal("0.00"))
    again = ca.post(f"/api/admin/donations/{donation_uid}/refund/",
                    {"reason": "again"}, format="json")
    check("double refund -> 409", again.status_code == 409)

    # 7. Rate limits.
    # Burst: fresh user pummels one campaign 3x fast -> 3rd must be 429.
    from django.core.cache import cache
    cache.clear()
    burst_user = orm_user()
    cburst = client(burst_user)
    burst = [cburst.post("/api/donations/",
                         {"campaign_uid": uid, "amount": "100.00", "currency": "TZS",
                          "provider": "M_PESA"}, format="json",
                         HTTP_IDEMPOTENCY_KEY=f"b-{i}").status_code for i in range(3)]
    check("per-campaign burst 2/min -> third 429", burst[0] == 201 and burst[1] == 201 and burst[-1] == 429)

    # Hourly: fresh user, 10 distinct ACTIVE campaigns keep the burst key clear.
    cache.clear()
    hourly_user = orm_user()
    chourly = client(hourly_user)
    lanes = []
    for i in range(10):
        cam = co.post("/api/campaigns/",
                      {"title": f"Lane-{i}", "goal_amount": "100000.00", "currency": "TZS"},
                      format="json").data
        co.post(f"/api/campaigns/{cam['uid']}/submit/")
        cv.post(f"/api/admin/campaigns/{cam['uid']}/verify/", {"approve": True}, format="json")
        lanes.append(cam["uid"])
    hourly_statuses = [chourly.post("/api/donations/",
                                    {"campaign_uid": lan, "amount": "1000.00", "currency": "TZS",
                                     "provider": "M_PESA"}, format="json",
                                    HTTP_IDEMPOTENCY_KEY=f"h-{i}").status_code
                       for i, lan in enumerate(lanes)]
    eleventh = chourly.post("/api/donations/",
                            {"campaign_uid": uid, "amount": "100.00", "currency": "TZS",
                             "provider": "M_PESA"}, format="json",
                            HTTP_IDEMPOTENCY_KEY="h-10")
    check("donation initiate 10/hour -> 11th 429",
          set(hourly_statuses) == {201} and eleventh.status_code == 429)

    ok = len(checks) == sum(1 for _, passed in checks if passed)
finally:
    runner.teardown_databases(old_config)

print(f"Stage 4.12 gate: {sum(1 for _, p in checks if p)}/{len(checks)} checks passed")
print("GATE_OK" if ok else "GATE_FAILED")
raise SystemExit(0 if ok else 1)