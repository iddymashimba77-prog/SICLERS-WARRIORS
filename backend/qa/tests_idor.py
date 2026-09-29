"""P0 IDOR matrix — cross-user resource access must collapse.

Stage 4.19 / §6, §7. Builds a second warm user and proves, for every
user-owned resource family below, that the foreign actor cannot read or
mutate it. Where a surface is owner-filtered, assert either an empty
result list (list shape) or 403/404 (detail shape).
"""

import uuid as _uuid
from decimal import Decimal

from django.core.cache import cache
from django.test import TestCase
from django.utils import timezone

from blood_network.models import BloodDonor, BloodRequest
from donations.models import Campaign, Donation, PaymentTransaction
from emergencies.models import EmergencyAccessGrant, EmergencyRequest
from medications.models import Medication, MedicationSchedule
from notifications.models import Notification
from patients.models import Patient

from . import qa_helpers as h
from .tests_emergency_surface import _sos


class _Base(TestCase):
    def setUp(self):
        cache.clear()
        self.patient = h.orm_user("PATIENT")
        self.other = h.orm_user("PATIENT")
        self.a = h.client(self.patient)
        self.b = h.client(self.other)

        self.profile = Patient.objects.create(
            user=self.patient, genotype="SS", date_of_birth="1995-01-01",
        )
        self.notif = Notification.objects.create(
            recipient=self.patient, type="SYSTEM", channel="IN_APP",
            title="Sickle cell awareness", body="Private notification",
        )
        self.med = Medication.objects.create(
            patient=self.patient, name="Hydroxyurea", dosage="500mg daily",
            start_date=timezone.now().date(),
        )
        self.schedule = MedicationSchedule.objects.create(
            medication=self.med, time_of_day=timezone.now().time(),
            days_of_week=["MON", "WED", "FRI"],
        )
        # Emergency + auto C10 grant scoped to the patient.
        _sos(self.a)
        self.request = EmergencyRequest.objects.get(requester=self.patient)
        self.grant = EmergencyAccessGrant.objects.get(patient=self.patient)
        # Donation + payment.
        org = h.orm_user("ORGANIZATION")
        self.campaign = Campaign.objects.create(
            owner=org, title="QA Fund", goal_amount=Decimal("9999999.00"),
            status="ACTIVE",
        )
        self.donation = Donation.objects.create(
            campaign=self.campaign, donor=self.patient, amount=Decimal("20000.00"),
            status="COMPLETED", idempotency_key=_uuid.uuid4().hex,
            transaction_ref=_uuid.uuid4().hex[:32],
        )
        self.txn = PaymentTransaction.objects.create(
            donation=self.donation, provider="M_PESA",
            provider_ref=f"SANDBOX-{_uuid.uuid4().hex[:12].upper()}",
            status="SUCCESS", amount=Decimal("20000.00"), attempt=1,
        )
        self.donor_profile = BloodDonor.objects.create(
            user=self.patient, blood_group="O+", region="Greater Accra", city="Accra",
        )
        self.blood_req = BloodRequest.objects.create(
            created_by=self.patient, patient=self.patient, blood_group_needed="O+",
            units=2, urgency="URGENT", location={"city": "Accra"}, reason="QA bloodstream",
        )


class CrossPatientMedicationIdorTests(_Base):
    def test_list_is_owner_scoped(self):
        mine = self.a.get("/api/medications/")
        foreign = self.b.get("/api/medications/")
        self.assertEqual(mine.status_code, 200)
        self.assertEqual(foreign.status_code, 200)
        self.assertEqual(foreign.data["count"], 0)

    def test_detail_denied_for_foreign_actor(self):
        self.assertIn(self.b.get(f"/api/medications/{self.med.uid}/").status_code, (403, 404))

    def test_schedule_of_foreign_medication_denied(self):
        path = f"/api/medications/{self.med.uid}/schedule/{self.schedule.uid}/"
        self.assertIn(self.b.delete(path).status_code, (403, 404))

    def test_cannot_soft_delete_foreign_medication(self):
        resp = self.b.delete(f"/api/medications/{self.med.uid}/")
        self.assertIn(resp.status_code, (403, 404))


