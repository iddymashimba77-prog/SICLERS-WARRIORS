"""Doctor / communication domain (approved Stage 4.10).

Source of truth:
  docs/sdlc/03-system-design/erd/community-communication-erd.md
  docs/sdlc/03-system-design/database-design.md §15 (lines 342-348)

CHECK vocabularies:
  conversations.type                 : DOCTOR_PATIENT PEER GROUP
  conversations.status               : ACTIVE CLOSED ARCHIVED
  conversation_participants.status   : ACTIVE LEFT BLOCKED REMOVED
  messages.message_type              : TEXT IMAGE FILE SYSTEM
  messages.status                    : SENT DELIVERED READ FAILED DELETED

Privacy (security-design §23): v1 is NOT end-to-end encrypted; TLS transport
plus server-side participant ACL (C13) is the designed level. Admin roles hold
no ``chat.*`` code and can never read a private conversation. There is no
approved MESSAGE notification type, so no message-body push is emitted; only
unread counts surface on the conversation list.

``message_attachments`` is part of the approved schema, but the secure upload
pipeline is an open gap (security-api-traceability ASG-6: signed initiate +
complete). No upload/list endpoint is exposed here — attachments are metadata
only until that amendment lands. Blocking is FUTURE (v2, §23) and not modelled.
"""

import uuid

from django.conf import settings
from django.db import models
from django.utils import timezone

CONVERSATION_TYPES = ["DOCTOR_PATIENT", "PEER", "GROUP"]
CONVERSATION_STATUSES = ["ACTIVE", "CLOSED", "ARCHIVED"]
PARTICIPANT_STATUSES = ["ACTIVE", "LEFT", "BLOCKED", "REMOVED"]
MESSAGE_TYPES = ["TEXT", "IMAGE", "FILE", "SYSTEM"]
MESSAGE_STATUSES = ["SENT", "DELIVERED", "READ", "FAILED", "DELETED"]


class Conversation(models.Model):
    TYPE = [(value, value) for value in CONVERSATION_TYPES]
    STATUS = [(value, value) for value in CONVERSATION_STATUSES]

    uid = models.UUIDField(default=uuid.uuid4, editable=False, unique=True, db_index=True)
    type = models.CharField(max_length=20, choices=TYPE, default="DOCTOR_PATIENT")
    created_by = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.PROTECT, related_name="conversations_created",
    )
    status = models.CharField(max_length=10, choices=STATUS, default="ACTIVE", db_index=True)
    last_message_at = models.DateTimeField(null=True, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        db_table = "conversations"
        ordering = ["-last_message_at", "-created_at"]
        constraints = [
            models.CheckConstraint(
                condition=models.Q(type__in=CONVERSATION_TYPES), name="conversations_type_ck",
            ),
            models.CheckConstraint(
                condition=models.Q(status__in=CONVERSATION_STATUSES),
                name="conversations_status_ck",
            ),
        ]
        indexes = [
            models.Index(fields=["status", "-last_message_at"], name="conversations_status_idx"),
        ]

    def __str__(self):
        return f"conversation:{self.uid}"


class ConversationParticipant(models.Model):
    STATUS = [(value, value) for value in PARTICIPANT_STATUSES]

    conversation = models.ForeignKey(
        Conversation, on_delete=models.CASCADE, related_name="participants",
    )
    user = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.PROTECT, related_name="conversation_participations",
    )
    role_in_chat = models.CharField(max_length=20, default="MEMBER")
    status = models.CharField(max_length=10, choices=STATUS, default="ACTIVE", db_index=True)
    invited_by = models.ForeignKey(
        settings.AUTH_USER_MODEL, null=True, blank=True,
        on_delete=models.SET_NULL, related_name="conversation_invites",
    )
    joined_at = models.DateTimeField(default=timezone.now)

    class Meta:
        db_table = "conversation_participants"
        constraints = [
            models.CheckConstraint(
                condition=models.Q(status__in=PARTICIPANT_STATUSES),
                name="conversation_participants_status_ck",
            ),
            models.UniqueConstraint(
                fields=["conversation", "user"], name="conversation_participants_uk",
            ),
        ]
        indexes = [
            models.Index(fields=["user", "status"], name="conv_participants_user_idx"),
        ]

    def __str__(self):
        return f"participant:{self.user_id}:conv:{self.conversation_id}"


