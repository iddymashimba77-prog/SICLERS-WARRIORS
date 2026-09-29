"""Education serializers (approved Stage 4.11).

Deny-by-default data boundary: the public surface exposes only publication
metadata (category, author brief, status, dates). Reviewer identity, rejection
reasons and other workflow internals are admin-only. Author projection reuses
the community ``uid + display_name`` convention (no email/phone/PHI).
"""

from rest_framework import serializers

from community.serializers import display_name
from community.sanitizers import sanitize_html

from . import models

TITLE_MAX = 200
BODY_MAX = 50000
COVER_URL_MAX = 500
REASON_MAX = 500


class EducationCategorySerializer(serializers.ModelSerializer):
    class Meta:
        model = models.EducationCategory
        fields = ["id", "code", "name", "sort_order"]
        read_only_fields = fields


class ContentAuthorSerializer(serializers.Serializer):
    uid = serializers.UUIDField(read_only=True)
    display_name = serializers.SerializerMethodField()

    def get_display_name(self, obj) -> str:
        return display_name(obj)


class EducationalContentSerializer(serializers.ModelSerializer):
    category = EducationCategorySerializer(read_only=True)
    author = ContentAuthorSerializer(read_only=True)
    is_author = serializers.SerializerMethodField()

    class Meta:
        model = models.EducationalContent
        fields = [
            "id", "uid", "title", "body", "category", "author", "status",
            "cover_url", "published_at", "created_at", "updated_at", "is_author",
        ]
        read_only_fields = fields

    def get_is_author(self, obj) -> bool:
        request = self.context.get("request")
        return bool(request and request.user.is_authenticated and obj.author_id == request.user.pk)


class EducationalContentListSerializer(serializers.ModelSerializer):
    """Lean feed projection (Stage 4.18 — NFR-PERF-002).

    The list endpoint must not stream the full editorial ``body`` (up to 50 kB
    of sanitized HTML) for every row; the list carries publication metadata
    only and the detail endpoint still returns the full article.
    """

    category = EducationCategorySerializer(read_only=True)
    author = ContentAuthorSerializer(read_only=True)
    is_author = serializers.SerializerMethodField()

    class Meta:
        model = models.EducationalContent
        fields = [
            "id", "uid", "title", "category", "author", "status",
            "cover_url", "published_at", "created_at", "updated_at", "is_author",
        ]
        read_only_fields = fields

    def get_is_author(self, obj) -> bool:
        request = self.context.get("request")
        return bool(request and request.user.is_authenticated and obj.author_id == request.user.pk)


class AdminEducationalContentSerializer(EducationalContentSerializer):
    """Moderator projection — adds the locked review fields (FR-EDU-003)."""

    reviewed_by = ContentAuthorSerializer(read_only=True)

    class Meta:
        model = models.EducationalContent
        fields = EducationalContentSerializer.Meta.fields + [
            "reviewed_by", "reviewed_at", "rejection_reason",
        ]
        read_only_fields = fields


class EducationalContentCreateSerializer(serializers.Serializer):
    title = serializers.CharField(max_length=TITLE_MAX)
    body = serializers.CharField(max_length=BODY_MAX)
    category = serializers.CharField(max_length=60)
    cover_url = serializers.CharField(
        max_length=COVER_URL_MAX, required=False, allow_blank=True, default="",
    )

    def validate_title(self, value):
        cleaned = sanitize_html(value, max_length=TITLE_MAX)
        if not cleaned.strip():
            raise serializers.ValidationError("A title is required.")
        return cleaned

    def validate_body(self, value):
        cleaned = sanitize_html(value, max_length=BODY_MAX)
        if not cleaned.strip():
            raise serializers.ValidationError("Content cannot be empty.")
        return cleaned

    def validate_cover_url(self, value):
        cleaned = sanitize_html(value, max_length=COVER_URL_MAX)
        if cleaned and not (
            cleaned.startswith("https://") or cleaned.startswith("http://")
        ):
            raise serializers.ValidationError("Cover URL must be an http(s) link.")
        return cleaned

    def validate_category(self, value):
        category = models.EducationCategory.objects.filter(code=value.strip()).first()
        if category is None:
            raise serializers.ValidationError("Unsupported category.")
        return category


class ReviewSerializer(serializers.Serializer):
    decision = serializers.ChoiceField(choices=["approve", "reject"])
    reason = serializers.CharField(
        max_length=REASON_MAX, required=False, allow_blank=True, default="",
    )

    def validate_reason(self, value):
        return sanitize_html(value, max_length=REASON_MAX)