"""Community domain (approved Stage 4.10).

Source of truth:
  docs/sdlc/03-system-design/erd/community-communication-erd.md
  docs/sdlc/03-system-design/database-design.md §14 (lines 336-340)

CHECK vocabularies:
  community_posts.category : SUPPORT EDUCATION GENERAL VENTING
  community_posts.status   : PUBLISHED HIDDEN REMOVED PENDING_REVIEW
  comments.status          : PUBLISHED HIDDEN REMOVED
  reports.target_type      : POST COMMENT
  reports.status           : OPEN IN_REVIEW RESOLVED DISMISSED

Data boundary (§14): community content is fully separable from private medical
records — no medical fields live here and none may be read into it.

Moderation is hide-first (security-api-traceability §7): a reported item is
HIDDEN for review; REMOVED is the terminal moderated state. Posts are
soft-deleted via `deleted_at` (never hard-deleted) so moderation history and
audit stay intact. Traceability: FR-COM-001..005.
"""

import uuid

from django.conf import settings
from django.db import models

POST_CATEGORIES = ["SUPPORT", "EDUCATION", "GENERAL", "VENTING"]
POST_STATUSES = ["PUBLISHED", "HIDDEN", "REMOVED", "PENDING_REVIEW"]
COMMENT_STATUSES = ["PUBLISHED", "HIDDEN", "REMOVED"]
REPORT_TARGET_TYPES = ["POST", "COMMENT"]
REPORT_STATUSES = ["OPEN", "IN_REVIEW", "RESOLVED", "DISMISSED"]


class CommunityPost(models.Model):
    CATEGORY = [(value, value) for value in POST_CATEGORIES]
    STATUS = [(value, value) for value in POST_STATUSES]

    uid = models.UUIDField(default=uuid.uuid4, editable=False, unique=True, db_index=True)
    author = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.PROTECT, related_name="community_posts",
    )
    title = models.CharField(max_length=200, blank=True)
    content = models.TextField()
    category = models.CharField(max_length=10, choices=CATEGORY, default="GENERAL")
    status = models.CharField(max_length=14, choices=STATUS, default="PUBLISHED", db_index=True)
    moderated_by = models.ForeignKey(
        settings.AUTH_USER_MODEL, null=True, blank=True,
        on_delete=models.SET_NULL, related_name="moderated_community_posts",
    )
    moderated_at = models.DateTimeField(null=True, blank=True)
    moderation_reason = models.TextField(blank=True)
    created_at = models.DateTimeField(auto_now_add=True, db_index=True)
    updated_at = models.DateTimeField(auto_now=True)
    deleted_at = models.DateTimeField(null=True, blank=True)

    class Meta:
        db_table = "community_posts"
        ordering = ["-created_at"]
        constraints = [
            models.CheckConstraint(
                condition=models.Q(category__in=POST_CATEGORIES),
                name="community_posts_category_ck",
            ),
            models.CheckConstraint(
                condition=models.Q(status__in=POST_STATUSES),
                name="community_posts_status_ck",
            ),
        ]
        indexes = [
            models.Index(fields=["status", "-created_at"], name="community_posts_status_idx"),
            models.Index(fields=["author", "-created_at"], name="community_posts_author_idx"),
            models.Index(fields=["category", "-created_at"], name="community_posts_category_idx"),
        ]

    def __str__(self):
        return f"post:{self.uid}"


class Comment(models.Model):
    STATUS = [(value, value) for value in COMMENT_STATUSES]

    post = models.ForeignKey(
        CommunityPost, on_delete=models.CASCADE, related_name="comments",
    )
    author = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.PROTECT, related_name="community_comments",
    )
    content = models.TextField()
    status = models.CharField(max_length=12, choices=STATUS, default="PUBLISHED", db_index=True)
    created_at = models.DateTimeField(auto_now_add=True, db_index=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        db_table = "comments"
        ordering = ["created_at"]
        constraints = [
            models.CheckConstraint(
                condition=models.Q(status__in=COMMENT_STATUSES),
                name="comments_status_ck",
            ),
        ]
        indexes = [
            models.Index(fields=["post", "created_at"], name="comments_post_ts_idx"),
        ]

    def __str__(self):
        return f"comment:{self.pk}:post:{self.post_id}"


class Reaction(models.Model):
    post = models.ForeignKey(
        CommunityPost, on_delete=models.CASCADE, related_name="reactions",
    )
    user = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.PROTECT, related_name="community_reactions",
    )
    reaction_type = models.CharField(max_length=20, default="LIKE")
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        db_table = "reactions"
        ordering = ["-created_at"]
        constraints = [
            models.UniqueConstraint(
                fields=["post", "user", "reaction_type"],
                name="reactions_post_user_type_uk",
            ),
        ]
        indexes = [
            models.Index(fields=["post", "reaction_type"], name="reactions_post_type_idx"),
        ]

    def __str__(self):
        return f"reaction:{self.reaction_type}:post:{self.post_id}"


class Report(models.Model):
    TARGET_TYPE = [(value, value) for value in REPORT_TARGET_TYPES]
    STATUS = [(value, value) for value in REPORT_STATUSES]

    reporter = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.PROTECT, related_name="community_reports",
    )
    target_type = models.CharField(max_length=8, choices=TARGET_TYPE)
    target_id = models.PositiveBigIntegerField()
    reason = models.TextField()
    status = models.CharField(max_length=12, choices=STATUS, default="OPEN", db_index=True)
    reviewed_by = models.ForeignKey(
        settings.AUTH_USER_MODEL, null=True, blank=True,
        on_delete=models.SET_NULL, related_name="community_reports_reviewed",
    )
    review_notes = models.TextField(blank=True)
    created_at = models.DateTimeField(auto_now_add=True, db_index=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        db_table = "reports"
        ordering = ["-created_at"]
        constraints = [
            models.CheckConstraint(
                condition=models.Q(target_type__in=REPORT_TARGET_TYPES),
                name="reports_target_type_ck",
            ),
            models.CheckConstraint(
                condition=models.Q(status__in=REPORT_STATUSES),
                name="reports_status_ck",
            ),
            models.UniqueConstraint(
                fields=["reporter", "target_type", "target_id"],
                name="reports_reporter_target_uk",
            ),
        ]
        indexes = [
            models.Index(fields=["status", "-created_at"], name="reports_status_ts_idx"),
            models.Index(fields=["target_type", "target_id"], name="reports_target_idx"),
        ]

    def __str__(self):
        return f"report:{self.pk}:{self.target_type}:{self.target_id}"