class Message(models.Model):
    MESSAGE_TYPE = [(value, value) for value in MESSAGE_TYPES]
    STATUS = [(value, value) for value in MESSAGE_STATUSES]

    uid = models.UUIDField(default=uuid.uuid4, editable=False, unique=True, db_index=True)
    conversation = models.ForeignKey(
        Conversation, on_delete=models.CASCADE, related_name="messages",
    )
    sender = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.PROTECT, related_name="chat_messages",
    )
    content = models.TextField(blank=True)
    message_type = models.CharField(max_length=8, choices=MESSAGE_TYPE, default="TEXT")
    status = models.CharField(max_length=10, choices=STATUS, default="SENT", db_index=True)
    created_at = models.DateTimeField(auto_now_add=True, db_index=True)
    # Own-view tombstone: deletion keeps the row and masks the body.
    deleted_at = models.DateTimeField(null=True, blank=True)

    class Meta:
        db_table = "messages"
        ordering = ["created_at"]
        constraints = [
            models.CheckConstraint(
                condition=models.Q(message_type__in=MESSAGE_TYPES), name="messages_type_ck",
            ),
            models.CheckConstraint(
                condition=models.Q(status__in=MESSAGE_STATUSES), name="messages_status_ck",
            ),
        ]
        indexes = [
            models.Index(fields=["conversation", "created_at"], name="messages_conv_ts_idx"),
        ]

    def __str__(self):
        return f"message:{self.uid}"


class MessageAttachment(models.Model):
    message = models.ForeignKey(
        Message, on_delete=models.CASCADE, related_name="attachments",
    )
    file_url = models.CharField(max_length=500)  # storage key, not a public URL
    content_type = models.CharField(max_length=120)
    size_bytes = models.PositiveBigIntegerField()
    uploaded_by = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.PROTECT, related_name="message_attachments",
    )
    uploaded_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        db_table = "message_attachments"

    def __str__(self):
        return f"attachment:{self.pk}:message:{self.message_id}"


class Doctor(models.Model):
    """Professional verification registry (approved Stage 4.x, AUTH-1).

    Source of truth — database-design.md §3.4 (line 179):
      doctors | user_id FK unique, facility_id FK null, license_number,
               specialty (code), registration_body, verification_status
               CHECK(PENDING APPROVED REJECTED SUSPENDED), verified_by FK,
               verified_at, verification_expires_at null, rejection_reason,
               is_active, created_at, updated_at.
               Sensitive documents live in `verification_documents` (secure
               storage, not public).

    Rules (role-perm §20, BR-001):
    * A doctor's clinical functions are available only while the account is
      ACTIVE AND ``verification_status == APPROVED`` (``User.is_verified_doctor``
      enforces both). Registration never auto-approves.
    * ``doctor.signup`` — separate from chat — is the approved entry point; the
      world-crossing surface stays a look-up of the professional registry.
    """

    VERIFICATION_STATUS = [
        ("PENDING", "PENDING"),
        ("APPROVED", "APPROVED"),
        ("REJECTED", "REJECTED"),
        ("SUSPENDED", "SUSPENDED"),
    ]

    user = models.OneToOneField(
        settings.AUTH_USER_MODEL, on_delete=models.PROTECT, related_name="doctor_profile",
    )
    facility = models.ForeignKey(
        "facilities.Facility", null=True, blank=True,
        on_delete=models.SET_NULL, related_name="doctors",
    )
    license_number = models.CharField(max_length=120, blank=True)
    specialty = models.CharField(max_length=120, blank=True, help_text="Clinical specialty code.")
    registration_body = models.CharField(max_length=200, blank=True)
    verification_status = models.CharField(
        max_length=16, choices=VERIFICATION_STATUS, default="PENDING", db_index=True,
    )
    verified_by = models.ForeignKey(
        settings.AUTH_USER_MODEL, null=True, blank=True,
        on_delete=models.SET_NULL, related_name="verified_doctors",
    )
    verified_at = models.DateTimeField(null=True, blank=True)
    verification_expires_at = models.DateTimeField(null=True, blank=True)
    rejection_reason = models.TextField(blank=True)
    is_active = models.BooleanField(default=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        db_table = "doctors"
        ordering = ["-created_at"]
        constraints = [
            models.CheckConstraint(
                condition=models.Q(verification_status__in=[
                    "PENDING", "APPROVED", "REJECTED", "SUSPENDED",
                ]),
                name="doctors_verification_status_ck",
            ),
        ]
        indexes = [
            models.Index(
                fields=["verification_status", "created_at"],
                name="doctors_status_created_idx",
            ),
        ]

    def __str__(self):
        return f"Doctor({self.user_id}:{self.verification_status})"
