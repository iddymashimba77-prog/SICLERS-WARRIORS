"""Chat domain services (Stage 4.10).

Conversation creation is restricted to DOCTOR_PATIENT in v1 (only DOCTOR,
HEALTHCARE_STAFF and PATIENT hold ``chat.start``; group/peer creation has no
approved grant). The patient-initiated path enforces C13b — the partner must be
a verified doctor — and every message/read/leave path enforces C13 membership.
"""

from django.db import transaction
from django.utils import timezone

from notifications.services import create_notification

from . import models


def _role_for(user) -> str:
    if user.is_patient:
        return "PATIENT"
    if user._has_active_role("DOCTOR"):
        return "DOCTOR"
    if user._has_active_role("HEALTHCARE_STAFF"):
        return "STAFF"
    return "MEMBER"


@transaction.atomic
def create_conversation(*, creator, partner, type_="DOCTOR_PATIENT"):
    conversation = models.Conversation.objects.create(
        type=type_, created_by=creator, status="ACTIVE",
    )
    models.ConversationParticipant.objects.create(
        conversation=conversation, user=creator, role_in_chat=_role_for(creator), status="ACTIVE",
    )
    models.ConversationParticipant.objects.create(
        conversation=conversation, user=partner, role_in_chat=_role_for(partner),
        status="ACTIVE", invited_by=creator,
    )
    # Non-PHI, consent-safe signal only (no message type is approved, so message
    # content is never pushed — unread counts surface in-chat instead).
    if partner.pk != creator.pk:
        create_notification(
            recipient=partner,
            type_="SYSTEM",
            title="New conversation",
            body="A new conversation was started with you.",
            data={"route": "messages", "resource_type": "conversation"},
            related_resource_type="conversation",
            related_resource_id=str(conversation.uid),
            delivery_key=f"chat:conv:{conversation.uid}:{partner.pk}",
        )
    return conversation


@transaction.atomic
def send_message(*, conversation, sender, content, message_type="TEXT"):
    message = models.Message.objects.create(
        conversation=conversation, sender=sender, content=content,
        message_type=message_type, status="SENT",
    )
    conversation.last_message_at = message.created_at
    conversation.save(update_fields=["last_message_at", "updated_at"])
    return message


@transaction.atomic
def delete_message(message):
    """Own-view tombstone: mask the body, keep the row for ordering/audit."""
    message.deleted_at = timezone.now()
    message.status = "DELETED"
    message.content = ""
    message.save(update_fields=["deleted_at", "status", "content"])
    return message


@transaction.atomic
def mark_read(*, conversation, reader):
    updated = (
        conversation.messages.filter(deleted_at__isnull=True)
        .exclude(sender=reader)
        .exclude(status="READ")
        .update(status="READ")
    )
    return updated


@transaction.atomic
def leave_conversation(*, conversation, user):
    participant = conversation.participants.filter(user=user).first()
    if participant is None:
        return None
    participant.status = "LEFT"
    participant.save(update_fields=["status"])
    if not conversation.participants.filter(status="ACTIVE").exists():
        conversation.status = "CLOSED"
        conversation.save(update_fields=["status", "updated_at"])
    return participant


@transaction.atomic
def add_participant(*, conversation, user, invited_by, role_in_chat="MEMBER"):
    participant, _ = models.ConversationParticipant.objects.get_or_create(
        conversation=conversation,
        user=user,
        defaults={"role_in_chat": role_in_chat, "status": "ACTIVE", "invited_by": invited_by},
    )
    if participant.status != "ACTIVE":
        participant.status = "ACTIVE"
        participant.invited_by = invited_by
        participant.save(update_fields=["status", "invited_by"])
    return participant


def record_decision(
    doctor, *, decision: str, actor=None, reason: str = "",
    details=None, from_status: str = "", to_status: str = "",
):
    """Append one immutable verification decision row for a doctor (FR-DOC-006).

    C6 requires every verification decision to carry a reason and be audited;
    this is the durable record of both. Called from the submit, resubmit,
    verify, suspend and reinstate paths so the trail covers every state the
    doctor has ever been in, not only the current one.
    """
    return models.DoctorVerificationDecision.objects.create(
        doctor=doctor,
        actor=actor,
        decision=decision,
        from_status=from_status or "",
        to_status=to_status or doctor.verification_status,
        reason=(reason or "")[:2000],
        details=dict(details or {}),
    )
