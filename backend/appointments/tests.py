"""Tests for the clinic appointment API (§11).

Run::

    venv/bin/python manage.py test appointments --settings=config.settings.ephemeral_test

Covers: booking (self and consented proxy), relationship scoping (a patient can
never read another patient's appointments), reminder-settings validation,
patient vs clinic status authority, soft cancel retaining history, and the
reminder-obligation projection.
"""

import uuid as _uuid

from django.test import TestCase
from django.utils import timezone
from rest_framework.test import APIClient
from rest_framework_simplejwt.tokens import RefreshToken

from accounts.models import Role, User, UserRole
from appointments.models import ClinicAppointment
from facilities.models import Facility
from patients.models import Patient

_PASSWORD = "Str0ng!Pass9"


def _orm_user(role_code, email=None):
    user = User.objects.create_user(
        email=email or f"{role_code.lower()}-{_uuid.uuid4().hex[:10]}@example.com",
        password=_PASSWORD,
        first_name="Test",
        last_name=role_code.title(),
        account_status="ACTIVE",
    )
    UserRole.objects.create(user=user, role=Role.objects.get(code=role_code))
    return user


def _client(user):
    client = APIClient()
    client.credentials(HTTP_AUTHORIZATION=f"Bearer {RefreshToken.for_user(user).access_token}")
    return client


def _patient_profile(user):
    return Patient.objects.create(user=user, date_of_birth="2000-01-01")


def _facility():
    return Facility.objects.create(
        name="Muhimbili Sickle Cell Centre",
        facility_type="HOSPITAL",
        region="Dar es Salaam",
        city="Dar es Salaam",
        is_verified=True,
    )


def _errors(payload):
    """Unwrap the standard error envelope so assertions read the details."""
    if isinstance(payload, dict) and "error" in payload:
        return payload["error"].get("details", {})
    return payload


def _book(client, facility, **overrides):
    payload = {
        "facility_uid": facility.uid.hex,
        "appointment_type": "FOLLOW_UP",
        "scheduled_at": (timezone.now() + timezone.timedelta(days=7)).isoformat(),
        "duration_minutes": 30,
        "reason": "Routine pain review",
        "reminder_enabled": True,
        "reminder_days_before": [1],
        "reminder_times": ["07:00", "19:00"],
        "reminder_channels": ["in_app", "push"],
    }
    payload.update(overrides)
    return client.post("/api/appointments/", data=payload, format="json")


class AppointmentBookingTests(TestCase):
    def setUp(self):
        self.patient = _orm_user("PATIENT")
        _patient_profile(self.patient)
        self.facility = _facility()
        self.client_for_patient = _client(self.patient)

    def test_patient_books_appointment(self):
        response = _book(self.client_for_patient, self.facility)
        self.assertEqual(response.status_code, 201, response.data)
        row = ClinicAppointment.objects.get(uid=response.data["uid"])
        self.assertEqual(row.patient, self.patient)
        self.assertEqual(row.created_by, self.patient)
        self.assertEqual(row.status, "REQUESTED")
        self.assertEqual(row.facility, self.facility)
        # Facility projection feeds the clinic card without a second lookup.
        self.assertEqual(response.data["facility_name"], self.facility.name)

    def test_patient_cannot_choose_a_past_slot(self):
        past = (timezone.now() - timezone.timedelta(days=1)).isoformat()
        response = _book(self.client_for_patient, self.facility, scheduled_at=past)
        self.assertEqual(response.status_code, 400)
        self.assertIn("scheduled_at", _errors(response.data))

    def test_reminders_require_a_time_and_lead_time(self):
        response = _book(self.client_for_patient, self.facility, reminder_times=[])
        self.assertEqual(response.status_code, 400)
        self.assertIn("reminder_times", _errors(response.data))

    def test_invalid_reminder_time_is_rejected_with_a_friendly_message(self):
        response = _book(self.client_for_patient, self.facility, reminder_times=["25:99"])
        self.assertEqual(response.status_code, 400)
        self.assertIn("reminder_times", _errors(response.data))

    def test_reminders_can_be_turned_off(self):
        response = _book(
            self.client_for_patient, self.facility, reminder_enabled=False, reminder_times=[]
        )
        self.assertEqual(response.status_code, 201, response.data)
        self.assertFalse(response.data["reminder_enabled"])

    def test_follow_up_requires_a_due_date(self):
        response = _book(self.client_for_patient, self.facility, follow_up_required=True)
        self.assertEqual(response.status_code, 400)
        self.assertIn("follow_up_due_on", _errors(response.data))

    def test_past_appointment_note_is_not_exposed_to_the_patient(self):
        created = _book(self.client_for_patient, self.facility)
        uid = created.data["uid"]
        ClinicAppointment.objects.filter(uid=uid).update(notes="HbF 12%, hydroxyurea adjusted")
        response = self.client_for_patient.get(f"/api/appointments/{uid}/")
        self.assertEqual(response.status_code, 200)
        self.assertNotIn("notes", response.data)

    def test_versioned_prefix_is_an_alias(self):
        created = _book(self.client_for_patient, self.facility)
        uid = created.data["uid"]
        legacy = self.client_for_patient.get(f"/api/appointments/{uid}/")
        versioned = self.client_for_patient.get(f"/api/v1/appointments/{uid}/")
        self.assertEqual(legacy.status_code, versioned.status_code)
        self.assertEqual(legacy.data["uid"], versioned.data["uid"])


