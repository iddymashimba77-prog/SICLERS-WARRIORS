"""Community serializers (approved Stage 4.10).

Deny-by-default data boundary: author projection is a display name + uid only.
Email, phone, medical flags, roles and moderation internals are never exposed
on public community surfaces.
"""

from rest_framework import serializers

from . import models
from .sanitizers import sanitize_html


def display_name(user) -> str:
    if user is None:
        return "Member"
    name = (getattr(user, "first_name", "") or "").strip()
    return name or "Member"


class AuthorBriefSerializer(serializers.Serializer):
    uid = serializers.UUIDField(read_only=True)
    display_name = serializers.SerializerMethodField()

    def get_display_name(self, obj) -> str:
        return display_name(obj)


class CommunityPostSerializer(serializers.ModelSerializer):
    author = AuthorBriefSerializer(read_only=True)
    reaction_count = serializers.SerializerMethodField()
    comment_count = serializers.SerializerMethodField()
    reacted = serializers.SerializerMethodField()
    is_author = serializers.SerializerMethodField()
    moderation_reason = serializers.SerializerMethodField()

    class Meta:
        model = models.CommunityPost
        fields = [
            "id", "uid", "author", "title", "content", "category", "status",
            "moderation_reason", "reaction_count", "comment_count",
            "reacted", "is_author", "created_at", "updated_at",
        ]
        read_only_fields = fields

    def get_reaction_count(self, obj) -> int:
        return getattr(obj, "reaction_count", None) or 0

    def get_comment_count(self, obj) -> int:
        return getattr(obj, "comment_count", None) or 0

    def get_reacted(self, obj) -> bool:
        return bool(getattr(obj, "user_reacted", False))

    def get_is_author(self, obj) -> bool:
        request = self.context.get("request")
        return bool(request and request.user.is_authenticated and obj.author_id == request.user.pk)

    def get_moderation_reason(self, obj) -> str | None:
        """Moderation internals are moderation-only (Stage 4.17 §15)."""
        request = self.context.get("request")
        if request and request.user.is_authenticated and request.user.has_perm_code("community.moderate"):
            return obj.moderation_reason
        return None


class CommunityPostCreateSerializer(serializers.Serializer):
    title = serializers.CharField(max_length=200, required=False, allow_blank=True, default="")
    content = serializers.CharField(max_length=20000)
    category = serializers.ChoiceField(choices=models.POST_CATEGORIES, default="GENERAL")

    def validate_content(self, value):
        cleaned = sanitize_html(value, max_length=20000)
        if not cleaned.strip():
            raise serializers.ValidationError("Content cannot be empty.")
        return cleaned

    def validate_title(self, value):
        return sanitize_html(value, max_length=200)


class CommentSerializer(serializers.ModelSerializer):
    author = AuthorBriefSerializer(read_only=True)
    is_author = serializers.SerializerMethodField()

    class Meta:
        model = models.Comment
        fields = ["id", "author", "content", "status", "is_author", "created_at", "updated_at"]
        read_only_fields = fields

    def get_is_author(self, obj) -> bool:
        request = self.context.get("request")
        return bool(request and request.user.is_authenticated and obj.author_id == request.user.pk)


class CommentCreateSerializer(serializers.Serializer):
    content = serializers.CharField(max_length=5000)

    def validate_content(self, value):
        cleaned = sanitize_html(value, max_length=5000)
        if not cleaned.strip():
            raise serializers.ValidationError("Comment cannot be empty.")
        return cleaned


class ReactionSerializer(serializers.Serializer):
    reaction_type = serializers.CharField(max_length=20, required=False, default="LIKE")


class ReportCreateSerializer(serializers.Serializer):
    target_type = serializers.ChoiceField(choices=models.REPORT_TARGET_TYPES)
    target_id = serializers.IntegerField()
    reason = serializers.CharField(max_length=2000)

    def validate_reason(self, value):
        # Spoiler-safe: reason is metadata only, never the reported body.
        cleaned = sanitize_html(value, max_length=2000)
        if not cleaned.strip():
            raise serializers.ValidationError("A reason is required.")
        return cleaned


class AdminReportSerializer(serializers.ModelSerializer):
    reporter = AuthorBriefSerializer(read_only=True)
    reviewed_by = AuthorBriefSerializer(read_only=True)
    target_preview = serializers.SerializerMethodField()
    target_exists = serializers.SerializerMethodField()

    class Meta:
        model = models.Report
        fields = [
            "id", "reporter", "target_type", "target_id", "reason", "status",
            "target_preview", "target_exists", "reviewed_by", "review_notes",
            "created_at", "updated_at",
        ]
        read_only_fields = fields

    def _target(self, obj):
        cache = self.context.setdefault("_target_cache", {})
        key = (obj.target_type, obj.target_id)
        if key in cache:
            return cache[key]
        if obj.target_type == "POST":
            target = models.CommunityPost.objects.filter(pk=obj.target_id).first()
        else:
            target = models.Comment.objects.filter(pk=obj.target_id).first()
        cache[key] = target
        return target

    def get_target_preview(self, obj) -> str:
        target = self._target(obj)
        if target is None:
            return ""
        raw = getattr(target, "title", "") or getattr(target, "content", "") or ""
        return raw[:120]

    def get_target_exists(self, obj) -> bool:
        return self._target(obj) is not None


class ReportResolveSerializer(serializers.Serializer):
    status = serializers.ChoiceField(choices=["RESOLVED", "DISMISSED"])
    review_notes = serializers.CharField(max_length=2000, required=False, allow_blank=True, default="")
    action = serializers.ChoiceField(
        choices=["NONE", "HIDE", "REMOVE"], required=False, default="NONE",
    )

    def validate_review_notes(self, value):
        return sanitize_html(value, max_length=2000)
