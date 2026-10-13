"""Content CMS services — thin, tested state transitions.

Views never hand-roll status/flags math; invalid transitions raise
``ValueError`` which the view maps to a 400. Sanitisation mirrors education
(``community.sanitizers.sanitize_html``) and author projection mirrors
community's uid + display_name.
"""

from django.utils import timezone

from . import models


def _clean(value, max_length):
    from community.sanitizers import sanitize_html
    return sanitize_html(value or "", max_length=max_length)


# --------------------------------------------------------------- news articles

def create_news(*, author, title, category, body, excerpt="", cover_url="",
                cover_alt="", tags=None):
    return models.NewsArticle.objects.create(
        author=author,
        title=_clean(title, 200),
        category=category,
        body=_clean(body, 50000),
        excerpt=_clean(excerpt, 500) or None,
        cover_url=_clean(cover_url, 500),
        cover_alt=_clean(cover_alt, 300),
        tags=tags or [],
        status="DRAFT",
    )


def update_news(article, *, title=None, category=None, body=None, excerpt=None,
                cover_url=None, cover_alt=None, tags=None):
    fields = []
    if title is not None:
        article.title, fields = _clean(title, 200), [*fields, "title"]
    if body is not None:
        article.body, fields = _clean(body, 50000), [*fields, "body"]
    if excerpt is not None:
        article.excerpt, fields = _clean(excerpt, 500), [*fields, "excerpt"]
    if cover_url is not None:
        article.cover_url, fields = _clean(cover_url, 500), [*fields, "cover_url"]
    if cover_alt is not None:
        article.cover_alt, fields = _clean(cover_alt, 300), [*fields, "cover_alt"]
    if tags is not None:
        article.tags, fields = list(tags), [*fields, "tags"]
    if category is not None:
        article.category, fields = category, [*fields, "category"]
    if fields:
        article.save(update_fields=[*set(fields), "updated_at"])
    return article


def publish_news(article):
    if article.status == "PUBLISHED":
        raise ValueError("This article is already published.")
    article.status = "PUBLISHED"
    article.published_at = timezone.now()
    article.save(update_fields=["status", "published_at", "updated_at"])
    return article


def unpublish_news(article):
    if article.status != "PUBLISHED":
        raise ValueError("Only published news can be unpublished.")
    article.status = "DRAFT"
    article.published_at = None
    article.featured = False
    # A pin is a promise to the public; withdrawing the article withdraws it.
    article.pinned = False
    article.pinned_at = None
    article.pinned_by = None
    article.save(update_fields=[
        "status", "published_at", "featured", "pinned", "pinned_at", "pinned_by", "updated_at",
    ])
    return article


def archive_news(article):
    if article.status == "ARCHIVED":
        raise ValueError("This article is already archived.")
    article.status = "ARCHIVED"
    article.featured = False
    article.pinned = False
    article.pinned_at = None
    article.pinned_by = None
    article.save(update_fields=[
        "status", "featured", "pinned", "pinned_at", "pinned_by", "updated_at",
    ])
    return article


def set_featured(article, *, featured):
    if featured and article.status != "PUBLISHED":
        raise ValueError("Only published news can be featured.")
    article.featured = bool(featured)
    article.save(update_fields=["featured", "updated_at"])
    return article


def set_pinned(article, *, pinned, actor=None):
    """Pin/unpin a published article (§17/§18).

    Pinning is meaningless for anything the public cannot read, so it is
    refused outside PUBLISHED. Unpublishing or soft-deleting clears the pin
    (see ``unpublish_news``/``soft_delete_news``) so a hidden article can
    never sit at the top of the public list.
    """
    pinned = bool(pinned)
    if pinned:
        if article.status != "PUBLISHED":
            raise ValueError("Only published news can be pinned.")
        if article.deleted_at is not None:
            raise ValueError("Restore the article before pinning it.")
    article.pinned = pinned
    article.pinned_at = timezone.now() if pinned else None
    article.pinned_by = actor if pinned else None
    article.save(update_fields=["pinned", "pinned_at", "pinned_by", "updated_at"])
    return article


def soft_delete_news(article, *, actor=None, reason=""):
    """Remove an article from every public surface without destroying it.

    Production editorial content is never hard-deleted (§18): the row is marked
    deleted, archived if it was live, and unpinned, so it disappears from the
    public API immediately while remaining restorable and auditable.
    """
    if article.deleted_at is not None:
        return article
    article.deleted_at = timezone.now()
    article.deleted_by = actor
    if article.status == "PUBLISHED":
        article.status = "ARCHIVED"
    article.pinned = False
    article.pinned_at = None
    article.pinned_by = None
    article.save(update_fields=[
        "deleted_at", "deleted_by", "status", "pinned", "pinned_at", "pinned_by", "updated_at",
    ])
    return article


def restore_news(article, *, actor=None):
    """Undo a soft delete, returning the article to ARCHIVED for review."""
    if article.deleted_at is None:
        return article
    article.deleted_at = None
    article.deleted_by = None
    if article.status == "ARCHIVED":
        article.status = "DRAFT"
    article.save(update_fields=["deleted_at", "deleted_by", "status", "updated_at"])
    return article


# ------------------------------------------------------- ticker announcements

def _validate_window(start_at, end_at):
    if start_at and end_at and end_at < start_at:
        raise ValueError("End date must be on or after the start date.")


def create_ticker(*, created_by, message, announcement_type="INFO", link_url="",
                  is_active=True, priority=0, start_at=None, end_at=None):
    _validate_window(start_at, end_at)
    return models.TickerAnnouncement.objects.create(
        created_by=created_by,
        message=_clean(message, 240),
        announcement_type=announcement_type,
        link_url=_clean(link_url, 500),
        is_active=bool(is_active),
        priority=priority or 0,
        start_at=start_at,
        end_at=end_at,
    )


def update_ticker(ann, *, message=None, announcement_type=None, link_url=None,
                  is_active=None, priority=None, start_at=None, end_at=None):
    _validate_window(
        start_at if start_at is not None else ann.start_at,
        end_at if end_at is not None else ann.end_at,
    )
    fields = []
    if message is not None:
        ann.message, fields = _clean(message, 240), [*fields, "message"]
    if announcement_type is not None:
        ann.announcement_type, fields = announcement_type, [*fields, "announcement_type"]
    if link_url is not None:
        ann.link_url, fields = _clean(link_url, 500), [*fields, "link_url"]
    if is_active is not None:
        ann.is_active, fields = bool(is_active), [*fields, "is_active"]
    if priority is not None:
        ann.priority, fields = priority, [*fields, "priority"]
    if start_at is not None:
        ann.start_at, fields = start_at, [*fields, "start_at"]
    if end_at is not None:
        ann.end_at, fields = end_at, [*fields, "end_at"]
    if fields:
        ann.save(update_fields=[*set(fields), "updated_at"])
    return ann


def set_ticker_active(ann, *, active):
    ann.is_active = bool(active)
    ann.save(update_fields=["is_active", "updated_at"])
    return ann