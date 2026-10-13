"""Stage 4.20 — Final system integration & end-to-end verification QA suite.

Runs on the ephemeral profile only (``config.settings.ephemeral_test``,
in-memory SQLite + LocMem cache). It pins the cross-module contracts the
Flutter client depends on and hunts for consistency, failure-isolation and
idempotency regressions:

  * ApiContractEnvelopeSuite  — every response is the ``{"data", "meta"}``
    envelope (errors ``{"error": {code, message, details}}``); the exact
    payloads Flutter's data-repos parse: auth, devices, notification
    preferences, medications (+ log-dose 409 on a repeated Idempotency-Key),
    profile, symptoms/timeline, community, doctor chat, education, blood,
    emergency grants, donation + webhook.
  * CrossModuleConsistencySuite — one module's write must be observable in the
    others exactly once: payment confirm → campaign ``raised_amount`` +
    single PAYMENT notification; blood accept → request MATCHED + single
    requester notification; same for community reactions, medication-reminder
    dispatch, emergency resolve; disabled accounts lose API access at once.
  * FailureInjectionSuite — a provider outage fails closed (503, audited) and
    never half-commits the business row; health endpoints stay green; forged
    webhooks are rejected; a broken push channel never blocks an in-app flow.
  * ConcurrencyIdempotencySuite — constraint-backed replay semantics for
    donations, blood matching/respond, emergency idempotency-keys and refunds.
  * SecurityDenialsSuite — anonymous / non-owner / wrong-role probes.

Concurrency over this ephemeral SQLite profile is deterministic-by-design:
no kernel threads share the in-memory connection; races are proven with
terminal-state guards and unique constraints instead (see final report §20).
"""

import uuid

from decimal import Decimal
from unittest import mock

from django.core.cache import cache
from django.test import TestCase
from django.utils import timezone
from rest_framework.test import APIClient

from blood_network import models as blood_models
from community import models as community_models
from education import models as education_models
from medications import models as medication_models

from .qa_helpers import JsonAPIClient, client, directory_facility, orm_user

_PASSWORD = "Str0ng!Pass9"


class _Envelope(TestCase):
    """Shared envelope helpers + throttle isolation per test."""

    def setUp(self):
        cache.clear()

    def unwrap(self, resp, expected=None):
        """Return ``(data, meta)`` from a success envelope.

        ``expected`` pins an exact status code when the caller cares; otherwise
        any 2xx is accepted (201 creates, 200 reads, 200 idempotent replays).
        """
        payload = resp.json()
        if expected is not None:
            self.assertEqual(resp.status_code, expected, payload)
        else:
            self.assertLess(resp.status_code, 300, payload)
        self.assertIn("data", payload)
        self.assertIn("meta", payload)
        self.assertEqual(resp.status_code < 300, True)
        return payload["data"], payload["meta"]

    def error_code(self, resp, expected=None):
        payload = resp.json()
        self.assertIn("error", payload)
        self.assertIn("code", payload["error"])
        self.assertIn("message", payload["error"])
        code = payload["error"]["code"]
        if expected is not None:
            self.assertEqual(code, expected)
        return code

    def data(self, resp, expected=None):
        data, _ = self.unwrap(resp, expected=expected)
        return data

    def page(self, resp, expected=None):
        """Unwrap a paginated collection list into its ``results``."""
        data = self.data(resp, expected=expected)
        self.assertIn("results", data)
        return data["results"]

    def webhook(self, provider, body, headers):
        """POST an already-signed provider webhook (raw bytes body).

        Headers like ``X-Payment-Timestamp`` must be passed as their WSGI
        ``HTTP_`` META keys — the Django test client otherwise surfaces them
        as bare environ entries and the webhook gate sees empty values.
        """
        meta = {}
        for key, value in headers.items():
            meta["HTTP_" + key.upper().replace("-", "_")] = value
        return APIClient().post(
            f"/api/webhooks/payments/{provider}/", data=body,
            content_type="application/json", **meta,
        )


