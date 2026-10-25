"""AI assistant conversation models.

Persistent Ask AI history (owner-scoped):

* a ``Conversation`` belongs to exactly one user and is only ever returned to
  that user (API filtering is by ``user``; other uids are 404);
* a ``Message`` stores the turn text plus a ``meta`` envelope (safety flags,
  emergency categories, citations) so reopening a thread preserves the
  guidance the live response showed;
* deleting the user cascades to their conversations and messages, and
  deleting a conversation cascades to its messages.

These transcripts necessarily contain health-related text; retention is
expected to follow the project's data-retention policy, and access is limited
to the owner (API) and staff with Django-admin access.
"""

import uuid

from django.conf import settings
from django.db import models
from django.utils import timezone


class Conversation(models.Model):
    uid = models.UUIDField(default=uuid.uuid4, editable=False, unique=True, db_index=True)
    user = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name="ai_conversations",
    )
    title = models.CharField(max_length=200, blank=True)
    created_at = models.DateTimeField(auto_now_add=True, db_index=True)
    updated_at = models.DateTimeField(auto_now=True, db_index=True)
    last_activity_at = models.DateTimeField(default=timezone.now, db_index=True)
    archived = models.BooleanField(default=False)

    class Meta:
        ordering = ["-last_activity_at", "-created_at"]
        indexes = [
            models.Index(fields=["user", "-last_activity_at"]),
        ]

    def __str__(self):
        return f"Conversation({self.uid})"


class Message(models.Model):
    class Role(models.TextChoices):
        USER = "user", "User"
        ASSISTANT = "assistant", "Assistant"

    uid = models.UUIDField(default=uuid.uuid4, editable=False, unique=True, db_index=True)
    conversation = models.ForeignKey(
        Conversation,
        on_delete=models.CASCADE,
        related_name="messages",
    )
    role = models.CharField(max_length=20, choices=Role.choices)
    content = models.TextField()
    created_at = models.DateTimeField(auto_now_add=True, db_index=True)
    meta = models.JSONField(default=dict, blank=True)

    class Meta:
        ordering = ["created_at", "id"]
        indexes = [
            models.Index(fields=["conversation", "created_at"]),
        ]

    def __str__(self):
        return f"Message({self.uid}, {self.role})"