class PublicDonorDirectorySanityTests(TestCase):
    def setUp(self):
        self.donor_target = h.orm_user("BLOOD_DONOR")
        BloodDonor.objects.create(
            user=self.donor_target, blood_group="O+", region="Greater Accra",
            city="Accra", is_verified=True,
        )
        # The directory is STA/ADM-internal (blood_donors.view), never public.
        self.admin = h.orm_user("ADMIN")
        self.admin_client = h.client(self.admin)

    def test_directory_rows_never_expose_contact_pii(self):
        rows = self.admin_client.get("/api/blood/donors/").data["results"]
        self.assertTrue(rows)
        for row in rows:
            self.assertNotIn("email", row)
            self.assertNotIn("user", row)
            self.assertNotIn("phone", row)

    def test_verified_only_directory(self):
        # Unverified profiles are excluded from the finder entirely.
        unverified = h.orm_user("BLOOD_DONOR")
        BloodDonor.objects.create(user=unverified, blood_group="B+")
        uids = [r["id"] for r in self.admin_client.get("/api/blood/donors/").data["results"]]
        self.assertNotIn(unverified.blood_donor_profile.id, uids)

    def test_directory_is_internal_not_donor_facing(self):
        # C8/C9 keep the donor busy; the directory is an ops surface.
        donor_observer = h.orm_user("BLOOD_DONOR")
        BloodDonor.objects.create(user=donor_observer, blood_group="A+")
        self.assertEqual(h.client(donor_observer).get("/api/blood/donors/").status_code, 403)

    def test_patient_cannot_access_donor_self_surface(self):
        patient = h.orm_user("PATIENT")
        # 'me' must never fall through to a foreign/other profile, and the
        # code gate denies non-donor roles outright.
        self.assertEqual(h.client(patient).get("/api/blood/donors/me/").status_code, 403)


class CrossPatientBloodRequestIdorTests(_Base):
    def test_blood_request_foreign_detail_denied(self):
        self.assertIn(self.b.get(f"/api/blood/requests/{self.blood_req.uid}/").status_code,
                      (403, 404))

    def test_blood_request_detail_owner_ok(self):
        self.assertEqual(self.a.get(f"/api/blood/requests/{self.blood_req.uid}/").status_code, 200)


class CrossPatientDonationIdorTests(_Base):
    def test_donation_detail_foreign_denied(self):
        self.assertIn(self.b.get(f"/api/donations/{self.donation.uid}/").status_code, (403, 404))

    def test_receipt_foreign_denied(self):
        self.assertIn(self.b.get(f"/api/donations/{self.donation.uid}/receipt/").status_code,
                      (403, 404))

    def test_payment_detail_foreign_denied(self):
        self.assertIn(self.b.get(f"/api/payments/{self.txn.id}/").status_code, (403, 404))

    def test_donation_history_is_owner_scoped(self):
        self.assertEqual(self.b.get("/api/donations/").data["count"], 0)


class CrossPatientEmergencyIdorTests(_Base):
    def test_access_grant_foreign_detail_denied(self):
        self.assertIn(self.b.get(f"/api/emergency/access-grants/{self.grant.uid}/").status_code,
                      (403, 404))

    def test_access_grant_non_participant_scope(self):
        uids = [g["uid"] for g in self.b.get("/api/emergency/access-grants/").data["results"]]
        self.assertEqual(uids, [])


class CrossPatientNotificationIdorTests(_Base):
    def test_notification_list_is_owner_scoped(self):
        mine = self.a.get("/api/notifications/")
        self.assertIn(self.notif.id, [n["id"] for n in mine.data["results"]])
        foreign = self.b.get("/api/notifications/")
        self.assertNotIn(self.notif.id, [n["id"] for n in foreign.data["results"]])

    def test_notification_mark_foreign_read_denied(self):
        resp = self.b.post(f"/api/notifications/{self.notif.id}/read/")
        self.assertIn(resp.status_code, (403, 404))