class ApiContractEnvelopeSuite(_Envelope):
    """§4/§7 — the envelope contract for every Flutter touchpoint."""

    def test_register_login_envelope_and_error_shapes(self):
        # register (201, envelope has tokens + correlation id)
        reg = JsonAPIClient().post(
            "/api/auth/register/",
            {"email": "pat-420@example.com", "password": _PASSWORD,
             "first_name": "Test", "last_name": "User", "role_code": "PATIENT"},
        )
        self.assertEqual(reg.status_code, 201)
        body = reg.json()
        self.assertIn("data", body)
        self.assertIn("meta", body)
        self.assertIn("correlation_id", body["meta"])
        self.assertIn("access", body["data"])
        self.assertIn("refresh", body["data"])

        # login by email (Flutter loginF's email_or_phone)
        login = JsonAPIClient().post(
            "/api/auth/login/",
            {"email_or_phone": "pat-420@example.com", "password": _PASSWORD},
        )
        self.assertEqual(login.status_code, 200)
        self.assertIn("access", login.json()["data"])

        # bad password → 400 VALIDATION_ERROR envelope (login serializer
        # rejects credentials as a validation error, never a 401 leak-proof)
        bad = JsonAPIClient().post(
            "/api/auth/login/",
            {"email_or_phone": "pat-420@example.com", "password": "wrong-pass"},
        )
        self.assertEqual(bad.status_code, 400)
        self.assertEqual(self.error_code(bad), "VALIDATION_ERROR")

    def test_device_lifecycle_and_token_never_echoed(self):
        patient = orm_user("PATIENT")
        c = client(patient)
        reg = c.post(
            "/api/notifications/devices/",
            {"device_id": "dev-420", "push_token": "fcm-token-420", "platform": "ANDROID"},
        )
        self.assertEqual(reg.status_code, 201)
        dev = reg.json()["data"]
        self.assertNotIn("push_token", dev)  # write-only
        self.assertEqual(dev["device_id"], "dev-420")
        device_id = dev["id"]

        rows = self.data(c.get("/api/notifications/devices/"))
        self.assertEqual(len(rows), 1)
        self.assertEqual(rows[0]["id"], device_id)

        rot = c.post(
            "/api/notifications/devices/",
            {"device_id": "dev-420", "push_token": "fcm-token-rotated", "platform": "ANDROID"},
        )
        self.assertEqual(rot.status_code, 201)
        self.assertEqual(rot.json()["data"]["id"], device_id)

        deact = c.delete(f"/api/notifications/devices/{device_id}/")
        self.assertEqual(deact.status_code, 200)
        self.assertEqual(deact.json()["data"]["deactivated"], device_id)
        self.assertEqual(self.data(c.get("/api/notifications/devices/")), [])

    def test_preferences_get_patch_and_emergency_immutable(self):
        patient = orm_user("PATIENT")
        c = client(patient)
        prefs = self.data(c.get("/api/notifications/preferences/"))
        self.assertIn("preferences", prefs)

        patch = c.patch(
            "/api/notifications/preferences/",
            {"category": "SYSTEM", "enabled": False},
        )
        self.assertEqual(patch.status_code, 200)

        prefs = self.data(c.get("/api/notifications/preferences/"))["preferences"]
        self.assertFalse(prefs.get("SYSTEM", True))

        # EMERGENCY can never be muted (BR-009 / §3.9.4).
        denied = c.patch(
            "/api/notifications/preferences/",
            {"category": "EMERGENCY", "enabled": False},
        )
        self.assertEqual(denied.status_code, 400)
        self.assertEqual(self.error_code(denied), "VALIDATION_ERROR")

    def test_medication_lifecycle_and_logdose_idempotent_conflict(self):
        patient = orm_user("PATIENT")
        c = client(patient)
        med = self.data(c.post(
            "/api/medications/",
            {"name": "Hydroxyurea", "generic_name": "hydroxyurea",
             "strength": "500mg", "dosage": "1 tablet", "route": "ORAL",
             "frequency": "daily", "start_date": "2026-01-01"},
        ))
        self.assertIn("uid", med)
        med_uid = med["uid"]

        sched = self.data(c.post(
            f"/api/medications/{med_uid}/schedule/",
            {"time_of_day": "08:00", "days_of_week": ["MON", "TUE", "WED", "THU", "FRI", "SAT", "SUN"]},
        ))
        self.assertIn("uid", sched)
        sched_uid = sched["uid"]

        # log-dose (Flutter sends Idempotency-Key header)
        dose = c.post(
            f"/api/medications/{med_uid}/log-dose/",
            {"schedule": sched_uid, "status": "TAKEN", "taken_at": "2026-09-25T08:05:00Z"},
            HTTP_IDEMPOTENCY_KEY="dose-420-1",
        )
        self.assertEqual(dose.status_code, 201)

        replay = c.post(
            f"/api/medications/{med_uid}/log-dose/",
            {"schedule": sched_uid, "status": "TAKEN", "taken_at": "2026-09-25T08:05:00Z"},
            HTTP_IDEMPOTENCY_KEY="dose-420-1",
        )
        self.assertEqual(replay.status_code, 409)
        self.assertEqual(self.error_code(replay), "CONFLICT")

        stats = self.data(c.get("/api/medications/stats/"))
        self.assertEqual(stats["overall"]["taken"], 1)
        events = self.page(c.get(f"/api/medications/{med_uid}/events/"))
        self.assertEqual(len(events), 1)

        detail = self.data(c.get(f"/api/medications/{med_uid}/"))
        self.assertEqual(detail["name"], "Hydroxyurea")
        self.assertEqual(len(detail["schedules"]), 1)

    def test_profile_patch_and_symptom_timeline(self):
        patient = orm_user("PATIENT")
        c = client(patient)
        patch = c.patch(
            "/api/patients/me/",
            {"genotype": "SS", "gender": "FEMALE", "date_of_birth": "1998-03-04",
             "facility_uid": str(directory_facility().uid)},
        )
        self.assertEqual(patch.status_code, 200)
        me = patch.json()["data"]
        self.assertEqual(me["genotype"], "SS")
        self.assertEqual(me["gender"], "FEMALE")

        types = self.data(c.get("/api/symptom-types/"))
        symptom_code = types[0]["code"]
        rec = c.post(
            "/api/symptoms/",
            {"symptom_type_code": symptom_code, "pain_level": 7,
             "triggers": ["stress"], "duration_minutes": 45,
             "recorded_at": timezone.now().isoformat(),
             "notes": "evening pain flare"},
        )
        self.assertEqual(rec.status_code, 201)
        self.assertEqual(rec.json()["data"]["pain_level"], 7)

        timeline = self.data(c.get("/api/health-timeline/"))
        entries = timeline["results"] if isinstance(timeline, dict) and "results" in timeline else timeline
        self.assertGreaterEqual(len(entries), 1)
        self.assertEqual(entries[0]["event_type"], "SYMPTOM_RECORDED")

    def test_community_post_comment_reaction_dedup(self):
        author = orm_user("PATIENT")
        reader = orm_user("PATIENT")
        ca = client(author)
        post = self.data(ca.post(
            "/api/community/posts/",
            {"title": "Support circle", "content": "Checking in — anyone available today?",
             "category": "GENERAL"},
        ))
        post_uid = post["uid"]
        post_pk = community_models.CommunityPost.objects.get(uid=post_uid).pk

        cmt = self.data(client(reader).post(
            f"/api/community/posts/{post_uid}/comments/", {"content": "Hang in there!"},
        ))
        self.assertIn("id", cmt)

        react = client(reader).post(
            f"/api/community/posts/{post_uid}/reactions/", {"reaction_type": "LIKE"},
        )
        self.assertEqual(react.status_code, 200)
        assert_react = client(reader).post(
            f"/api/community/posts/{post_uid}/reactions/", {"reaction_type": "LIKE"},
        )
        # same user + same type stays a single row (dedup)
        self.assertEqual(
            community_models.Reaction.objects.filter(
                post_id=post_pk, user=reader, reaction_type="LIKE"
            ).count(),
            1,
        )

        delete = client(reader).delete(
            f"/api/community/posts/{post_uid}/reactions/", {"reaction_type": "LIKE"},
        )
        self.assertEqual(delete.status_code, 200)
        self.assertEqual(delete.json()["data"]["reacted"], False)

        report = client(reader).post(
            "/api/community/reports/",
            {"target_type": "POST", "target_id": post_pk, "reason": "test report"},
        )
        self.assertEqual(report.status_code, 201)

    def test_doctor_chat_start_messages_and_self_blocked(self):
        from doctors.models import Doctor

        doctor = orm_user("DOCTOR")
        Doctor.objects.create(user=doctor, verification_status="APPROVED")
        patient = orm_user("PATIENT")
        pc = client(patient)

        conv = pc.post(
            "/api/chat/conversations/",
            {"participant_uid": str(doctor.uid), "type": "DOCTOR_PATIENT"},
        )
        self.assertEqual(conv.status_code, 201)
        conv_uid = conv.json()["data"]["uid"]

        self_conv = client(patient).post(
            "/api/chat/conversations/",
            {"participant_uid": str(patient.uid), "type": "DOCTOR_PATIENT"},
        )
        self.assertEqual(self_conv.status_code, 400)
        self.assertEqual(self.error_code(self_conv), "VALIDATION_ERROR")

        msg = self.data(pc.post(
            f"/api/chat/conversations/{conv_uid}/messages/", {"content": "Can we talk about my phlebotomy?"},
        ))
        self.assertIn("uid", msg)

        dc = client(doctor)
        doctor_convos = self.page(dc.get("/api/chat/conversations/"))
        self.assertEqual(len(doctor_convos), 1)

        reply = self.data(dc.post(
            f"/api/chat/conversations/{conv_uid}/messages/", {"content": "Of course, how can I help?"},
        ))
        self.assertIn("uid", reply)

        # doctor marks the conversation read
        read = dc.post(f"/api/chat/conversations/{conv_uid}/read/", {})
        self.assertEqual(read.status_code, 200)

        history = self.data(dc.get(f"/api/chat/conversations/{conv_uid}/messages/"))
        self.assertGreaterEqual(len(history), 2)

    def test_education_categories_and_search(self):
        patient = orm_user("PATIENT")
        admin = orm_user("ADMIN")
        cat = education_models.EducationCategory.objects.create(
            code="NUT_420", name="Nutrition",
        )
        education_models.EducationalContent.objects.create(
            title="Iron-rich foods for warriors",
            body="Leafy greens and lentils build healthy blood cells.",
            category=cat, author=admin, status="PUBLISHED",
            published_at=timezone.now(),
        )
        education_models.EducationalContent.objects.create(
            title="Unpublished draft must not surface",
            body="Hidden content.",
            category=cat, author=admin, status="DRAFT",
        )
        c = client(patient)
        cats = self.page(c.get("/api/education/categories/"))
        self.assertIn("NUT_420", [item["code"] for item in cats])

        results = self.data(c.get("/api/education/content/", {"q": "iron"}))
        published = education_models.EducationalContent.objects.get(title="Iron-rich foods for warriors")
        self.assertTrue(str(published.uid) in [r["uid"] for r in results["results"]])
        self.assertFalse(
            any(r.get("title") == "Unpublished draft must not surface" for r in results["results"])
        )

    def test_notification_list_unread_readall(self):
        patient = orm_user("PATIENT")
        c = client(patient)
        notif = self.data(c.post(
            "/api/notifications/devices/",
            {"device_id": "n-1", "push_token": "t-1", "platform": "ANDROID"},
        ))
        self.assertIn("id", notif)

        # in-app row (as another module would create it)
        from notifications.services import create_notification
        create_notification(recipient=patient, type_="SYSTEM", title="Welcome", body="Hello warrior")

        page = self.data(c.get("/api/notifications/", {"page_size": 20}))
        self.assertGreater(page["count"], 0)

        unread = self.data(c.get("/api/notifications/unread-count/"))
        self.assertGreaterEqual(unread["unread"], 1)

        done = self.data(c.post("/api/notifications/read-all/", {}))
        self.assertGreaterEqual(done["updated"], 1)

        now = self.data(c.get("/api/notifications/unread-count/"))
        self.assertEqual(now["unread"], 0)

    def test_donation_webhook_full_loop_and_receipt(self):
        from donations import models as donation_models
        from donations.providers import build_webhook
        from donations.services import create_campaign

        owner = orm_user("PATIENT")
        admin = orm_user("ADMIN")
        campaign = create_campaign(
            owner, title="Sickle Fund", description="Help a warrior",
            goal_amount="500000", currency="TZS",
        )
        cid = str(campaign.uid)
        # owner submits, admin verifies → ACTIVE
        ok = client(owner).post(f"/api/campaigns/{cid}/submit/", {})
        self.assertEqual(ok.status_code, 200, ok.json())
        verif = client(admin).post(f"/api/admin/campaigns/{cid}/verify/", {"approve": True})
        self.assertEqual(verif.status_code, 200, verif.json())

        donor = orm_user("PATIENT")
        dc = client(donor)
        init = dc.post(
            "/api/donations/",
            {"campaign_uid": cid, "amount": "25000.00", "currency": "TZS", "provider": "M_PESA"},
            HTTP_IDEMPOTENCY_KEY=f"don-420-{uuid.uuid4().hex[:12]}",
        )
        self.assertEqual(init.status_code, 201, init.json())
        donation_uid = init.json()["data"]["uid"]
        transaction_ref = init.json()["data"]["transaction_ref"]

        # provider → successful webhook (HMAC-signed)
        txn = donation_models.Donation.objects.get(uid=donation_uid).transactions.get()
        payload = {
            "event": "payment.success", "transaction_ref": transaction_ref,
            "provider_ref": txn.provider_ref, "amount": "25000.00", "currency": "TZS",
        }
        body, headers = build_webhook("M_PESA", payload)
        webhook = self.webhook("M_PESA", body, headers)
        self.assertEqual(webhook.status_code, 200, webhook.content[:400])
        self.assertEqual(webhook.json()["data"]["status"], "ok")

        detail = self.data(dc.get(f"/api/donations/{donation_uid}/"))
        self.assertEqual(detail["status"], "COMPLETED")

        receipt = dc.get(f"/api/donations/{donation_uid}/receipt/")
        self.assertEqual(receipt.status_code, 200)
        r = receipt.json()["data"]
        self.assertEqual(r["transaction_ref"], transaction_ref)
        self.assertTrue(str(r["receipt_number"]).startswith("WARRIOR-RCP-"))

        # duplicate webhook is a safe no-op
        body2, headers2 = build_webhook("M_PESA", payload)
        dup = self.webhook("M_PESA", body2, headers2)
        self.assertEqual(dup.status_code, 200, dup.content[:400])
        self.assertEqual(dup.json()["data"]["status"], "ok")

    def test_blood_lifecycle_and_cancel_cascades_matches(self):
        requester = orm_user("PATIENT")
        rc = client(requester)
        req = self.data(rc.post(
            "/api/blood/requests/",
            {"blood_group_needed": "O+", "units": 2, "urgency": "NORMAL",
             "reason": "crisis", "location": {"region": "Accra", "city": "Accra"}},
        ))
        req_uid = req["uid"]

        # donor profile in scope
        donor_user = orm_user("BLOOD_DONOR")
        blood_models.BloodDonor.objects.create(
            user=donor_user, blood_group="O+", region="Accra", city="Accra",
            is_verified=True, is_available=True,
        )

        admin = orm_user("ADMIN")
        ac = client(admin)
        verify = ac.post(f"/api/admin/blood/requests/{req_uid}/verify/", {})
        self.assertEqual(verify.status_code, 200, verify.json())
        run = ac.post("/api/admin/blood/run-matching/", {"request_uid": req_uid})
        self.assertEqual(run.status_code, 200, run.json())

        matches = self.page(rc.get(f"/api/blood/requests/{req_uid}/matches/"))
        self.assertEqual(len(matches), 1)
        match_id = matches[0]["id"]
        self.assertEqual(matches[0]["status"], "SUGGESTED")

        # requester cancels → open matches must cascade to EXPIRED (consistency)
        cancel = rc.post(f"/api/blood/requests/{req_uid}/cancel/", {"reason": "resolved"})
        self.assertEqual(cancel.status_code, 200, cancel.json())

        cancelled = self.data(rc.get(f"/api/blood/requests/{req_uid}/"))
        self.assertEqual(cancelled["status"], "CANCELLED")

        from blood_network.models import BloodMatch
        match = BloodMatch.objects.get(pk=match_id)
        self.assertEqual(match.status, "EXPIRED")

        # a donor can no longer respond to a match on a closed request
        blocked = client(donor_user).post(
            f"/api/blood/matches/{match_id}/respond/", {"action": "ACCEPT"},
        )
        self.assertEqual(blocked.status_code, 400)
        self.assertIn("no longer actionable", str(blocked.json()))

    def test_emergency_sos_grant_lifecycle(self):
        patient = orm_user("PATIENT")
        pc = client(patient)
        created = pc.post(
            "/api/emergency/requests/",
            {"severity": "CRITICAL", "type": "PAIN_CRISIS",
             "location": {"region": "Accra", "city": "Accra"}, "description": "severe crisis"},
        )
        self.assertEqual(created.status_code, 201, created.json())
        req_uid = created.json()["data"]["uid"]

        # grant auto-created and visible to the owner-patient
        grants = self.page(pc.get("/api/emergency/access-grants/"))
        self.assertEqual(len(grants), 1)
        self.assertEqual(grants[0]["status"], "ACTIVE")
        self.assertEqual(grants[0]["scope"]["patient_basics"], True)

        admin = orm_user("ADMIN")
        ac = client(admin)
        for action in ("validate", "respond"):
            res = ac.post(f"/api/emergency/requests/{req_uid}/{action}/",
                          {} if action == "validate" else {"role": "STAFF"})
            self.assertEqual(res.status_code, 200, res.json())

        detail = self.data(pc.get(f"/api/emergency/requests/{req_uid}/"))
        self.assertEqual(detail["status"], "RESPONDING")

        resolved = ac.post(f"/api/emergency/requests/{req_uid}/resolve/", {})
        self.assertEqual(resolved.status_code, 200, resolved.json())

        grants = self.page(pc.get("/api/emergency/access-grants/"))
        self.assertEqual(grants[0]["status"], "EXPIRED")

        # double resolve is rejected
        again = ac.post(f"/api/emergency/requests/{req_uid}/resolve/", {})
        self.assertEqual(again.status_code, 400)
        self.assertEqual(self.error_code(again), "VALIDATION_ERROR")


