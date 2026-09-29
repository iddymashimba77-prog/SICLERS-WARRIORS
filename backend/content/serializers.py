"""Content CMS serializers.

Public surface exposes publication metadata only (title, category, excerpt,
cover, tags, dates, author brief). The full editorial ``body`` is served on the
public detail page only — the list payload is lean (§ NFR-PERF). Admin
serializers add workflow fields (status, featured, author, dates). Reuses the
community ``uid + display_name`` author projection and HTML sanitisation.
"""

from rest_framework import serializers

from community.sanitizers import sanitize_html
from community.serializers import display_name

from . import models

TITLE_MAX = 200
EXCERPT_MAX = 500
BODY_MAX = 50000
URL_MAX = 500
ALT_MAX = 300
MESSAGE_MAX = 240
TAG_MAX = 40

_CATEGORY_CODES = [code for code, _label in models.NEWS_CATEGORIES]
_TICKER_CODES = [code for code, _label in models.TICKER_TYPES]


def _clean(value, max_length):
    return sanitize_html(value or "", max_length=max_length)


class ItemAuthorSerializer(serializers.Serializer):
    uid = serializers.UUIDField(read_only=True)
    display_name = serializers.SerializerMethodField()

    def get_display_name(self, obj) -> str:
        return display_name(obj)


# --------------------------------------------------------------- public news

class PublicNewsSummarySerializer(serializers.ModelSerializer):
    """Lean public listing row — no full body (NFR-PERF-002)."""

    category_label = serializers.CharField(read_only=True)
    author = ItemAuthorSerializer(read_only=True)
    tags = serializers.ListField(child=serializers.CharField(), read_only=True)

    class Meta:
        model = models.NewsArticle
        fields = [
            "uid", "title", "category", "category_label", "excerpt",
            "cover_url", "cover_alt", "tags", "featured",
            "author", "published_at", "created_at", "updated_at",
        ]
        read_only_fields = fields


class PublicNewsDetailSerializer(PublicNewsSummarySerializer):
    """Public detail row — adds the editorial body."""

    class Meta(PublicNewsSummarySerializer.Meta):
        fields = PublicNewsSummarySerializer.Meta.fields + ["body"]


class PublicNewsCategorySerializer(serializers.Serializer):
    code = serializers.CharField()
    label = serializers.CharField()


class PublicTickerSerializer(serializers.ModelSerializer):
    announcement_type_label = serializers.CharField(read_only=True)

    class Meta:
        model = models.TickerAnnouncement
        fields = [
            "uid", "message", "announcement_type", "announcement_type_label",
            "link_url", "priority",
        ]
        read_only_fields = fields


# ---------------------------------------------------------------- admin news

class AdminNewsSerializer(serializers.ModelSerializer):
    category_label = serializers.CharField(read_only=True)
    author = ItemAuthorSerializer(read_only=True)
    tags = serializers.ListField(child=serializers.CharField(), read_only=True)

    class Meta:
        model = models.NewsArticle
        fields = [
            "uid", "title", "category", "category_label", "excerpt", "body",
            "cover_url", "cover_alt", "tags", "featured", "status", "author",
            "published_at", "created_at", "updated_at",
        ]
        read_only_fields = fields


class NewsWriteSerializer(serializers.Serializer):
    title = serializers.CharField(max_length=TITLE_MAX)
    category = serializers.ChoiceField(choices=_CATEGORY_CODES)
    body = serializers.CharField(max_length=BODY_MAX)
    excerpt = serializers.CharField(
        max_length=EXCERPT_MAX, required=False, allow_blank=True, default="",
    )
    cover_url = serializers.CharField(
        max_length=URL_MAX, required=False, allow_blank=True, default="",
    )
    cover_alt = serializers.CharField(
        max_length=ALT_MAX, required=False, allow_blank=True, default="",
    )
    tags = serializers.ListField(
        child=serializers.CharField(max_length=TAG_MAX),
        required=False, allow_empty=True, default=list,
    )

    def validate_title(self, value):
        cleaned = _clean(value, TITLE_MAX)
        if not cleaned.strip():
            raise serializers.ValidationError("A title is required.")
        return cleaned

    def validate_body(self, value):
        cleaned = _clean(value, BODY_MAX)
        if not cleaned.strip():
            raise serializers.ValidationError("Content cannot be empty.")
        return cleaned

    def validate_excerpt(self, value):
        cleaned = _clean(value, EXCERPT_MAX)
        if cleaned.strip():
            return cleaned
        return _default_excerpt(self.initial_data or {})

    def validate_tags(self, value):
        tags = []
        for tag in value:
            cleaned = _clean(tag, TAG_MAX).strip()
            if cleaned:
                tags.append(cleaned)
        return tags[:10]

    def validate_cover_url(self, value):
        cleaned = _clean(value, URL_MAX)
        if cleaned and not (cleaned.startswith("http://") or cleaned.startswith("https://")):
            raise serializers.ValidationError("Cover URL must be an http(s) link.")
        return cleaned


def _default_excerpt(initial):
    body = _clean(str(initial.get("body") or ""), EXCERPT_MAX)
    words = body.split()
    return " ".join(words[:30])


class FeatureSerializer(serializers.Serializer):
    featured = serializers.BooleanField()


class NewsCoverSerializer(serializers.Serializer):
    image = serializers.FileField()
    alt = serializers.CharField(
        max_length=ALT_MAX, required=False, allow_blank=True, default="",
    )


# -------------------------------------------------------------- admin ticker

class AdminTickerSerializer(serializers.ModelSerializer):
    announcement_type_label = serializers.CharField(read_only=True)

    class Meta:
        model = models.TickerAnnouncement
        fields = [
            "uid", "message", "announcement_type", "announcement_type_label",
            "link_url", "is_active", "priority", "start_at", "end_at",
            "created_at", "updated_at",
        ]
        read_only_fields = fields


class TickerWriteSerializer(serializers.Serializer):
    message = serializers.CharField(max_length=MESSAGE_MAX)
    announcement_type = serializers.ChoiceField(choices=_TICKER_CODES, default="INFO")
    link_url = serializers.CharField(
        max_length=URL_MAX, required=False, allow_blank=True, default="",
    )
    is_active = serializers.BooleanField(required=False, default=True)
    priority = serializers.IntegerField(required=False, default=0)
    start_at = serializers.DateTimeField(required=False, allow_null=True)
    end_at = serializers.DateTimeField(required=False, allow_null=True)

    def validate_message(self, value):
        cleaned = _clean(value, MESSAGE_MAX)
        if not cleaned.strip():
            raise serializers.ValidationError("A message is required.")
        return cleaned

    def validate_link_url(self, value):
        cleaned = _clean(value, URL_MAX)
        if cleaned and not (cleaned.startswith("http://") or cleaned.startswith("https://")):
            raise serializers.ValidationError("Link URL must be an http(s) link.")
        return cleaned

    def validate(self, attrs):
        start_at = attrs.get("start_at")
        end_at = attrs.get("end_at")
        if start_at and end_at and end_at < start_at:
            raise serializers.ValidationError(
                {"end_at": "End date must be on or after the start date."}
            )
        return attrs