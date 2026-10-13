"""Education domain (approved Stage 4.11).

Source of truth:
  docs/sdlc/03-system-design/database-design.md §17 (lines 378-385)
  docs/sdlc/03-system-design/erd/community-communication-erd.md (lines 87-108)
  docs/sdlc/03-system-design/api-design.md §20 / api-endpoint-matrix.md §18

Approved two-level hierarchy only: ``education_categories`` (1) →
``educational_content`` (N). The approved design does NOT define courses,
lessons, quizzes, certificates or premium tiers — those are out of scope and
must not be invented here.

Publishing lifecycle (DB enum, database-design §22):
  DRAFT -> IN_REVIEW -> PUBLISHED -> ARCHIVED
                         |-> REJECTED (sent back to author for revision)

Medical safety (§ 4.11-3): educational content is information, never diagnosis
or prescription. The API never exposes drafts publicly and the mobile UI labels
published content as educational material, not medical advice.

Data boundary: author projection is uid + display name only; no email, phone or
medical data lives on this surface. Content is editable by its author while it
is a draft (or rejected/archived); once published, it is read-only outside the
admin review surface.
"""

import uuid

from django.conf import settings
from django.db import models

CONTENT_STATUSES = ["DRAFT", "IN_REVIEW", "PUBLISHED", "ARCHIVED", "REJECTED"]

# Statuses in which the author may still edit their submission. PUBLISHED and
# IN_REVIEW are locked; changes to a published piece require review again.
EDITABLE_STATUSES = ["DRAFT", "REJECTED", "ARCHIVED"]
SUBMITTABLE_STATUSES = ["DRAFT", "REJECTED"]


class EducationCategory(models.Model):
    code = models.CharField(max_length=60, unique=True)
    name = models.CharField(max_length=120)
    sort_order = models.IntegerField(default=0)

    class Meta:
        db_table = "education_categories"
        ordering = ["sort_order", "name"]

    def __str__(self):
        return f"{self.code}:{self.name}"


class EducationalContent(models.Model):
    # Values reflect the approved emoji/status namespaces in community/education
    # ERDs. ``status`` is the authoritative publication state (never the view).
    STATUS = [(value, value) for value in CONTENT_STATUSES]

    uid = models.UUIDField(default=uuid.uuid4, editable=False, unique=True, db_index=True)
    title = models.TextField()
    body = models.TextField()
    category = models.ForeignKey(
        EducationCategory, on_delete=models.PROTECT, related_name="contents",
    )
    author = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.PROTECT, related_name="educational_contents",
    )
    status = models.CharField(max_length=12, choices=STATUS, default="DRAFT", db_index=True)
    reviewed_by = models.ForeignKey(
        settings.AUTH_USER_MODEL, null=True, blank=True,
        on_delete=models.SET_NULL, related_name="reviewed_educational_contents",
    )
    reviewed_at = models.DateTimeField(null=True, blank=True)
    rejection_reason = models.TextField(blank=True)
    cover_url = models.TextField(blank=True)
    # Optional downloadable attachment (PDF/print handout, slide deck, image).
    # Stored under MEDIA_ROOT and served by the deployment's media/CDN rule; the
    # file itself is validated (type + size + magic bytes) at upload time by
    # ``education.services.validate_document_upload`` — never trusted by name.
    document_file = models.FileField(
        upload_to="education/documents/", blank=True, max_length=300,
    )
    document_name = models.CharField(max_length=255, blank=True)
    document_content_type = models.CharField(max_length=120, blank=True)
    document_size = models.PositiveIntegerField(null=True, blank=True)
    document_uploaded_at = models.DateTimeField(null=True, blank=True)
    document_uploaded_by = models.ForeignKey(
        settings.AUTH_USER_MODEL, null=True, blank=True, on_delete=models.SET_NULL,
        related_name="uploaded_education_documents",
    )
    published_at = models.DateTimeField(null=True, blank=True, db_index=True)
    created_at = models.DateTimeField(auto_now_add=True, db_index=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        db_table = "educational_content"
        ordering = ["-created_at"]
        constraints = [
            models.CheckConstraint(
                condition=models.Q(status__in=CONTENT_STATUSES),
                name="educational_content_status_ck",
            ),
        ]
        indexes = [
            models.Index(
                fields=["status", "-published_at"], name="edu_content_status_pub_idx",
            ),
            models.Index(
                fields=["category", "-published_at"], name="edu_content_category_pub_idx",
            ),
            models.Index(
                fields=["author", "-created_at"], name="edu_content_author_ts_idx",
            ),
            # Stage 4.18: the public feed filters (status=PUBLISHED [+ category])
            # then sorts by -published_at; one composite covers both.
            models.Index(
                fields=["status", "category", "-published_at"], name="edu_content_status_cat_pub_idx",
            ),
        ]

    def __str__(self):
        return f"content:{self.uid}"