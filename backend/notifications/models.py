"""Notification domain (approved Stage 4.8 service surface).

Source of truth — docs/sdlc/03-system-design/database-design.md §19 (lines 367-368):
  notifications | recipient_user_id FK, type CHECK(MEDICATION_REMINDER APPOINTMENT
                  BLOOD EMERGENCY PAYMENT COMMUNITY CONSENT SYSTEM),
                  channel CHECK(PUSH IN_APP EMAIL SMS), title, body,
                  related_resource_type, related_resource_id, status
                  CHECK(PENDING SENT DELIVERED READ FAILED SUPPRESSED),
                  delivery_key unique null, read_at, sent_at, created_at
  notification_preferences | user_id FK, category CHECK(mirrors type),
                             enabled bool, UNIQUE(user_id, category), updated_at

Stage 4.8 scope: models + internal `NotificationService` + minimal scoped
inbox API (GET/POST read, GET/PATCH preferences). Full inbox UI, push, and
broadcast are future-stage surfaces.
"""

from django.conf import settings
from django.db import models


class Notification(models.Model):
    TYPE = [
        ("MEDICATION_REMINDER", "MEDICATION_REMINDER"),
        ("APPOINTMENT", "APPOINTMENT"),
        ("BLOOD", "BLOOD"),
        ("EMERGENCY", "EMERGENCY"),
        ("PAYMENT", "PAYMENT"),
        ("COMMUNITY", "COMMUNITY"),
        ("CONSENT", "CONSENT"),
        ("SYSTEM", "SYSTEM"),
    ]
    CHANNEL = [
        ("PUSH", "PUSH"),
        ("IN_APP", "IN_APP"),
        ("EMAIL", "EMAIL"),
        ("SMS", "SMS"),
    ]
    STATUS = [
        ("PENDING", "PENDING"),
        ("SENT", "SENT"),
        ("DELIVERED", "DELIVERED"),
        ("READ", "READ"),
        ("FAILED", "FAILED"),
        ("SUPPRESSED", "SUPPRESSED"),
    ]
    PRIORITY = [
        ("LOW", "LOW"),
        ("NORMAL", "NORMAL"),
        ("HIGH", "HIGH"),
        ("CRITICAL", "CRITICAL"),
    ]

    recipient = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name="notifications",
    )
    type = models.CharField(max_length=30, choices=TYPE, db_index=True)
    priority = models.CharField(max_length=10, choices=PRIORITY, default="NORMAL", db_index=True)
    channel = models.CharField(max_length=10, choices=CHANNEL, default="IN_APP")
    title = models.CharField(max_length=200)
    body = models.TextField()
    data = models.JSONField(default=dict, blank=True)
    related_resource_type = models.CharField(max_length=60, blank=True)
    related_resource_id = models.CharField(max_length=64, blank=True)
    status = models.CharField(max_length=16, choices=STATUS, default="PENDING", db_index=True)
    delivery_key = models.CharField(max_length=200, null=True, blank=True, unique=True)
    read_at = models.DateTimeField(null=True, blank=True)
    sent_at = models.DateTimeField(null=True, blank=True)
    created_at = models.DateTimeField(auto_now_add=True, db_index=True)

    class Meta:
        db_table = "notifications"
        ordering = ["-created_at"]
        constraints = [
            models.CheckConstraint(
                condition=models.Q(status__in=["PENDING", "SENT", "DELIVERED", "READ", "FAILED", "SUPPRESSED"]),
                name="notif_status_ck",
            ),
            models.CheckConstraint(
                condition=models.Q(channel__in=["IN_APP", "PUSH", "SMS", "EMAIL"]),
                name="notif_channel_ck",
            ),
            models.CheckConstraint(
                condition=models.Q(priority__in=["LOW", "NORMAL", "HIGH", "CRITICAL"]),
                name="notif_priority_ck",
            ),
        ]
        indexes = [
            models.Index(fields=["recipient", "status", "-created_at"], name="notif_recipient_status_idx"),
            models.Index(fields=["recipient", "-created_at"], name="notif_recipient_ts_idx"),
        ]

    def __str__(self):
        return f"[{self.type}] → {self.recipient_id} ({self.status})"


class PushDevice(models.Model):
    """Registered push-capable device (Stage 4.13, §21 api-design).

    Only the fields the mobile push stack needs are stored:
      * ``push_token``   — treated as sensitive infrastructure data; write-only
        in every API serializer and never echoed to clients.
      * ``device_id``    — opaque client-generated identifier used to rotate a
        token on the same install instead of creating a duplicate row.
      * ``platform``     — ANDROID / IOS / WEB / OTHER.

    A user may register many devices. Deactivation is a soft flag so token
    rotation and logout cleanup stay auditable without destructive deletes.
    """

    PLATFORM = [
        ("ANDROID", "ANDROID"),
        ("IOS", "IOS"),
        ("WEB", "WEB"),
        ("OTHER", "OTHER"),
    ]

    user = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name="push_devices",
    )
    device_id = models.CharField(max_length=120, blank=True)
    push_token = models.CharField(max_length=255, db_index=True)
    platform = models.CharField(max_length=10, choices=PLATFORM, default="OTHER")
    is_active = models.BooleanField(default=True)
    last_seen_at = models.DateTimeField(null=True, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        db_table = "push_devices"
        ordering = ["-updated_at"]
        constraints = [
            models.CheckConstraint(
                condition=models.Q(platform__in=["ANDROID", "IOS", "WEB", "OTHER"]),
                name="push_device_platform_ck",
            ),
            models.UniqueConstraint(fields=["user", "device_id"], name="push_dev_user_device_uk"),
        ]
        indexes = [
            models.Index(fields=["user", "is_active"], name="push_dev_user_active_idx"),
            models.Index(fields=["push_token"], name="push_dev_token_idx"),
        ]

    def __str__(self):
        return f"{self.user_id}:{self.device_id or self.push_token[:8]} ({self.platform})"


class NotificationPreference(models.Model):
    CATEGORY = Notification.TYPE

    user = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name="notification_preferences",
    )
    category = models.CharField(max_length=30, choices=CATEGORY)
    enabled = models.BooleanField(default=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        db_table = "notification_preferences"
        constraints = [
            models.UniqueConstraint(fields=["user", "category"], name="notif_pref_user_cat_uk"),
        ]

    def __str__(self):
        return f"{self.user_id}:{self.category}={'ON' if self.enabled else 'OFF'}"
