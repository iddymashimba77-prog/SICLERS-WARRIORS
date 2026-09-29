"""Community domain services (approved Stage 4.10).

Encapsulates moderation state transitions and report resolution so views stay
thin and the rules are testable. Hide-first moderation: a report action of
``HIDE`` hides the target for human review; ``REMOVE`` is terminal. Both stamp
``moderated_by`` / ``moderated_at`` / ``moderation_reason``.
"""

from django.utils import timezone

from notifications.services import create_notification

from . import models


def create_post(*, author, title="", content, category="GENERAL"):
    return models.CommunityPost.objects.create(
        author=author, title=title, content=content, category=category,
        status="PUBLISHED",
    )


def update_post(post, *, title=None, content=None, category=None):
    if title is not None:
        post.title = title
    if content is not None:
        post.content = content
    if category is not None:
        post.category = category
    post.save(update_fields=["title", "content", "category", "updated_at"])
    return post


def soft_delete_post(post):
    """Author deletion — soft delete so moderation/audit history is preserved."""
    post.deleted_at = timezone.now()
    post.status = "REMOVED"
    post.save(update_fields=["deleted_at", "status", "updated_at"])
    return post


def moderate_post(post, *, actor, action, reason=""):
    """Apply a moderator decision to a post (HIDE or REMOVE)."""
    if action not in ("HIDE", "REMOVE"):
        raise ValueError("Unsupported moderation action.")
    post.status = "HIDDEN" if action == "HIDE" else "REMOVED"
    post.moderated_by = actor
    post.moderated_at = timezone.now()
    post.moderation_reason = reason or post.moderation_reason
    post.save(
        update_fields=["status", "moderated_by", "moderated_at", "moderation_reason", "updated_at"]
    )
    return post


def moderate_comment(comment, *, actor, action, reason=""):
    if action not in ("HIDE", "REMOVE"):
        raise ValueError("Unsupported moderation action.")
    comment.status = "HIDDEN" if action == "HIDE" else "REMOVED"
    comment.save(update_fields=["status", "updated_at"])
    return comment


def set_reaction(*, post, user, reaction_type="LIKE"):
    """Toggle semantics live in the view; this creates the reaction row."""
    reaction, created = models.Reaction.objects.get_or_create(
        post=post, user=user, reaction_type=reaction_type,
    )
    if created and post.author_id and post.author_id != user.pk:
        create_notification(
            recipient=post.author,
            type_="COMMUNITY",
            title="New reaction on your post",
            body="Someone reacted to your community post.",
            related_resource_type="community_post",
            related_resource_id=str(post.uid),
            delivery_key=f"community:reaction:{reaction.pk}",
        )
    return reaction


def clear_reaction(*, post, user, reaction_type="LIKE"):
    return models.Reaction.objects.filter(
        post=post, user=user, reaction_type=reaction_type,
    ).delete()


def create_comment(*, post, author, content):
    comment = models.Comment.objects.create(post=post, author=author, content=content, status="PUBLISHED")
    if post.author_id and post.author_id != author.pk:
        create_notification(
            recipient=post.author,
            type_="COMMUNITY",
            title="New reply",
            body="Someone replied to your community post.",
            related_resource_type="community_post",
            related_resource_id=str(post.uid),
            delivery_key=f"community:comment:{comment.pk}",
        )
    return comment


def update_comment(comment, *, content):
    comment.content = content
    comment.save(update_fields=["content", "updated_at"])
    return comment


def soft_delete_comment(comment):
    comment.status = "REMOVED"
    comment.save(update_fields=["status", "updated_at"])
    return comment


def _target_object(target_type, target_id):
    if target_type == "POST":
        return models.CommunityPost.objects.filter(pk=target_id).first()
    if target_type == "COMMENT":
        return models.Comment.objects.filter(pk=target_id).first()
    return None


def create_report(*, reporter, target_type, target_id, reason):
    """Create a report; the unique (reporter, target) constraint blocks duplicates."""
    return models.Report.objects.create(
        reporter=reporter,
        target_type=target_type,
        target_id=target_id,
        reason=reason,
        status="OPEN",
    )


def resolve_report(report, *, actor, status, review_notes="", action="NONE"):
    """Close a report, optionally applying a hide-first moderation action."""
    if status not in ("RESOLVED", "DISMISSED"):
        raise ValueError("Unsupported report status.")
    if action in ("HIDE", "REMOVE"):
        target = _target_object(report.target_type, report.target_id)
        if target is not None:
            if report.target_type == "POST":
                moderate_post(target, actor=actor, action=action, reason=review_notes)
            else:
                moderate_comment(target, actor=actor, action=action, reason=review_notes)
    report.status = status
    report.reviewed_by = actor
    report.review_notes = review_notes
    report.save(update_fields=["status", "reviewed_by", "review_notes", "updated_at"])
    return report
