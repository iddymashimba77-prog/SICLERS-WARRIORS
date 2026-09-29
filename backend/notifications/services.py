"""Notification service (Stage 4.8 foundation, extended in Stage 4.13).

The ONE place application modules create notifications. Blood matching,
emergencies, donations, community, education and reminders all call
``create_notification``; nothing sends to a provider directly.

Deduping: a ``delivery_key`` is a stable unique logical identity (e.g.
``blood:match:<id>``); ``get_or_create`` on that key makes re-runs idempotent
(duplicate attempts return the existing row instead of a second notification).

Preferences (FR-NOT-006): non-emergency categories can be muted per-user;
muted notifications are recorded as SUPPRESSED for audit, never silently lost.

Safety (BR-009 / special-systems §3.9.4): EMERGENCY notifications are NEVER
suppressible. Security/consent signals (``force=True``) are likewise recorded
as PENDING even when their category is muted.

Priority (Stage 4.13): derived from ``type`` by default (EMERGENCY→CRITICAL,
BLOOD→HIGH, everything else NORMAL) unless the caller overrides ``priority``.

Delivery: in-app delivery is the database row itself. External push delivery
is an extension point (``deliver_push``) that only acts when a provider is
configured; it never fakes a send when none is configured.
"""

import logging

from django.utils import timezone

from .models import Notification, NotificationPreference, PushDevice

logger = logging.getLogger(__name__)

# Emergency notifications are NEVER suppressible (FR-EMG, BR-009).
FORCED_CATEGORIES = {"EMERGENCY"}

ALL_CATEGORIES = [t for t, _ in Notification.TYPE]

_PRIORITY_BY_TYPE = {
    "EMERGENCY": "CRITICAL",
    "BLOOD": "HIGH",
    "PAYMENT": "NORMAL",
    "MEDICATION_REMINDER": "NORMAL",
    "APPOINTMENT": "NORMAL",
    "COMMUNITY": "LOW",
    "CONSENT": "HIGH",
    "SYSTEM": "NORMAL",
}


def is_enabled(user, category: str) -> bool:
    """Preference for a category == None means enabled (default)."""
    pref = NotificationPreference.objects.filter(user=user, category=category).first()
    return pref.enabled if pref is not None else True


def create_notification(
    *,
    recipient,
    type_,
    title,
    body,
    channel="IN_APP",
    priority=None,
    data=None,
    related_resource_type="",
    related_resource_id="",
    delivery_key=None,
    force=False,
):
    """Create one notification row.

    Returns the Notification. When a ``delivery_key`` is supplied the creation is
    idempotent: an existing row for the same key is returned unchanged.
    Categories muted by preference (and not forced/emergency) are created with
    status SUPPRESSED.

    ``data`` carries only the minimum deep-link context (never medical content).
    """

    muted = False
    if not force and type_ not in FORCED_CATEGORIES:
        muted = not is_enabled(recipient, type_)
    status = "SUPPRESSED" if muted else "PENDING"
    prio = priority or _PRIORITY_BY_TYPE.get(type_, "NORMAL")
    payload = dict(data or {})

    if delivery_key:
        obj, _created = Notification.objects.get_or_create(
            delivery_key=delivery_key,
            defaults={
                "recipient": recipient,
                "type": type_,
                "priority": prio,
                "channel": channel,
                "title": title,
                "body": body,
                "data": payload,
                "related_resource_type": related_resource_type[:60],
                "related_resource_id": str(related_resource_id)[:64] if related_resource_id else "",
                "status": status,
            },
        )
        return obj
    return Notification.objects.create(
        recipient=recipient,
        type=type_,
        priority=prio,
        channel=channel,
        title=title,
        body=body,
        data=payload,
        related_resource_type=related_resource_type[:60],
        related_resource_id=str(related_resource_id)[:64] if related_resource_id else "",
        status=status,
    )


def unread_count(user) -> int:
    """Number of inbox rows the user has not read (SUPPRESSED excluded)."""
    return Notification.objects.filter(recipient=user).exclude(
        status__in=("READ", "SUPPRESSED")
    ).count()


def create_broadcast_notifications(*, recipients, title, body, channel="IN_APP"):
    """Create one SYSTEM row per recipient in a single ``bulk_create`` window.

    Stage 4.18 (NFR-PERF-004): the admin broadcast previously issued one INSERT
    per target (up to 500 rows). Broadcasting is always ``force=True`` (policy
    rows are never suppressible — BR-009 / §21), so no per-recipient preference
    lookups are needed and a single bulk insert is safe and semantics-identical.

    Returns the number of rows created. Deduplication is intentionally NOT part
    of the broadcast contract (the audience is re-sent verbatim on re-post).
    """
    prio = _PRIORITY_BY_TYPE.get("SYSTEM", "NORMAL")
    rows = [
        Notification(
            recipient=recipient,
            type="SYSTEM",
            priority=prio,
            channel=channel,
            title=title,
            body=body,
            data={},
            related_resource_type="",
            related_resource_id="",
            status="PENDING",
        )
        for recipient in recipients
    ]
    if not rows:
        return 0
    Notification.objects.bulk_create(rows, batch_size=500)
    return len(rows)


def mark_read(notification) -> Notification:
    """Mark a single notification READ (in-place; returns the row)."""
    if notification.status != "READ":
        notification.status = "READ"
        notification.read_at = timezone.now()
        notification.save(update_fields=["status", "read_at"])
    return notification


def read_all(user) -> int:
    """Mark all of the user's readable notifications READ. Returns count."""
    updated = Notification.objects.filter(recipient=user).exclude(
        status__in=("READ", "SUPPRESSED")
    ).update(status="READ", read_at=timezone.now())
    return updated


# ---------------------------------------------------------------------------
# Push device/token management (Stage 4.13, §21)
# ---------------------------------------------------------------------------


def register_device(*, user, push_token, platform="OTHER", device_id=""):
    """Register/rotate a push token for one of the user's devices.

    Idempotent per (user, device_id): re-registration rotates the token on the
    same row and re-activates it (token rotation, logout re-login).
    """
    auth = user.is_authenticated if hasattr(user, "is_authenticated") else True
    if not auth:
        raise ValueError("Device registration requires an authenticated user.")
    device, _created = PushDevice.objects.update_or_create(
        user=user,
        device_id=device_id,
        defaults={
            "push_token": push_token,
            "platform": platform,
            "is_active": True,
            "last_seen_at": timezone.now(),
        },
    )
    return device


def deactivate_device(user, device) -> bool:
    """Soft-deactivate a device owned by ``user``. Returns True when deactivated."""
    if device.user_id != user.pk:
        return False
    if device.is_active:
        device.is_active = False
        device.save(update_fields=["is_active", "updated_at"])
    return True


def list_devices(user):
    """Active push devices for the user (token kept out of any serializer)."""
    return PushDevice.objects.filter(user=user, is_active=True)


# ---------------------------------------------------------------------------
# Push delivery extension point (Stage 4.13)
# ---------------------------------------------------------------------------

def deliver_push(notification) -> bool:
    """Attempt external push delivery for a single notification.

    This is a pure extension point. FCM is NOT configured in this environment
    (no credentials, no mobile firebase project), so the default implementation
    is a documented no-op that never fakes a successful send. Wire a provider
    (e.g. firebase-admin) here when a project approves one; on success set
    ``status="SENT"`` + ``sent_at`` and catch provider failures (→ FAILED).
    """
    logger.debug("Push delivery is not configured; %s stays %s (in-app only).",
                 notification.pk, notification.status)
    return False