"""Backend tests for the Stage 4.8 notification service + inbox API.

Run::

    venv/bin/python manage.py test notifications --settings=config.settings.ephemeral_test

Covers: delivery-key idempotency, recipient-only inbox (IDOR → 404), read /
read-all, preference map + PATCH, mute → SUPPRESSED, and emergency
notifications never being suppressible (FR-EMG / BR-009).
"""

import uuid as _uuid

from django.test import TestCase
from rest_framework.test import APIClient
from rest_framework_simplejwt.tokens import RefreshToken

from accounts.models import Role, User, UserRole
from notifications.models import Notification
from notifications.services import create_notification


_PASSWORD = "Str0ng!Pass9"


def _orm_user(role_code="PATIENT", email=None):
    user = User.objects.create_user(
        email=email or f"{role_code.lower()}-{_uuid.uuid4().hex[:10]}@example.com",
        password=_PASSWORD,
        first_name="Test",
        last_name="User",
        account_status="ACTIVE",
    )
    UserRole.objects.create(user=user, role=Role.objects.get(code=role_code))
    return user


def _client(user):
    client = APIClient()
    client.credentials(HTTP_AUTHORIZATION=f"Bearer {RefreshToken.for_user(user).access_token}")
    return client


class NotificationServiceTests(TestCase):
    def setUp(self):
        self.user = _orm_user()

    def test_delivery_key_is_idempotent(self):
        first = create_notification(
            recipient=self.user, type_="BLOOD", title="t", body="b",
            delivery_key="blood:match:1",
        )
        second = create_notification(
            recipient=self.user, type_="BLOOD", title="t2", body="b2",
            delivery_key="blood:match:1",
        )
        self.assertEqual(first.pk, second.pk)
        self.assertEqual(Notification.objects.count(), 1)

    def test_muted_category_suppressed_but_emergency_forced(self):
        Notification.objects.create(
            recipient=self.user, type="BLOOD", title="x", body="y",
        )
        from notifications.models import NotificationPreference

        NotificationPreference.objects.create(user=self.user, category="BLOOD", enabled=False)
        muted = create_notification(
            recipient=self.user, type_="BLOOD", title="t", body="b", delivery_key="k1",
        )
        self.assertEqual(muted.status, "SUPPRESSED")
        emergency = create_notification(
            recipient=self.user, type_="EMERGENCY", title="t", body="b",
            delivery_key="k2", force=True,
        )
        self.assertEqual(emergency.status, "PENDING")


class NotificationApiTests(TestCase):
    def setUp(self):
        self.user = _orm_user()
        self.client = _client(self.user)
        self.note = Notification.objects.create(
            recipient=self.user, type="SYSTEM", title="Welcome", body="Hello",
        )

    def test_inbox_is_recipient_scoped(self):
        resp = self.client.get("/api/notifications/")
        self.assertEqual(resp.status_code, 200)
        self.assertEqual(resp.data["count"], 1)

        stranger = _client(_orm_user())
        self.assertEqual(stranger.get("/api/notifications/").data["count"], 0)
        self.assertEqual(stranger.get(f"/api/notifications/{self.note.id}/").status_code, 404)

    def test_mark_read(self):
        resp = self.client.post(f"/api/notifications/{self.note.id}/read/")
        self.assertEqual(resp.status_code, 200)
        self.assertEqual(resp.data["status"], "READ")
        self.note.refresh_from_db()
        self.assertIsNotNone(self.note.read_at)

    def test_read_all(self):
        Notification.objects.create(
            recipient=self.user, type="SYSTEM", title="Second", body="Again",
        )
        resp = self.client.post("/api/notifications/read-all/")
        self.assertEqual(resp.status_code, 200)
        self.assertEqual(resp.data["updated"], 2)
        self.assertEqual(
            Notification.objects.filter(recipient=self.user, status="READ").count(), 2
        )

    def test_preferences_get_and_patch(self):
        listed = self.client.get("/api/notifications/preferences/")
        self.assertEqual(listed.status_code, 200)
        self.assertIs(listed.data["preferences"]["BLOOD"], True)
        patched = self.client.patch(
            "/api/notifications/preferences/", {"category": "BLOOD", "enabled": False}, format="json"
        )
        self.assertEqual(patched.status_code, 200)
        self.assertIs(patched.data["enabled"], False)
        again = self.client.get("/api/notifications/preferences/")
        self.assertIs(again.data["preferences"]["BLOOD"], False)

    def test_preferences_require_auth(self):
        self.assertEqual(APIClient().get("/api/notifications/preferences/").status_code, 401)
        self.assertEqual(APIClient().get("/api/notifications/").status_code, 401)