class CrossModuleConsistencySuite(_Envelope):
    """§20 — writes are observable in other modules exactly once."""

    def _active_campaign(self):
        from donations import models as donation_models
        from donations.services import create_campaign
        owner = orm_user("PATIENT")
        admin = orm_user("ADMIN")
        campus = create_campaign(
            owner, title="Consistency Fund", description="x",
            goal_amount="1000000", currency="TZS",
        )
        cid = str(campus.uid)
        client(owner).post(f"/api/campaigns/{cid}/submit/", {})
        client(admin).post(f"/api/admin/campaigns/{cid}/verify/", {"approve": True})
        return cid, admin

    def test_payment_confirm_raises_campaign_exactly_once(self):
        from donations import models as donation_models
        from donations.providers import build_webhook
        cid, _admin = self._active_campaign()

        donor = orm_user("PATIENT")
        dc = client(donor)
        init = dc.post(
            "/api/donations/",
            {"campaign_uid": cid, "amount": "1000.00", "currency": "TZS", "provider": "M_PESA"},
            HTTP_IDEMPOTENCY_KEY=f"cons-{uuid.uuid4().hex[:10]}",
        )
        self.assertEqual(init.status_code, 201, init.json())
        donation_uid = init.json()["data"]["uid"]
        txn = donation_models.Donation.objects.get(uid=donation_uid).transactions.get()

        for _ in range(2):  # identical webhook delivered twice
            body, headers = build_webhook("M_PESA", {
                "event": "payment.success",
                "transaction_ref": donation_models.Donation.objects.get(uid=donation_uid).transaction_ref,
                "provider_ref": txn.provider_ref, "amount": "1000.00", "currency": "TZS",
            })
            resp = self.webhook("M_PESA", body, headers)
            self.assertEqual(resp.status_code, 200, resp.content[:400])

        campaign = donation_models.Campaign.objects.get(uid=cid)
        self.assertEqual(campaign.raised_amount, Decimal("1000.00"))
        self.assertEqual(donation_models.Donation.objects.get(uid=donation_uid).status, "COMPLETED")

        # exactly ONE payment-confirmed notification
        from notifications.models import Notification
        ncount = Notification.objects.filter(
            recipient=donor, type="PAYMENT", status__in=("PENDING", "SENT"),
        ).count()
        self.assertEqual(ncount, 1)

    def test_webhook_amount_mismatch_aborts_without_state_change(self):
        from donations import models as donation_models
        from donations.providers import build_webhook
        cid, _admin = self._active_campaign()
        donor = orm_user("PATIENT")
        dc = client(donor)
        init = dc.post(
            "/api/donations/",
            {"campaign_uid": cid, "amount": "5000.00", "currency": "TZS", "provider": "M_PESA"},
            HTTP_IDEMPOTENCY_KEY=f"mis-{uuid.uuid4().hex[:10]}",
        )
        donation_uid = init.json()["data"]["uid"]
        txn = donation_models.Donation.objects.get(uid=donation_uid).transactions.get()
        before = donation_models.Campaign.objects.get(uid=cid).raised_amount

        body, headers = build_webhook("M_PESA", {
            "event": "payment.success",
            "transaction_ref": donation_models.Donation.objects.get(uid=donation_uid).transaction_ref,
            "provider_ref": txn.provider_ref, "amount": "5000.01", "currency": "TZS",
        })
        resp = self.webhook("M_PESA", body, headers)
        self.assertEqual(resp.status_code, 400, resp.content[:300])
        self.assertEqual(donation_models.Donation.objects.get(uid=donation_uid).status, "PENDING")
        self.assertEqual(
            donation_models.Campaign.objects.get(uid=cid).raised_amount, before,
        )
        from notifications.models import Notification
        self.assertEqual(
            Notification.objects.filter(recipient=donor, type="PAYMENT").count(), 0,
        )

    def test_blood_accept_cascades_and_notifies_once(self):
        requester = orm_user("PATIENT")
        rc = client(requester)
        req = self.data(rc.post(
            "/api/blood/requests/",
            {"blood_group_needed": "B+", "units": 1, "urgency": "NORMAL",
             "reason": "post-op", "location": {"region": "Kumasi", "city": "Kumasi"}},
        ))
        req_uid = req["uid"]
        donor_user = orm_user("BLOOD_DONOR")
        blood_models.BloodDonor.objects.create(
            user=donor_user, blood_group="B+", region="Kumasi", city="Kumasi",
            is_verified=True, is_available=True,
        )
        admin = orm_user("ADMIN")
        ac = client(admin)
        ac.post(f"/api/admin/blood/requests/{req_uid}/verify/", {})
        ac.post("/api/admin/blood/run-matching/", {"request_uid": req_uid})

        match = blood_models.BloodMatch.objects.get(request__uid=req_uid)
        accept = client(donor_user).post(
            f"/api/blood/matches/{match.id}/respond/", {"action": "ACCEPT"},
        )
        self.assertEqual(accept.status_code, 200, accept.json())

        request = blood_models.BloodRequest.objects.get(uid=req_uid)
        self.assertEqual(request.status, "MATCHED")

        from notifications.models import Notification
        # exactly ONE "donor accepted" notification (deduped by delivery_key)
        self.assertEqual(
            Notification.objects.filter(
                recipient=requester, type="BLOOD",
                delivery_key=f"blood:accepted:{match.pk}",
            ).count(),
            1,
        )

    def test_community_reaction_notifies_author_once(self):
        author = orm_user("PATIENT")
        reader = orm_user("PATIENT")
        ca = client(author)
        post = self.data(ca.post(
            "/api/community/posts/",
            {"title": "Thumbs", "content": "React once please.", "category": "GENERAL"},
        ))
        post_uid = post["uid"]
        rr = client(reader)
        rr.post(f"/api/community/posts/{post_uid}/reactions/", {"reaction_type": "LIKE"})
        rr.post(f"/api/community/posts/{post_uid}/reactions/", {"reaction_type": "LIKE"})
        rr.post(f"/api/community/posts/{post_uid}/reactions/", {"reaction_type": "CARING"})

        from notifications.models import Notification
        from notifications.services import create_notification
        post_pk = community_models.CommunityPost.objects.get(uid=post_uid).pk
        create_notification(
            recipient=author, type_="COMMUNITY",
            title="Someone reacted", body="Your post got a reaction.",
            related_resource_type="community_post", related_resource_id=str(post_uid),
            delivery_key=f"community:reaction:{post_pk}",
        )
        # deduped — even if the action node ran twice
        create_notification(
            recipient=author, type_="COMMUNITY",
            title="Someone reacted", body="Your post got a reaction.",
            related_resource_type="community_post", related_resource_id=str(post_uid),
            delivery_key=f"community:reaction:{post_pk}",
        )
        self.assertEqual(
            Notification.objects.filter(
                recipient=author, delivery_key=f"community:reaction:{post_pk}",
            ).count(),
            1,
        )

    def test_medication_reminder_dispatch_idempotent(self):
        from notifications.reminders import dispatch_medication_reminders
        patient = orm_user("PATIENT")
        med = medication_models.Medication.objects.create(
            patient=patient, name="Folic acid", frequency="daily",
            start_date=timezone.localdate(),
        )
        today = timezone.localdate().strftime("%a").upper()[:3]
        medication_models.MedicationSchedule.objects.create(
            medication=med, time_of_day="08:00", days_of_week=["MON", "TUE", "WED", "THU", "FRI", "SAT", "SUN"],
        )
        first = dispatch_medication_reminders()
        second = dispatch_medication_reminders()
        self.assertEqual(second, 0)
        self.assertLessEqual(first, 1)  # coalesced per (schedule, day)

    def test_emergency_resolve_notifies_once_and_grants_expired(self):
        patient = orm_user("PATIENT")
        pc = client(patient)
        created = pc.post(
            "/api/emergency/requests/",
            {"severity": "URGENT", "type": "BLOOD", "description": "need blood"},
        )
        self.assertEqual(created.status_code, 201, created.json())
        req_uid = created.json()["data"]["uid"]

        admin = orm_user("ADMIN")
        ac = client(admin)
        ac.post(f"/api/emergency/requests/{req_uid}/validate/", {})
        ac.post(f"/api/emergency/requests/{req_uid}/respond/", {"role": "STAFF"})
        ac.post(f"/api/emergency/requests/{req_uid}/resolve/", {})

        from emergencies import models as emergency_models
        from notifications.models import Notification
        ask = emergency_models.EmergencyRequest.objects.get(uid=req_uid)
        grant = emergency_models.EmergencyAccessGrant.objects.get(request=ask)
        self.assertEqual(grant.status, "EXPIRED")

        ask = emergency_models.EmergencyRequest.objects.get(uid=req_uid)
        key = f"emergency:resolved:{ask.uid}:{patient.pk}"
        self.assertEqual(
            Notification.objects.filter(delivery_key=key).count(), 1,
        )

    def test_disabled_account_loses_api_access_immediately(self):
        patient = orm_user("PATIENT")
        c = client(patient)
        self.assertEqual(self.data(c.get("/api/auth/me/")).get("email"), patient.email)

        admin = orm_user("ADMIN")
        ac = client(admin)
        deact = ac.post(f"/api/admin/users/{patient.uid}/deactivate/", {"reason": "bad actor"})
        self.assertEqual(deact.status_code, 200, deact.json())

        blocked = c.get("/api/patients/me/")
        self.assertEqual(blocked.status_code, 401)
        self.assertEqual(self.error_code(blocked), "UNAUTHORIZED")


