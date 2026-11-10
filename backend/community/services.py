"""Community domain services (approved Stage 4.10, forum extension).

Encapsulates moderation state transitions, reply threading and forum
notification fan-out so views stay thin and the rules are testable. Hide-first
moderation: a report action of ``HIDE`` hides the target for human review;
``REMOVE`` is terminal. Posts are soft-deleted via ``deleted_at`` so moderation
history and audit stay intact.
"""

from django.utils import timezone

from notifications.services import create_notification

from . import models

MAX_COMMENT_DEPTH = 5


def _forum_data(post, *, forum_type, comment=None):
    category = getattr(post, "forum_category", None)
    return {
        "route": "community",
        "forum_type": forum_type,
        "post_uid": str(post.uid),
        "post_id": post.pk,
        "comment_id": comment.pk if comment is not None else None,
        "category_slug": category.slug if category is not None else None,
    }


def _notify_recipient(*, recipient, post, title, body, delivery_key, forum_type, comment=None):
    """Create one forum notification, never for an admin-level recipient."""
    if recipient is None or getattr(recipient, "is_admin", False):
        return None
    return create_notification(
        recipient=recipient,
        type_="COMMUNITY",
        title=title,
        body=body,
        related_resource_type="community_post",
        related_resource_id=str(post.uid),
        delivery_key=delivery_key,
        data=_forum_data(post, forum_type=forum_type, comment=comment),
    )


def create_post(*, author, title="", content, category="GENERAL", forum_category=None):
    return models.CommunityPost.objects.create(
        author=author,
        title=title,
        content=content,
        category=category,
        forum_category=forum_category,
        status="PUBLISHED",
        last_activity_at=timezone.now(),
    )


def update_post(post, *, title=None, content=None, category=None, forum_category=None):
    changed = False
    if title is not None and title != post.title:
        post.title = title
        changed = True
    if content is not None and content != post.content:
        post.content = content
        changed = True
    if category is not None and category != post.category:
        post.category = category
        changed = True
    if forum_category is not None and forum_category != post.forum_category:
        post.forum_category = forum_category
        changed = True
    if changed:
        post.is_edited = True
        post.save(
            update_fields=[
                "title", "content", "category", "forum_category",
                "is_edited", "updated_at",
            ]
        )
    return post


def set_post_flags(post, *, is_pinned=None, is_locked=None):
    fields = []
    if is_pinned is not None:
        post.is_pinned = bool(is_pinned)
        fields.append("is_pinned")
    if is_locked is not None:
        post.is_locked = bool(is_locked)
        fields.append("is_locked")
    if fields:
        post.save(update_fields=[*fields, "updated_at"])
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
        _notify_recipient(
            recipient=post.author,
            post=post,
            title="New support on your post",
            body="Someone supported your community post.",
            delivery_key=f"community:reaction:{reaction.pk}:{post.author_id}",
            forum_type="POST_REACTION",
        )
    return reaction


def clear_reaction(*, post, user, reaction_type="LIKE"):
    return models.Reaction.objects.filter(
        post=post, user=user, reaction_type=reaction_type,
    ).delete()


def create_comment(*, post, author, content, parent=None):
    depth = 1
    if parent is not None:
        depth = min(parent.depth + 1, MAX_COMMENT_DEPTH)
    comment = models.Comment.objects.create(
        post=post,
        parent=parent,
        author=author,
        content=content,
        status="PUBLISHED",
        depth=depth,
    )
    post.last_activity_at = comment.created_at
    post.save(update_fields=["last_activity_at"])
    _fan_out_comment_notifications(post=post, comment=comment, parent=parent)
    return comment


def _fan_out_comment_notifications(*, post, comment, parent):
    """Notify the author, the replied-to member and prior participants once.

    The body never repeats community content (non-PHI metadata only). A single
    recipient receives at most one notification per comment via the unique
    delivery key, even when they are both the post author and a participant.
    """
    recipients = {}

    if post.author_id and post.author_id != comment.author_id:
        recipients[post.author_id] = (
            "COMMENT_REPLY" if parent is not None else "POST_COMMENT",
            "New reply to your post" if parent is not None else "New comment on your post",
        )

    if parent is not None and parent.author_id and parent.author_id != comment.author_id:
        recipients.setdefault(
            parent.author_id,
            ("COMMENT_REPLY", "New reply to your comment"),
        )

    participant_ids = (
        models.Comment.objects.filter(post=post, status="PUBLISHED")
        .exclude(author_id=comment.author_id)
        .values_list("author_id", flat=True)
        .distinct()
    )
    for recipient_id in participant_ids:
        recipients.setdefault(
            recipient_id,
            ("POST_ACTIVITY", "New activity in a discussion you joined"),
        )

    for recipient_id, (forum_type, title) in recipients.items():
        recipient = post.author if recipient_id == post.author_id else None
        if recipient is None:
            from accounts.models import User

            recipient = User.objects.filter(pk=recipient_id).first()
        _notify_recipient(
            recipient=recipient,
            post=post,
            title=title,
            body="Open the community forum to read the latest activity.",
            delivery_key=f"community:comment:{comment.pk}:{recipient_id}",
            forum_type=forum_type,
            comment=comment,
        )


def update_comment(comment, *, content):
    if content != comment.content:
        comment.content = content
        comment.is_edited = True
    comment.save(update_fields=["content", "is_edited", "updated_at"])
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