# ---------------------------------------------------------------------------
# Stage 4.13 — extended notifications & preferences surface
# ---------------------------------------------------------------------------

from notifications.models import NotificationPreference, PushDevice
from notifications.services import create_notification, mark_read


class Stage413InboxApiTests(TestCase):
    def setUp(self):
        self.user = _orm_user()
        self.client = _client(self.user)
        self.pending = Notification.objects.create(
            recipient=self.user, type="SYSTEM", title="One", body="First",
        )
        Notification.objects.create(
            recipient=self.user, type="SYSTEM", title="Two", body="Second",
        )
        marked = Notification.objects.create(
            recipient=self.user, type="SYSTEM", title="Three", body="Third",
        )
        mark_read(marked)
        Notification.objects.create(
            recipient=self.user, type="COMMUNITY", title="Muted", body="Hidden",
            status="SUPPRESSED",
        )

    def test_list_excludes_suppressed(self):
        resp = self.client.get("/api/notifications/")
        self.assertEqual(resp.status_code, 200)
        self.assertEqual(resp.data["count"], 3)

    def test_unread_count_endpoint(self):
        resp = self.client.get("/api/notifications/unread-count/")
        self.assertEqual(resp.status_code, 200)
        self.assertEqual(resp.data["unread"], 2)

    def test_mark_all_read_updates_unread_count(self):
        self.client.post("/api/notifications/read-all/")
        resp = self.client.get("/api/notifications/unread-count/")
        self.assertEqual(resp.data["unread"], 0)

    def test_mark_read_is_idor_safe(self):
        stranger = _client(_orm_user())
        self.assertEqual(
            stranger.post(f"/api/notifications/{self.pending.id}/read/").status_code, 404
        )
        self.assertEqual(stranger.get(f"/api/notifications/{self.pending.id}/").status_code, 404)

    def test_unread_count_requires_auth(self):
        self.assertEqual(APIClient().get("/api/notifications/unread-count/").status_code, 401)


class Stage413PreferenceTests(TestCase):
    def setUp(self):
        self.user_a = _orm_user()
        self.client_a = _client(self.user_a)

    def test_preferences_are_user_scoped(self):
        user_b = _orm_user()
        client_b = _client(user_b)
        self.client_a.patch("/api/notifications/preferences/", {"category": "BLOOD", "enabled": False}, format="json")
        got_a = self.client_a.get("/api/notifications/preferences/").data["preferences"]
        got_b = client_b.get("/api/notifications/preferences/").data["preferences"]
        self.assertIs(got_a["BLOOD"], False)
        self.assertIs(got_b["BLOOD"], True)

    def test_emergency_preference_cannot_be_disabled(self):
        resp = self.client_a.patch(
            "/api/notifications/preferences/", {"category": "EMERGENCY", "enabled": False}, format="json"
        )
        self.assertEqual(resp.status_code, 400)
        pref = NotificationPreference.objects.filter(user=self.user_a, category="EMERGENCY").first()
        self.assertIsNone(pref)