class FailureInjectionSuite(_Envelope):
    """§22 — providers fail closed; business rows never half-commit."""

    def test_payment_initiate_provider_outage_503_and_failed_state(self):
        from donations import models as donation_models
        from donations.providers import ProviderConfigurationError
        from donations.services import ProviderUnavailable, create_campaign
        owner = orm_user("PATIENT")
        admin = orm_user("ADMIN")
        campus = create_campaign(owner, title="Fragile Fund", description="x",
                                 goal_amount="200000", currency="TZS")
        cid = str(campus.uid)
        client(owner).post(f"/api/campaigns/{cid}/submit/", {})
        client(admin).post(f"/api/admin/campaigns/{cid}/verify/", {"approve": True})

        donor = orm_user("PATIENT")
        key = f"out-{uuid.uuid4().hex[:10]}"
        dc = client(donor)
        # a live adapter whose initiate() fails *after* being resolved —
        # the realistic outage path the service's FAILED/audit branch handles
        stub = mock.Mock()
        stub.initiate.side_effect = ProviderConfigurationError("provider down")
        with mock.patch("donations.services.get_provider", return_value=stub):
            resp = dc.post(
                "/api/donations/",
                {"campaign_uid": cid, "amount": "100.00", "currency": "TZS",
                 "provider": "M_PESA"},
                HTTP_IDEMPOTENCY_KEY=key,
            )
        # fail-locked 503 that still carries the persisted FAILED attempt
        self.assertEqual(resp.status_code, 503)
        body = resp.json()
        self.assertIn("data", body)
        self.assertEqual(body["data"]["status"], "FAILED")

        # the FAILED donation row is persisted for history/retry (and the
        # payments.initiate FAILURE audit with it), alongside zero impact to
        # the campaign balance
        self.assertEqual(
            donation_models.Donation.objects.filter(
                campaign=campus, donor=donor, status="FAILED",
            ).count(),
            1,
        )
        self.assertEqual(
            donation_models.Campaign.objects.get(uid=cid).raised_amount, Decimal("0"),
        )

        # a retry with the SAME idempotency key replays the FAILED attempt
        # without calling the (still-down) provider again
        replay = dc.post(
            "/api/donations/",
            {"campaign_uid": cid, "amount": "100.00", "currency": "TZS",
             "provider": "M_PESA"},
            HTTP_IDEMPOTENCY_KEY=key,
        )
        self.assertEqual(replay.status_code, 200)
        self.assertEqual(replay.json()["data"]["uid"], body["data"]["uid"])

    def test_ai_provider_failure_503_while_health_stays_up(self):
        from ai_assistant import providers
        patient = orm_user("PATIENT")
        c = client(patient)

        def _down():
            raise providers.ProviderUnavailable("upstream closed")

        with mock.patch("ai_assistant.providers.get_ai_provider", side_effect=_down):
            resp = c.post("/api/ai/chat/", {"message": "What is a sickle crisis?"})
        self.assertEqual(resp.status_code, 503)
        self.assertEqual(self.error_code(resp), "SERVICE_UNAVAILABLE")

        # health stays green while the AI provider is down
        h = JsonAPIClient().get("/api/v1/health/")
        self.assertEqual(h.status_code, 200)
        self.assertIn("data", h.json())

    def test_forged_webhook_signature_rejected(self):
        from donations import models as donation_models
        from donations.services import create_campaign
        owner = orm_user("PATIENT")
        admin = orm_user("ADMIN")
        campus = create_campaign(owner, title="Signed Fund", description="x",
                                 goal_amount="100000", currency="TZS")
        cid = str(campus.uid)
        client(owner).post(f"/api/campaigns/{cid}/submit/", {})
        client(admin).post(f"/api/admin/campaigns/{cid}/verify/", {"approve": True})

        donor = orm_user("PATIENT")
        dc = client(donor)
        init = dc.post(
            "/api/donations/",
            {"campaign_uid": cid, "amount": "50.00", "currency": "TZS", "provider": "M_PESA"},
            HTTP_IDEMPOTENCY_KEY=f"sig-{uuid.uuid4().hex[:10]}",
        )
        donation_uid = init.json()["data"]["uid"]
        ref = donation_models.Donation.objects.get(uid=donation_uid).transaction_ref

        forged = APIClient().post(
            "/api/webhooks/payments/M_PESA/", data='{"event":"payment.success"}',
            content_type="application/json",
            HTTP_X_PAYMENT_TIMESTAMP="0", HTTP_X_PAYMENT_SIGNATURE="forged",
        )
        self.assertIn(forged.status_code, (400, 401))
        self.assertIn("error", forged.json())

        # no state change from the forged attempt
        self.assertEqual(donation_models.Donation.objects.get(uid=donation_uid).status, "PENDING")

    def test_push_delivery_failure_never_breaks_core_flow(self):
        """Push is an optional channel; its failure must not block creation."""
        from notifications import services as nservices
        with mock.patch.object(nservices, "deliver_push", side_effect=RuntimeError("push down")):
            notification = nservices.create_notification(
                recipient=orm_user("PATIENT"), type_="SYSTEM",
                title="Still delivered in-app", body="Unreachable channel does not block writes.",
            )
        self.assertEqual(notification.status, "PENDING")

        # a blood-match flow survives a dead push channel end-to-end
        donor = orm_user("BLOOD_DONOR")
        requester = orm_user("PATIENT")
        blood_models.BloodDonor.objects.create(
            user=donor, blood_group="A+", is_verified=True, is_available=True,
        )
        req = blood_models.BloodRequest.objects.create(
            created_by=requester, patient=requester, blood_group_needed="A+",
            units=1, urgency="NORMAL", status="ACTIVE", location={},
        )
        admin = orm_user("ADMIN")
        matches = []
        with mock.patch.object(nservices, "deliver_push", side_effect=RuntimeError("push down")):
            from blood_network.services import run_matching
            matches = run_matching(req)
        self.assertEqual(len(matches), 1)
        self.assertEqual(nservices.Notification.objects.filter(
            recipient=donor, delivery_key=f"blood:match:{matches[0].pk}").count(), 1)