class AppointmentRelationshipTests(TestCase):
    def setUp(self):
        self.patient = _orm_user("PATIENT")
        _patient_profile(self.patient)
        self.other_patient = _orm_user("PATIENT")
        _patient_profile(self.other_patient)
        self.caregiver = _orm_user("CAREGIVER")
        self.facility = _facility()

    def test_patient_cannot_read_another_patients_appointments(self):
        other_client = _client(self.other_patient)
        created = _book(other_client, self.facility)
        self.assertEqual(created.status_code, 201)
        mine = _client(self.patient).get("/api/appointments/")
        self.assertEqual(mine.data["count"], 0)
        detail = _client(self.patient).get(f"/api/appointments/{created.data['uid']}/")
        self.assertEqual(detail.status_code, 404)

    def test_caregiver_without_consent_cannot_see_appointments(self):
        _book(_client(self.patient), self.facility)
        response = _client(self.caregiver).get("/api/appointments/")
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.data["count"], 0)

    def test_caregiver_with_consent_sees_and_books_for_patient(self):
        from medical_records.services import grant

        patient_profile = Patient.objects.get(user=self.patient)
        grant(
            patient=patient_profile,
            granted_to=self.caregiver,
            permission_scope=["appointments.read", "appointments.write_own"],
            resource_type="appointments",
            expires_at=timezone.now() + timezone.timedelta(days=30),
        )
        caregiver_client = _client(self.caregiver)
        listing = caregiver_client.get("/api/appointments/")
        self.assertEqual(listing.data["count"], 0)
        booked = _book(caregiver_client, self.facility, patient=self.patient.uid.hex)
        self.assertEqual(booked.status_code, 201, booked.data)
        row = ClinicAppointment.objects.get(uid=booked.data["uid"])
        self.assertEqual(row.patient, self.patient)
        self.assertEqual(row.created_by, self.caregiver)
        listing = caregiver_client.get("/api/appointments/")
        self.assertEqual(listing.data["count"], 1)

    def test_caregiver_cannot_spoof_a_patient_without_consent(self):
        response = _book(
            _client(self.caregiver), self.facility, patient=self.other_patient.uid.hex
        )
        self.assertEqual(response.status_code, 403)


