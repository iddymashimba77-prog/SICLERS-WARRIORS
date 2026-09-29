"""Education domain services (approved Stage 4.11).

Thin state-transition helpers so the review workflow (DRAFT -> IN_REVIEW ->
PUBLISHED/REJECTED, C12) is testable and the views never hand-roll status math.
Invalid transitions raise ``ValueError``; the view maps that to a 400.
"""

from django.utils import timezone

from notifications.services import create_notification

from . import models


def create_content(*, author, title, body, category, cover_url=""):
    return models.EducationalContent.objects.create(
        author=author, title=title, body=body,
        category=category, cover_url=cover_url or "",
        status="DRAFT",
    )


def update_content(content, *, title=None, body=None, category=None, cover_url=None):
    if title is not None:
        content.title = title
    if body is not None:
        content.body = body
    if category is not None:
        content.category = category
    if cover_url is not None:
        content.cover_url = cover_url
    content.save(
        update_fields=[
            "title", "body", "category", "cover_url", "updated_at",
        ]
    )
    return content


def submit_content(content):
    """Move an author-editable piece into the review queue (C12)."""
    if content.status not in models.SUBMITTABLE_STATUSES:
        raise ValueError("Only draft or rejected content can be submitted for review.")
    content.status = "IN_REVIEW"
    content.save(update_fields=["status", "updated_at"])
    return content


def admin_publish_content(content, *, actor):
    """One-step admin publish (DRAFT/ARCHIVED/REJECTED -> PUBLISHED).

    Mirrors the news CMS flow so an admin who authors {{content}} straight on
    the admin console can take it live without the two-step submit+review.
    Rejects publishing something already live.
    """
    if content.status == "PUBLISHED":
        raise ValueError("This content is already published.")
    now = timezone.now()
    content.status = "PUBLISHED"
    content.published_at = content.published_at or now
    content.reviewed_by = actor
    content.reviewed_at = now
    content.rejection_reason = ""
    content.save(
        update_fields=[
            "status", "published_at", "reviewed_by", "reviewed_at",
            "rejection_reason", "updated_at",
        ]
    )
    return content


def review_content(content, *, actor, decision, reason=""):
    """Approve (-> PUBLISHED) or reject (-> REJECTED). Only IN_REVIEW input."""
    if content.status != "IN_REVIEW":
        raise ValueError("Content is not pending review.")
    now = timezone.now()
    if decision == "reject":
        if not reason:
            raise ValueError("A reason is required to reject content.")
        content.status = "REJECTED"
        content.rejection_reason = reason
    else:
        content.status = "PUBLISHED"
        content.published_at = content.published_at or now
        content.rejection_reason = ""
    content.reviewed_by = actor
    content.reviewed_at = now
    content.save(
        update_fields=[
            "status", "reviewed_by", "reviewed_at",
            "rejection_reason", "published_at", "updated_at",
        ]
    )
    if content.author_id and content.author_id != actor.pk and content.status in ("PUBLISHED", "REJECTED"):
        phase = "published" if content.status == "PUBLISHED" else "needs review"
        create_notification(
            recipient=content.author,
            type_="SYSTEM",
            title="Warrior Academy update",
            body="Your submitted content was reviewed by the academy team.",
            data={"route": "education", "resource_type": "education_content"},
            related_resource_type="education_content",
            related_resource_id=str(content.uid),
            delivery_key=f"edu:{content.status.lower()}:{content.uid}",
        )
    return content