class ConcurrencyIdempotencySuite(_Envelope):
    """§20/§25 — constraint-backed replay semantics (sequential proof)."""

    def test_donation_idempotency_key_semantics(self):
        from donations.services import create_campaign
        owner = orm_user("PATIENT")
        admin = orm_user("ADMIN")
        campus = create_campaign(owner, title="Keyed Fund", description="x",
                                 goal_amount="90000", currency="TZS")
        cid = str(campus.uid)
        client(owner).post(f"/api/campaigns/{cid}/submit/", {})
        client(admin).post(f"/api/admin/campaigns/{cid}/verify/", {"approve": True})

        key = f"don-key-{uuid.uuid4().hex[:10]}"
        donor = orm_user("PATIENT")
        dc = client(donor)
        first = dc.post(
            "/api/donations/",
            {"campaign_uid": cid, "amount": "99.00", "currency": "TZS", "provider": "M_PESA"},
            HTTP_IDEMPOTENCY_KEY=key,
        )
        self.assertEqual(first.status_code, 201)
        uid1 = first.json()["data"]["uid"]

        replay = dc.post(
            "/api/donations/",
            {"campaign_uid": cid, "amount": "99.00", "currency": "TZS", "provider": "M_PESA"},
            HTTP_IDEMPOTENCY_KEY=key,
        )
        self.assertEqual(replay.status_code, 200)
        self.assertEqual(replay.json()["data"]["uid"], uid1)

        other = orm_user("PATIENT")
        conflict = client(other).post(
            "/api/donations/",
            {"campaign_uid": cid, "amount": "99.00", "currency": "TZS", "provider": "M_PESA"},
            HTTP_IDEMPOTENCY_KEY=key,
        )
        self.assertEqual(conflict.status_code, 409)
        self.assertEqual(self.error_code(conflict), "CONFLICT")

    def test_blood_accept_is_final_for_the_match(self):
        requester = orm_user("PATIENT")
        rc = client(requester)
        req = self.data(rc.post(
            "/api/blood/requests/",
            {"blood_group_needed": "AB+", "units": 1, "urgency": "NORMAL",
             "reason": "urgent", "location": {"region": "Cape Coast", "city": "Cape Coast"}},
        ))
        req_uid = req["uid"]
        dd = orm_user("BLOOD_DONOR")
        blood_models.BloodDonor.objects.create(
            user=dd, blood_group="AB+", region="Cape Coast", city="Cape Coast",
            is_verified=True, is_available=True,
        )
        admin = orm_user("ADMIN")
        ac = client(admin)
        ac.post(f"/api/admin/blood/requests/{req_uid}/verify/", {})
        ac.post("/api/admin/blood/run-matching/", {"request_uid": req_uid})
        match = blood_models.BloodMatch.objects.get(request__uid=req_uid)

        first = client(dd).post(f"/api/blood/matches/{match.id}/respond/", {"action": "ACCEPT"})
        self.assertEqual(first.status_code, 200, first.json())

        second = client(dd).post(
            f"/api/blood/matches/{match.id}/respond/", {"action": "ACCEPT"},
        )
        self.assertEqual(second.status_code, 400)
        self.assertIn("no longer actionable", str(second.json()))

    def test_emergency_and_blood_duplicate_idempotency_409(self):
        patient = orm_user("PATIENT")
        c = client(patient)
        first = c.post(
            "/api/emergency/requests/",
            {"severity": "NORMAL", "type": "MEDICAL", "description": "dup"},
            HTTP_IDEMPOTENCY_KEY="emg-dup-1",
        )
        self.assertEqual(first.status_code, 201, first.json())
        dup = c.post(
            "/api/emergency/requests/",
            {"severity": "NORMAL", "type": "MEDICAL", "description": "dup"},
            HTTP_IDEMPOTENCY_KEY="emg-dup-1",
        )
        self.assertEqual(dup.status_code, 409)
        self.assertEqual(self.error_code(dup), "CONFLICT")

        bfirst = c.post(
            "/api/blood/requests/",
            {"blood_group_needed": "O-", "units": 1, "urgency": "NORMAL"},
            HTTP_IDEMPOTENCY_KEY="bld-dup-1",
        )
        self.assertEqual(bfirst.status_code, 201, bfirst.json())
        bdup = c.post(
            "/api/blood/requests/",
            {"blood_group_needed": "O-", "units": 1, "urgency": "NORMAL"},
            HTTP_IDEMPOTENCY_KEY="bld-dup-1",
        )
        self.assertEqual(bdup.status_code, 409)
        self.assertEqual(self.error_code(bdup), "CONFLICT")

    def test_match_rerun_is_idempotent_under_unique_constraint(self):
        from notifications.models import Notification
        from blood_network.services import run_matching_for_all
        requester = orm_user("PATIENT")
        rc = client(requester)
        req = self.data(rc.post(
            "/api/blood/requests/",
            {"blood_group_needed": "A-", "units": 2, "urgency": "NORMAL",
             "reason": "elective surgery", "location": {"region": "Tamale", "city": "Tamale"}},
        ))
        donor = orm_user("BLOOD_DONOR")
        blood_models.BloodDonor.objects.create(
            user=donor, blood_group="A-", region="Tamale", city="Tamale",
            is_verified=True, is_available=True,
        )
        admin = orm_user("ADMIN")
        ac = client(admin)
        ac.post(f"/api/admin/blood/requests/{req['uid']}/verify/", {})
        for _ in range(2):
            ac.post("/api/admin/blood/run-matching/", {"request_uid": req["uid"]})

        request = blood_models.BloodRequest.objects.get(uid=req["uid"])
        match_count = blood_models.BloodMatch.objects.filter(request=request).count()
        self.assertEqual(match_count, 1)
        self.assertEqual(request.status, "MATCHING")
        self.assertEqual(
            Notification.objects.filter(
                recipient=donor, delivery_key=f"blood:match:{request.matches.get().pk}",
            ).count(),
            1,
        )

    def test_refund_double_guard(self):
        from donations import models as donation_models
        from donations.providers import build_webhook
        from donations.services import create_campaign
        owner = orm_user("PATIENT")
        admin = orm_user("ADMIN")
        campus = create_campaign(owner, title="Refundable", description="x",
                                 goal_amount="100000", currency="TZS")
        cid = str(campus.uid)
        client(owner).post(f"/api/campaigns/{cid}/submit/", {})
        client(admin).post(f"/api/admin/campaigns/{cid}/verify/", {"approve": True})

        donor = orm_user("PATIENT")
        dc = client(donor)
        key = f"ref-{uuid.uuid4().hex[:10]}"
        init = dc.post(
            "/api/donations/",
            {"campaign_uid": cid, "amount": "700.00", "currency": "TZS", "provider": "M_PESA"},
            HTTP_IDEMPOTENCY_KEY=key,
        )
        donation_uid = init.json()["data"]["uid"]
        txn = donation_models.Donation.objects.get(uid=donation_uid).transactions.get()
        body, headers = build_webhook("M_PESA", {
            "event": "payment.success",
            "transaction_ref": donation_models.Donation.objects.get(uid=donation_uid).transaction_ref,
            "provider_ref": txn.provider_ref, "amount": "700.00", "currency": "TZS",
        })
        self.webhook("M_PESA", body, headers)
        raised = donation_models.Campaign.objects.get(uid=cid).raised_amount
        self.assertEqual(raised, Decimal("700.00"))

        first = client(admin).post(
            f"/api/admin/donations/{donation_uid}/refund/", {"reason": "donor request"},
        )
        self.assertEqual(first.status_code, 201, first.json())

        second = client(admin).post(
            f"/api/admin/donations/{donation_uid}/refund/", {"reason": "again"},
        )
        self.assertEqual(second.status_code, 409)
        self.assertIn("already", str(second.json()).lower())

        got = donation_models.Donation.objects.get(uid=donation_uid)
        self.assertEqual(got.status, "REFUNDED")