class AppointmentLifecycleTests(TestCase):
    def setUp(self):
        self.patient = _orm_user("PATIENT")
        _patient_profile(self.patient)
        self.admin = _orm_user("ADMIN")
        self.facility = _facility()
        self.client_for_patient = _client(self.patient)
        self.uid = _book(self.client_for_patient, self.facility).data["uid"]

    def test_patient_cancels_with_a_reason_and_history_is_retained(self):
        response = self.client_for_patient.post(
            f"/api/appointments/{self.uid}/status/",
            data={"status": "CANCELLED", "reason": "Transport fell through"},
            format="json",
        )
        self.assertEqual(response.status_code, 200, response.data)
        self.assertEqual(response.data["status"], "CANCELLED")
        # Soft delete: the row survives as history.
        self.assertTrue(ClinicAppointment.objects.filter(uid=self.uid).exists())

    def test_cancelling_without_a_reason_is_refused(self):
        response = self.client_for_patient.post(
            f"/api/appointments/{self.uid}/status/", data={"status": "CANCELLED"}, format="json"
        )
        self.assertEqual(response.status_code, 400)
        self.assertIn("reason", _errors(response.data))

    def test_patient_cannot_complete_their_own_appointment(self):
        response = self.client_for_patient.post(
            f"/api/appointments/{self.uid}/status/", data={"status": "COMPLETED"}, format="json"
        )
        self.assertEqual(response.status_code, 400)

    def test_clinic_completes_and_sees_clinical_notes(self):
        admin_client = _client(self.admin)
        ClinicAppointment.objects.filter(uid=self.uid).update(notes="HbF 12%, dose adjusted")
        response = admin_client.post(
            f"/api/appointments/{self.uid}/status/", data={"status": "COMPLETED"}, format="json"
        )
        self.assertEqual(response.status_code, 200, response.data)
        self.assertEqual(response.data["status"], "COMPLETED")
        self.assertEqual(response.data["notes"], "HbF 12%, dose adjusted")
        detail = admin_client.get(f"/api/appointments/{self.uid}/")
        self.assertEqual(detail.status_code, 200)
        self.assertEqual(detail.data["uid"], self.uid)

    def test_reschedule_moves_the_slot_and_flags_rescheduled(self):
        new_slot = (timezone.now() + timezone.timedelta(days=12)).isoformat()
        response = self.client_for_patient.patch(
            f"/api/appointments/{self.uid}/", data={"scheduled_at": new_slot}, format="json"
        )
        self.assertEqual(response.status_code, 200, response.data)
        row = ClinicAppointment.objects.get(uid=self.uid)
        self.assertEqual(row.status, "RESCHEDULED")
        self.assertEqual(row.scheduled_at.isoformat(), new_slot)

    def test_delete_soft_cancels(self):
        response = self.client_for_patient.delete(f"/api/appointments/{self.uid}/")
        self.assertEqual(response.status_code, 200)
        self.assertEqual(ClinicAppointment.objects.get(uid=self.uid).status, "CANCELLED")

    def test_status_cannot_be_patched_directly(self):
        response = self.client_for_patient.patch(
            f"/api/appointments/{self.uid}/", data={"status": "COMPLETED"}, format="json"
        )
        self.assertEqual(response.status_code, 400)
        self.assertIn("status", _errors(response.data))


class AppointmentReminderObligationTests(TestCase):
    def setUp(self):
        self.patient = _orm_user("PATIENT")
        _patient_profile(self.patient)
        self.admin = _orm_user("ADMIN")
        self.facility = _facility()

    def _tomorrow_at(self, hour, reminder_times=("07:00", "19:00")):
        target = (timezone.now() + timezone.timedelta(days=1)).replace(
            hour=hour, minute=0, second=0, microsecond=0
        )
        return ClinicAppointment.objects.create(
            patient=self.patient,
            created_by=self.patient,
            facility=self.facility,
            scheduled_at=target,
            appointment_type="FOLLOW_UP",
            reminder_enabled=True,
            reminder_days_before=[1],
            reminder_times=list(reminder_times),
            reminder_channels=["in_app", "push"],
        )

    def _today_at(self, hour, minute=0):
        """A wall-clock instant on *today*, for use as the dispatcher's `now`.

        Every case below passes this to `reminder_due(at=...)` instead of reading
        the real clock. A reminder is only owed when its time-of-day has already
        passed, so a test that asserted against the machine's current hour passed
        in the afternoon and failed at 05:00 — the same defect as a hard-coded
        "00:01" slot, just with a different number attached.
        """
        return timezone.now().replace(
            hour=hour, minute=minute, second=0, microsecond=0
        )

    def test_reminder_is_due_on_the_lead_day_once_the_slot_has_passed(self):
        # Lead day is today; at 12:00 the 07:00 slot has passed and is still
        # inside the 12-hour freshness window, so it is owed.
        appointment = self._tomorrow_at(10)
        due = appointment.reminder_due(self._today_at(12))
        self.assertEqual([slot.hour for slot in due], [7])

    def test_a_slot_that_has_not_reached_its_time_is_not_due_yet(self):
        # At 22:00 the 23:00 slot has not arrived, so nothing is owed.
        appointment = self._tomorrow_at(23, reminder_times=["23:00"])
        self.assertEqual(appointment.reminder_due(self._today_at(22)), [])

    def test_a_slot_older_than_the_freshness_window_is_not_due(self):
        """A single 07:00 slot is not fired at 06:00 (too early) or 20:00 (stale).

        The 12-hour window is what stops a missed reminder from firing hours
        later, so both edges are asserted rather than only the happy path.
        """
        appointment = self._tomorrow_at(10, reminder_times=["07:00"])
        self.assertEqual(appointment.reminder_due(self._today_at(6)), [])
        self.assertEqual(
            [slot.hour for slot in appointment.reminder_due(self._today_at(8))], [7],
        )
        self.assertEqual(appointment.reminder_due(self._today_at(20)), [])

    def test_nothing_is_due_before_the_lead_day(self):
        appointment = self._tomorrow_at(10)
        too_early = (timezone.now() - timezone.timedelta(days=3)).replace(
            hour=9, minute=0, second=0, microsecond=0
        )
        self.assertEqual(appointment.reminder_due(too_early), [])

    def test_a_reminder_is_not_sent_twice_in_one_day(self):
        appointment = self._tomorrow_at(10)
        # Same lead day, later than the 07:00 slot: already sent today, so the
        # dispatcher must not send it twice.
        lead_day_nine = timezone.now().replace(hour=9, minute=0, second=0, microsecond=0)
        appointment.reminders_sent = 1
        appointment.last_reminder_sent_at = lead_day_nine
        appointment.save(update_fields=["reminders_sent", "last_reminder_sent_at"])
        self.assertEqual(appointment.reminder_due(lead_day_nine), [])

    def test_cancelled_appointments_owe_no_reminders(self):
        appointment = self._tomorrow_at(10)
        appointment.status = "CANCELLED"
        appointment.save(update_fields=["status"])
        self.assertEqual(appointment.reminder_due(), [])

    def test_staff_projection_lists_pending_obligations(self):
        """The staff view lists exactly what the dispatcher would send now.

        The slot is derived from the current clock rather than hard-coded: a
        reminder is only owed when its time-of-day has passed *and* is still
        inside the 12-hour freshness window, so a fixed "00:01" would make this
        test pass at 01:00 and fail at 13:00.
        """
        now = timezone.now()
        target = (now + timezone.timedelta(days=1)).replace(
            hour=23, minute=0, second=0, microsecond=0
        )
        slot = max(now - timezone.timedelta(hours=1), now.replace(
            hour=0, minute=0, second=0, microsecond=0
        ))
        ClinicAppointment.objects.create(
            patient=self.patient,
            created_by=self.patient,
            facility=self.facility,
            scheduled_at=target,
            reminder_enabled=True,
            reminder_days_before=[1],
            reminder_times=[slot.strftime("%H:%M")],
            reminder_channels=["in_app"],
        )
        response = _client(self.admin).get("/api/appointments/reminders/due")
        self.assertEqual(response.status_code, 200, response.data)
        self.assertGreaterEqual(response.data["count"], 1)

    def test_reminder_projection_requires_manage_permission(self):
        response = _client(self.patient).get("/api/appointments/reminders/due")
        self.assertEqual(response.status_code, 403)