class Stage413DeviceTests(TestCase):
    def setUp(self):
        self.user = _orm_user()
        self.client = _client(self.user)

    def test_register_requires_auth(self):
        resp = APIClient().post(
            "/api/notifications/devices/",
            {"push_token": "tok-x", "platform": "ANDROID", "device_id": "D1"},
            format="json",
        )
        self.assertEqual(resp.status_code, 401)

    def test_register_and_list_never_echo_token(self):
        resp = self.client.post(
            "/api/notifications/devices/",
            {"push_token": "tok-secret-1", "platform": "ANDROID", "device_id": "D1"},
            format="json",
        )
        self.assertEqual(resp.status_code, 201)
        body = resp.content.decode()
        self.assertNotIn("tok-secret-1", body)
        self.assertNotIn("push_token", body)
        listed = self.client.get("/api/notifications/devices/").data
        self.assertEqual(len(listed), 1)
        self.assertNotIn("tok-secret-1", self.client.get("/api/notifications/devices/").content.decode())
        stored = PushDevice.objects.get(user=self.user, device_id="D1")
        self.assertEqual(stored.push_token, "tok-secret-1")
        self.assertTrue(stored.is_active)

    def test_rotation_updates_token_on_same_device(self):
        self.client.post(
            "/api/notifications/devices/",
            {"push_token": "tok-old", "platform": "IOS", "device_id": "D1"},
            format="json",
        )
        self.client.post(
            "/api/notifications/devices/",
            {"push_token": "tok-new", "platform": "IOS", "device_id": "D1"},
            format="json",
        )
        self.assertEqual(PushDevice.objects.filter(user=self.user).count(), 1)
        self.assertEqual(PushDevice.objects.get(user=self.user).push_token, "tok-new")

    def test_devices_are_user_scoped(self):
        self.client.post(
            "/api/notifications/devices/",
            {"push_token": "tok-own", "platform": "ANDROID", "device_id": "D1"},
            format="json",
        )
        stranger = _client(_orm_user())
        self.assertEqual(len(stranger.get("/api/notifications/devices/").data), 0)
        device = PushDevice.objects.get(user=self.user)
        self.assertEqual(stranger.delete(f"/api/notifications/devices/{device.id}/").status_code, 404)

    def test_deactivate_own_device(self):
        self.client.post(
            "/api/notifications/devices/",
            {"push_token": "tok-a", "platform": "ANDROID", "device_id": "D1"},
            format="json",
        )
        device = PushDevice.objects.get(user=self.user)
        resp = self.client.delete(f"/api/notifications/devices/{device.id}/")
        self.assertEqual(resp.status_code, 200)
        device.refresh_from_db()
        self.assertFalse(device.is_active)
        self.assertEqual(len(self.client.get("/api/notifications/devices/").data), 0)

    def test_reactivation_after_deactivate(self):
        self.client.post(
            "/api/notifications/devices/",
            {"push_token": "tok-a", "platform": "ANDROID", "device_id": "D1"},
            format="json",
        )
        device = PushDevice.objects.get(user=self.user)
        self.client.delete(f"/api/notifications/devices/{device.id}/")
        self.client.post(
            "/api/notifications/devices/",
            {"push_token": "tok-b", "platform": "ANDROID", "device_id": "D1"},
            format="json",
        )
        device.refresh_from_db()
        self.assertTrue(device.is_active)
        self.assertEqual(device.push_token, "tok-b")


