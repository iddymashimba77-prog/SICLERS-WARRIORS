"""Phase 9 — notifications: inbox items, preferences, push devices."""

from __future__ import annotations

import datetime as _dt

from django.utils import timezone

from notifications.models import Notification, NotificationPreference, PushDevice

from .base import TAG, uuid_for

CATEGORIES = [
    "MEDICATION_REMINDER", "APPOINTMENT", "BLOOD", "EMERGENCY",
    "PAYMENT", "COMMUNITY", "CONSENT", "SYSTEM",
]


def seed(ctx) -> None:
    ctx.log("## Notifications")
    rng = ctx.rng
    now = timezone.now()
    recipients = ctx.users_of("PATIENT") + ctx.users_of("CAREGIVER") + ctx.users_of("BLOOD_DONOR")
    if not recipients:
        ctx.log("- skipped (no recipients)")
        return

    for i, user in enumerate(recipients, start=1):
        for k in range(1, 5):
            ntype = ["MEDICATION_REMINDER", "APPOINTMENT", "BLOOD", "CONSENT", "SYSTEM", "COMMUNITY"][(i + k) % 6]
            status = ["READ", "SENT", "DELIVERED", "PENDING"][(i + k) % 4]
            Notification.objects.update_or_create(
                delivery_key=f"{TAG}-NOTIF-{i}-{k}",
                defaults={
                    "recipient": user,
                    "type": ntype,
                    "priority": ["LOW", "NORMAL", "HIGH", "CRITICAL"][(i + k) % 4],
                    "channel": ["IN_APP", "PUSH", "EMAIL", "SMS"][(i + k) % 4],
                    "title": f"{TAG} {ntype.replace('_', ' ').title()} #{k}",
                    "body": f"{TAG} demo notification body for {user.first_name}.",
                    "data": {"source": TAG},
                    "related_resource_type": "qa_seed",
                    "related_resource_id": str(uuid_for("notif-resource", i, k)),
                    "status": status,
                    "read_at": timezone.now() - _dt.timedelta(days=1) if status == "READ" else None,
                    "sent_at": timezone.now() - _dt.timedelta(days=2) if status != "PENDING" else None,
                },
            )
            ctx.track("notifications")

        for category in ["MEDICATION_REMINDER", "APPOINTMENT", "BLOOD", "EMERGENCY", "PAYMENT", "COMMUNITY", "CONSENT", "SYSTEM"]:
            NotificationPreference.objects.update_or_create(
                user=user, category=category,
                defaults={"enabled": (hash((i, category)) % 5) != 0},
            )
            ctx.track("notification_preferences")

        if i % 4 == 0:
            PushDevice.objects.update_or_create(
                user=user, device_id=f"{TAG}-device-{i}",
                defaults={
                    "push_token": f"{TAG}-token-{i}",
                    "platform": ["ANDROID", "IOS", "WEB", "OTHER"][i % 4],
                    "is_active": True,
                    "last_seen_at": timezone.now() - _dt.timedelta(hours=i),
                },
            )
            ctx.track("push_devices")

    ctx.log(
        f"- notifications={ctx.counts.get('notifications', 0)} "
        f"preferences={ctx.counts.get('notification_preferences', 0)} "
        f"devices={ctx.counts.get('push_devices', 0)}"
    )