class AppointmentReminderDispatchTests(TestCase):
    """The dispatcher is the documented home for appointment reminders."""

    def setUp(self):
        self.patient = _orm_user("PATIENT")
        _patient_profile(self.patient)
        self.facility = _facility()

    def _tomorrow_morning(self, reminder_times=("07:00",), days_before=(1,)):
        target = (timezone.now() + timezone.timedelta(days=1)).replace(
            hour=10, minute=0, second=0, microsecond=0
        )
        return ClinicAppointment.objects.create(
            patient=self.patient,
            created_by=self.patient,
            facility=self.facility,
            scheduled_at=target,
            reminder_enabled=True,
            reminder_days_before=list(days_before),
            reminder_times=list(reminder_times),
            reminder_channels=["in_app", "push"],
        )

    @staticmethod
    def _dispatch_now():
        """A deterministic 'now' inside the dispatcher's freshness window.

        The 07:00 slot is due only while it is within 12 hours after it
        passes, so pinning the clock (instead of reading the wall clock)
        keeps these tests green at any hour of the day.
        """
        return timezone.now().replace(hour=7, minute=30, second=0, microsecond=0)

    def test_due_reminder_becomes_an_inbox_notification(self):
        from notifications.models import Notification

        appointment = self._tomorrow_morning()
        from notifications.reminders import dispatch_appointment_reminders

        created = dispatch_appointment_reminders(now=self._dispatch_now())
        self.assertGreaterEqual(created, 1)
        note = Notification.objects.filter(recipient=self.patient).latest("created_at")
        self.assertEqual(note.type, "APPOINTMENT")
        self.assertEqual(note.related_resource_id, str(appointment.uid))
        # De-identified body: venue + time only, never the reason/clinical note.
        self.assertIn(self.facility.name, note.body)
        self.assertNotIn("pain", note.body.lower())

    def test_reruns_do_not_duplicate(self):
        from notifications.reminders import dispatch_appointment_reminders

        self._tomorrow_morning()
        now = self._dispatch_now()
        first = dispatch_appointment_reminders(now=now)
        second = dispatch_appointment_reminders(now=now)
        self.assertGreaterEqual(first, 1)
        self.assertEqual(second, 0)

    def test_dispatcher_runs_every_producer(self):
        from notifications.reminders import dispatch_all_reminders

        self._tomorrow_morning()
        result = dispatch_all_reminders()
        self.assertIn("medication", result)
        self.assertIn("appointment", result)