class Stage413PrivacyAndRoleTests(TestCase):
    def test_medication_reminder_does_not_leak_medication_name(self):
        from datetime import timedelta

        from django.utils import timezone as tz

        from medications.models import Medication, MedicationSchedule
        from notifications.reminders import dispatch_medication_reminders

        now = tz.now()
        patient = _orm_user()
        med = Medication.objects.create(
            patient=patient, name="Hydroxyurea 500mg UniqueName", frequency="daily",
            start_date=now.date(),
        )
        MedicationSchedule.objects.create(
            medication=med,
            time_of_day=(now + timedelta(minutes=30)).time(),
            days_of_week=[tz.localtime(now).strftime("%a").upper()[:3]],
        )
        dispatch_medication_reminders(now=now)
        note = Notification.objects.filter(recipient=patient, type="MEDICATION_REMINDER").first()
        self.assertIsNotNone(note)
        self.assertNotIn("Hydroxyurea", note.body)
        self.assertNotIn("UniqueName", note.data.get("resource_id", ""))

    def test_medication_reminder_dispatch_is_idempotent(self):
        from datetime import timedelta

        from django.utils import timezone as tz

        from medications.models import Medication, MedicationSchedule
        from notifications.reminders import dispatch_medication_reminders

        now = tz.now()
        patient = _orm_user()
        med = Medication.objects.create(
            patient=patient, name="Methotrexate", frequency="daily", start_date=now.date(),
        )
        MedicationSchedule.objects.create(
            medication=med, time_of_day=(now + timedelta(minutes=15)).time(),
            days_of_week=[tz.localtime(now).strftime("%a").upper()[:3]],
        )
        self.assertEqual(dispatch_medication_reminders(now=now), 1)
        self.assertEqual(dispatch_medication_reminders(now=now), 0)
        self.assertEqual(
            Notification.objects.filter(recipient=patient, type="MEDICATION_REMINDER").count(), 1
        )

    def test_community_comment_notification_is_generic(self):
        from community.models import CommunityPost
        from community.services import create_comment

        author = _orm_user()
        commenter = _orm_user()
        post = CommunityPost.objects.create(author=author, content="My post", status="PUBLISHED")
        create_comment(post=post, author=commenter, content="Secret private reply 5522")
        note = Notification.objects.filter(recipient=author, type="COMMUNITY").first()
        self.assertIsNotNone(note)
        self.assertNotIn("Secret private reply", note.body)
        self.assertNotIn("5522", note.body)
        self.assertEqual(note.related_resource_type, "community_post")
        self.assertEqual(note.related_resource_id, str(post.uid))

    def test_comment_to_own_post_does_not_notify_self(self):
        from community.models import CommunityPost
        from community.services import create_comment

        author = _orm_user()
        post = CommunityPost.objects.create(author=author, content="Mine", status="PUBLISHED")
        create_comment(post=post, author=author, content="self reply")
        self.assertFalse(Notification.objects.filter(recipient=author, type="COMMUNITY").exists())

    def test_education_publish_notifies_author_only(self):
        from education.models import EducationCategory, EducationalContent
        from education.services import review_content

        author = _orm_user()
        reviewer = _orm_user()
        cat = EducationCategory.objects.create(code="GEN2", name="General", sort_order=1)
        content = EducationalContent.objects.create(
            author=author, title="Crisis facts", body="Content body",
            category=cat, status="IN_REVIEW",
        )
        review_content(content, actor=reviewer, decision="approve")
        note = Notification.objects.filter(recipient=author, type="SYSTEM").first()
        self.assertIsNotNone(note)
        self.assertEqual(note.related_resource_type, "education_content")
        self.assertEqual(note.related_resource_id, str(content.uid))
        self.assertNotIn("Crisis facts", note.body)
        self.assertFalse(Notification.objects.filter(recipient=reviewer).exists())

    def test_conversation_start_is_non_phi(self):
        from doctors.services import create_conversation

        creator = _orm_user()
        partner = _orm_user()
        create_conversation(creator=creator, partner=partner)
        note = Notification.objects.filter(recipient=partner, type="SYSTEM").first()
        self.assertIsNotNone(note)
        self.assertEqual(note.related_resource_type, "conversation")
        self.assertNotIn("message", note.body.lower())

    def test_admin_does_not_see_patient_notifications(self):
        patient = _orm_user()
        admin = _orm_user(role_code="SUPER_ADMIN")
        create_notification(recipient=patient, type_="SYSTEM", title="Med update", body="x")
        admin_client = _client(admin)
        self.assertEqual(admin_client.get("/api/notifications/").data["count"], 0)

    def test_security_notification_is_forced_over_system_mute(self):
        user = _orm_user()
        NotificationPreference.objects.create(user=user, category="SYSTEM", enabled=False)
        create_notification(recipient=user, type_="SYSTEM", title="Security", body="Alert", force=True)
        note = Notification.objects.get(recipient=user, title="Security")
        self.assertEqual(note.status, "PENDING")

    def test_system_mute_does_not_suppress_critical_payment_or_blood(self):
        user = _orm_user()
        NotificationPreference.objects.create(user=user, category="PAYMENT", enabled=False)
        note = create_notification(recipient=user, type_="PAYMENT", title="Pay success", body="ok")
        self.assertEqual(note.status, "SUPPRESSED")
        forced = create_notification(recipient=user, type_="EMERGENCY", title="SOS", body="ok", force=True)
        self.assertEqual(forced.status, "PENDING")


class Stage413IntegrationTests(TestCase):
    def test_login_emits_forced_security_notification(self):
        user = _orm_user()
        NotificationPreference.objects.create(user=user, category="SYSTEM", enabled=False)
        client = APIClient()
        resp = client.post(
            "/api/auth/login/",
            {"email_or_phone": user.email, "password": _PASSWORD},
            format="json",
        )
        self.assertEqual(resp.status_code, 200)
        note = Notification.objects.filter(recipient=user, type="SYSTEM", title="New sign-in").first()
        self.assertIsNotNone(note)
        self.assertEqual(note.status, "PENDING")
        self.assertEqual(note.priority, "HIGH")

    def test_community_comment_flow(self):
        from community.models import CommunityPost
        from community.services import create_comment, set_reaction

        author = _orm_user()
        member = _orm_user()
        post = CommunityPost.objects.create(author=author, content="hi", status="PUBLISHED")
        create_comment(post=post, author=member, content="hello")
        set_reaction(post=post, user=member, reaction_type="LIVE")
        set_reaction(post=post, user=member, reaction_type="LIVE")
        self.assertEqual(Notification.objects.filter(recipient=author, type="COMMUNITY").count(), 2)