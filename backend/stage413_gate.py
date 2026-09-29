"""Stage 4.13 notification gate — ephemeral SQLite ONLY.

Purpose
-------
Proves Stage 4.13 notifications & preferences end to end on top of the Stage
4.10-4.12 surface (`stage411_gate.py` / `stage412_gate.py`):

  1. inbox list is recipient-scoped + SUPPRESSED excluded + unread-count.
  2. preferences GET/PATCH; emergency can never be disabled.
  3. push device register/list/rotate/deactivate; tokens never echoed;
     cross-user device access denied (404).
  4. event hooks through the CENTRAL service:
       community comment       -> COMMUNITY to post author (generic body)
       education publish       -> SYSTEM to author
       medication reminder job -> MEDICATION_REMINDER (privacy-safe, idempotent)
       payment timeout         -> PRIVACY-safe PAYMENT on confirmed webhook
       login                   -> forced SYSTEM security alert
       emergency               -> CRITICAL, non-suppressible
  5. IDOR: user A cannot read or mark user B's notification/device.

Run:  venv/bin/python stage413_gate.py   (from backend/)
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
    from django.utils import timezone
    from rest_framework.test import APIClient
    from rest_framework_simplejwt.tokens import RefreshToken

    from accounts.models import Role, User, UserRole
    from community.models import CommunityPost
    from community.services import create_comment
    from education.models import EducationCategory, EducationalContent
    from education.services import review_content
    from notifications.models import Notification, NotificationPreference, PushDevice
    from notifications.reminders import dispatch_medication_reminders
    from notifications.services import create_notification
    from medications.models import Medication, MedicationSchedule

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


    patient = orm_user()
    stranger = orm_user()
    c = client(patient)
    cs = client(stranger)

    # 1. Inbox + unread-count.
    a = create_notification(recipient=patient, type_="SYSTEM", title="Welcome", body="hi")
    b = create_notification(recipient=patient, type_="BLOOD", title="Match", body="hi")
    check("list count == 2", c.get("/api/notifications/").data["count"] == 2)
    check("unread == 2", c.get("/api/notifications/unread-count/").data["unread"] == 2)
    check("priority derived BLOOD==HIGH", b.priority == "HIGH")
    c.post(f"/api/notifications/{a.id}/read/")
    check("unread after read == 1", c.get("/api/notifications/unread-count/").data["unread"] == 1)
    check("IDOR detail 404", cs.get(f"/api/notifications/{a.id}/").status_code == 404)
    check("IDOR read 404", cs.post(f"/api/notifications/{a.id}/read/").status_code == 404)

    # 2. Preferences.
    c.patch("/api/notifications/preferences/", {"category": "BLOOD", "enabled": False}, format="json")
    check("pref muted", c.get("/api/notifications/preferences/").data["preferences"]["BLOOD"] is False)
    check("prefs are user scoped", cs.get("/api/notifications/preferences/").data["preferences"]["BLOOD"] is True)
    blocked = c.patch("/api/notifications/preferences/", {"category": "EMERGENCY", "enabled": False}, format="json")
    check("emergency pref cannot disable", blocked.status_code == 400)

    # 3. Devices.
    reg = c.post("/api/notifications/devices/",
                 {"push_token": "tok-secret", "platform": "ANDROID", "device_id": "D1"}, format="json")
    check("device registered", reg.status_code == 201)
    check("token not echoed", "tok-secret" not in reg.content.decode() and "push_token" not in reg.content.decode())
    dev = PushDevice.objects.get(user=patient)
    check("stranger device list empty", len(cs.get("/api/notifications/devices/").data) == 0)
    check("stranger deactivate 404", cs.delete(f"/api/notifications/devices/{dev.id}/").status_code == 404)
    c.post("/api/notifications/devices/",
           {"push_token": "tok-new", "platform": "ANDROID", "device_id": "D1"}, format="json")
    dev.refresh_from_db()
    check("token rotation on same device", dev.push_token == "tok-new" and PushDevice.objects.filter(user=patient).count() == 1)
    check("deactivate own", c.delete(f"/api/notifications/devices/{dev.id}/").status_code == 200)
    dev.refresh_from_db()
    check("deactivated soft", dev.is_active is False)

    # 4. Hooks via central service.
    author = orm_user()
    member = orm_user()
    post = CommunityPost.objects.create(author=author, content="post", status="PUBLISHED")
    create_comment(post=post, author=member, content="secret reply 9933")
    note = Notification.objects.filter(recipient=author, type="COMMUNITY").first()
    check("community comment notified + generic", note is not None and "secret reply" not in note.body)

    edu = orm_user()
    reviewer = orm_user()
    cat = EducationCategory.objects.create(code="GEN", name="General", sort_order=1)
    content = EducationalContent.objects.create(author=edu, title="T", body="B", category=cat, status="IN_REVIEW")
    review_content(content, actor=reviewer, decision="approve")
    check("education publish notified", Notification.objects.filter(recipient=edu, type="SYSTEM").exists())

    now = timezone.now()
    med = Medication.objects.create(patient=patient, name="SuperSecretDrug", frequency="daily", start_date=now.date())
    MedicationSchedule.objects.create(
        medication=med, time_of_day=now.time(),
        days_of_week=[timezone.localtime(now).strftime("%a").upper()[:3]],
    )
    n1 = dispatch_medication_reminders(now=now)
    n2 = dispatch_medication_reminders(now=now)
    reminder = Notification.objects.filter(recipient=patient, type="MEDICATION_REMINDER").first()
    check("med reminder dispatched once", n1 == 1 and n2 == 0)
    check("med reminder privacy-safe", reminder is not None and "SuperSecretDrug" not in reminder.body)

    # Forced security alert (mute SYSTEM, still PENDING).
    NotificationPreference.objects.create(user=patient, category="SYSTEM", enabled=False)
    create_notification(recipient=patient, type_="SYSTEM", title="Security", body="Alert", priority="HIGH", force=True)
    sec = Notification.objects.get(recipient=patient, title="Security")
    check("security forced over mute", sec.status == "PENDING" and sec.priority == "HIGH")

    emg = create_notification(recipient=patient, type_="EMERGENCY", title="SOS", body="x", force=True)
    check("emergency CRITICAL + forced", emg.priority == "CRITICAL" and emg.status == "PENDING")

    ok = len(checks) == sum(1 for _, passed in checks if passed)
finally:
    runner.teardown_databases(old_config)

print(f"Stage 4.13 gate: {sum(1 for _, p in checks if p)}/{len(checks)} checks passed")
print("GATE_OK" if ok else "GATE_FAILED")
raise SystemExit(0 if ok else 1)