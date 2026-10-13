"""Content CMS domain (public home § News + admin Top Ticker).

Approved scope (final public-facing milestone):
  * ``NewsArticle`` — the dynamic "Latest News / Featured News / View All"
    surface of the public landing page, written by admins holding
    ``content.news.manage`` and read publicly (PUBLISHED rows only).
  * ``TickerAnnouncement`` — the admin-controlled top ticker strip; public
    endpoint serves only active + time-effective announcements.

Follows the project's content conventions (education §4.11): uid-routed
resources, an explicit publication lifecycle, least-privilege admin codes,
full audit traceability, and a lean public payload (no body on list rows).

News lifecycle (DB enum)::

    DRAFT -> PUBLISHED -> ARCHIVED
              ^   |
              |   +---- unpublish -> DRAFT
              +--------- re-publish (DRAFT/ARCHIVED -> PUBLISHED)

Featured news is exactly the published rows an admin flags; the public
"featured feed" is ``status=PUBLISHED AND featured=True``, newest first.

Data boundary: news mirrors the public feed openly, but is written ONLY by
admins; the author projection is uid + display name (community convention).
Ticker uses the same surface with ``content.ticker.manage``.
"""

import uuid

from django.conf import settings
from django.db import models

NEWS_STATUSES = ["DRAFT", "PUBLISHED", "ARCHIVED"]
# Editors may fix a live article in place (the fix goes live immediately) as
# well as drafts and archived pieces — blocking PUBLISHED made the admin "Edit"
# button useless on the very articles that matter most.
EDITABLE_STATUSES = ["DRAFT", "ARCHIVED", "PUBLISHED"]

NEWS_CATEGORIES = [
    ("HEALTH", "Health"),
    ("BLOOD", "Blood"),
    ("COMMUNITY", "Community"),
    ("EDUCATION", "Education"),
    ("EVENTS", "Events"),
    ("ANNOUNCEMENTS", "Announcements"),
    ("FUNDRAISING", "Fundraising"),
]

TICKER_TYPES = [
    ("INFO", "Information"),
    ("URGENT", "Urgent"),
    ("BLOOD", "Blood"),
    ("EVENT", "Event"),
    ("DONATION", "Donation"),
    ("SUCCESS", "Success"),
]


class NewsArticle(models.Model):
    STATUS = [(value, value) for value in NEWS_STATUSES]

    uid = models.UUIDField(default=uuid.uuid4, editable=False, unique=True, db_index=True)
    title = models.CharField(max_length=200)
    category = models.CharField(
        max_length=20, choices=NEWS_CATEGORIES, db_index=True,
    )
    excerpt = models.TextField(blank=True)
    body = models.TextField()
    cover_url = models.TextField(blank=True)
    cover_alt = models.CharField(max_length=300, blank=True)
    tags = models.JSONField(default=list, blank=True)
    featured = models.BooleanField(default=False, db_index=True)
    # Pinning is an explicit editorial override that floats a published article
    # to the top of the public list regardless of publish date (§17/§18).
    # Separate from `featured` because a pin has an actor and a timestamp.
    pinned = models.BooleanField(default=False, db_index=True)
    pinned_at = models.DateTimeField(null=True, blank=True)
    pinned_by = models.ForeignKey(
        settings.AUTH_USER_MODEL, null=True, blank=True, on_delete=models.SET_NULL,
        related_name="pinned_news_articles",
    )
    # Soft delete: editorial content is never destroyed from the database, so a
    # mistaken removal is recoverable and the audit trail keeps a referent.
    deleted_at = models.DateTimeField(null=True, blank=True, db_index=True)
    deleted_by = models.ForeignKey(
        settings.AUTH_USER_MODEL, null=True, blank=True, on_delete=models.SET_NULL,
        related_name="deleted_news_articles",
    )
    author = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.PROTECT,
        related_name="news_articles",
    )
    status = models.CharField(
        max_length=12, choices=STATUS, default="DRAFT", db_index=True,
    )
    published_at = models.DateTimeField(null=True, blank=True, db_index=True)
    created_at = models.DateTimeField(auto_now_add=True, db_index=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        db_table = "news_articles"
        ordering = ["-pinned", "-published_at", "-id"]

    def __str__(self):
        return self.title

    def category_label(self):
        return dict(NEWS_CATEGORIES).get(self.category, self.category)


class TickerAnnouncement(models.Model):
    uid = models.UUIDField(default=uuid.uuid4, editable=False, unique=True, db_index=True)
    message = models.CharField(max_length=240)
    announcement_type = models.CharField(
        max_length=12, choices=TICKER_TYPES, default="INFO", db_index=True,
    )
    link_url = models.TextField(blank=True)
    is_active = models.BooleanField(default=True, db_index=True)
    priority = models.IntegerField(default=0)
    start_at = models.DateTimeField(null=True, blank=True)
    end_at = models.DateTimeField(null=True, blank=True)
    # Optional announcement artwork. The file field stores the re-encoded JPEG;
    # `image_url` in the payloads is derived at render time (core.media) so it
    # always points at the right origin. `image_alt` is editable admin metadata.
    image = models.ImageField(upload_to="content/ticker/", blank=True)
    image_alt = models.CharField(max_length=300, blank=True)
    created_by = models.ForeignKey(
        settings.AUTH_USER_MODEL, null=True, blank=True, on_delete=models.SET_NULL,
        related_name="ticker_announcements",
    )
    created_at = models.DateTimeField(auto_now_add=True, db_index=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        db_table = "ticker_announcements"
        ordering = ["-priority", "-created_at"]

    def __str__(self):
        return self.message

    def announcement_type_label(self):
        return dict(TICKER_TYPES).get(self.announcement_type, self.announcement_type)

    def is_effective(self, moment):
        """Active AND inside the optional start/end window."""
        if not self.is_active:
            return False
        if self.start_at and self.start_at > moment:
            return False
        if self.end_at and self.end_at < moment:
            return False
        return True