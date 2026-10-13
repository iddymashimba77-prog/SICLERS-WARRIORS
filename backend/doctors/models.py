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

    `professional_type` says which kind of professional the row describes. It is
    one column rather than three near-identical tables because the *verification
    question is the same question* for all of them: is this person who they say
    they are, and is that registration current? The queue, the documents, the
    decision trail and the suspension path are shared for that reason.

    What the type does **not** do is grant privileges. ``DOCTOR``,
    ``PSYCHOLOGIST`` and ``SOCIAL_SUPPORT`` are separate *account roles* with
    separate permission bundles (accounts migration 0014); this column only
    records which professional the verified row belongs to, so that
    ``is_verified_doctor`` can stay doctor-specific and the directory can say
    "psychologist" instead of "doctor".
    """

    PROFESSIONAL_TYPES = [
        ("DOCTOR", "Doctor"),
        ("PSYCHOLOGIST", "Psychologist"),
        ("SOCIAL_SUPPORT", "Social support worker"),
    ]
    PROFESSIONAL_TYPE_CODES = [value for value, _ in PROFESSIONAL_TYPES]

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
    professional_type = models.CharField(
        max_length=16, choices=PROFESSIONAL_TYPES, default="DOCTOR", db_index=True,
        help_text="Which professional this registry row describes; not a privilege grant.",
    )
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
            models.CheckConstraint(
                condition=models.Q(professional_type__in=[
                    "DOCTOR", "PSYCHOLOGIST", "SOCIAL_SUPPORT",
                ]),
                name="doctors_professional_type_ck",
            ),
        ]
        indexes = [
            models.Index(
                fields=["verification_status", "created_at"],
                name="doctors_status_created_idx",
            ),
            models.Index(
                fields=["professional_type", "verification_status"],
                name="doctors_type_status_idx",
            ),
        ]

    def __str__(self):
        return f"Doctor({self.user_id}:{self.professional_type}:{self.verification_status})"

class AppendOnlyDoctorDecisionQuerySet(models.QuerySet):
    """Bulk-mutation guard; instance guards alone are bypassed by the ORM."""

    def delete(self):
        raise ValueError("Decision history is append-only and cannot be deleted.")

    def update(self, **kwargs):
        raise ValueError("Decision history is append-only and cannot be modified.")


class DoctorVerificationDecision(models.Model):
    """APPEND-ONLY verification history for a doctor account (FR-DOC-006, BR-001).

    `Doctor` stores only the current `verification_status` plus the last
    `verified_by`/`verified_at`/`rejection_reason`. That is the right shape for
    a fast authorization check, but it is not a record of *how* the doctor got
    there: a rejected applicant who reapplies and is then approved would leave
    only the approval behind, and the earlier rejection — the reason the licence
    was doubted in the first place — would be unrecoverable.

    This table is that record. Every submission, approval, rejection, suspension
    and reinstatement is one immutable row, in order, naming the officer who
    decided and the reason they gave. C6 requires every decision to carry a
    reason and be audited; this is where the reason survives.

    `request` is PROTECT for the same reason as everywhere else in this codebase:
    history that can lose its subject is not history.
    """

    DECISION = [
        ("SUBMITTED", "SUBMITTED"),
        ("APPROVED", "APPROVED"),
        ("REJECTED", "REJECTED"),
        ("SUSPENDED", "SUSPENDED"),
        ("REINSTATED", "REINSTATED"),
        ("RESUBMITTED", "RESUBMITTED"),
        ("NOTE", "NOTE"),
    ]
    DECISIONS = [value for value, _ in DECISION]

    uid = models.UUIDField(default=uuid.uuid4, editable=False, unique=True, db_index=True)
    doctor = models.ForeignKey(
        Doctor, on_delete=models.PROTECT, related_name="verification_decisions",
    )
    actor = models.ForeignKey(
        settings.AUTH_USER_MODEL, null=True, blank=True,
        on_delete=models.SET_NULL, related_name="doctor_verification_decisions",
    )
    decision = models.CharField(max_length=16, choices=DECISION, db_index=True)
    from_status = models.CharField(max_length=16, blank=True)
    to_status = models.CharField(max_length=16, blank=True)
    reason = models.TextField(blank=True)
    details = models.JSONField(default=dict, blank=True)
    decided_at = models.DateTimeField(auto_now_add=True, db_index=True)

    class Meta:
        db_table = "doctor_verification_decisions"
        ordering = ["-decided_at", "-pk"]
        constraints = [
            models.CheckConstraint(
                condition=models.Q(decision__in=[
                    "SUBMITTED", "APPROVED", "REJECTED", "SUSPENDED",
                    "REINSTATED", "RESUBMITTED", "NOTE",
                ]),
                name="doctor_verdec_decision_ck",
            ),
        ]
        indexes = [
            models.Index(
                fields=["doctor", "-decided_at"], name="doctor_verdec_time_idx",
            ),
            models.Index(fields=["decision", "-decided_at"], name="doctor_verdec_type_idx"),
        ]

    objects = AppendOnlyDoctorDecisionQuerySet.as_manager()

    def __str__(self):
        return f"DoctorDecision({self.doctor_id}:{self.decision})"

    def save(self, *args, **kwargs):
        if self.pk is not None:
            raise ValueError(
                "DoctorVerificationDecision is append-only and cannot be modified."
            )
        return super().save(*args, **kwargs)

    def delete(self, *args, **kwargs):
        raise ValueError("DoctorVerificationDecision is append-only and cannot be deleted.")