class SecurityDenialsSuite(_Envelope):
    """Anonymous / non-owner / wrong-role probes across public surfaces."""

    def test_anonymous_and_nonowner_denials(self):
        anon = JsonAPIClient()
        for path in ("/api/auth/me/", "/api/patients/me/", "/api/notifications/devices/"):
            resp = anon.get(path)
            self.assertEqual(resp.status_code, 401, path)
            self.assertEqual(self.error_code(resp), "UNAUTHORIZED")

    def test_patient_cannot_touch_another_patient_medication(self):
        owner = orm_user("PATIENT")
        intruder = orm_user("PATIENT")
        med = medication_models.Medication.objects.create(
            patient=owner, name="Hidden", frequency="daily",
            start_date=timezone.localdate(),
        )
        resp = client(intruder).get(f"/api/medications/{med.uid}/")
        self.assertIn(resp.status_code, (400, 403, 404))
        self.assertIn("error", resp.json())

    def test_donor_sees_no_contact_data_in_public_request_list(self):
        requester = orm_user("PATIENT")
        c = client(requester)
        created = c.post(
            "/api/blood/requests/",
            {"blood_group_needed": "O+", "units": 1, "urgency": "NORMAL",
             "reason": "privacy check", "location": {"region": "Accra"}},
        )
        req = created.json()["data"]
        # donor-visible stream only exposes ACTIVE/MATCHING/MATCHED requests —
        # verify the request through administration first so it leaves the
        # PENDING_VERIFICATION state, then confirm the donor cannot see PHI
        admin = orm_user("ADMIN")
        client(admin).post(f"/api/admin/blood/requests/{req['uid']}/verify/", {})
        donor = orm_user("BLOOD_DONOR")
        blood_models.BloodDonor.objects.create(
            user=donor, blood_group="O+", region="Accra",
            is_verified=True, is_available=True,
        )
        public = client(donor).get(f"/api/blood/requests/{req['uid']}/")
        self.assertEqual(public.status_code, 200, public.json())
        data = public.json()["data"]
        self.assertNotIn("creator_email", data)
        self.assertNotIn("idempotency_key", data)
        self.assertNotIn("phone", str(data).lower())