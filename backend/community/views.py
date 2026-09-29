"""Community API views (approved Stage 4.10, endpoint-matrix §16).

    GET/POST    /api/community/posts/                       list (auth) / create
    GET         /api/community/posts/{uid}/                 retrieve (auth)
    PATCH/DELETE /api/community/posts/{uid}/                author / moderator
    POST/DELETE /api/community/posts/{uid}/reactions/       react (community.comment)
    GET/POST    /api/community/posts/{uid}/comments/        read / comment
    PATCH/DELETE /api/community/posts/{uid}/comments/{id}/  author / moderator
    POST        /api/community/reports/                     community.report
    GET         /api/admin/community/reports/               community.moderate
    POST        /api/admin/community/reports/{id}/resolve/  community.moderate

Deny by default: reading community posts/comments is open to authenticated
members; writing is gated; moderation is MODERATOR/ADMIN/SUPER_ADMIN only.
There is no ADMIN bypass into private medical data — community is its own
boundary (§14).
"""

from django.db import IntegrityError, transaction
from django.db.models import Count, Exists, OuterRef, Q, Subquery
from rest_framework import mixins, status as http_status, viewsets
from rest_framework.decorators import action
from rest_framework.exceptions import NotFound, PermissionDenied, ValidationError
from rest_framework.generics import GenericAPIView
from rest_framework.parsers import JSONParser
from rest_framework.response import Response

from accounts.permissions import IsAuthenticatedRespectStatus, require
from audit.services import record_audit
from core.pagination import CorePageNumberPagination
from . import models, serializers, services
from .permissions import CommunityAccess
from .throttles import (
    CommunityInteractionThrottle,
    CommunityPostThrottle,
    CommunityReportThrottle,
    CommunityResolveThrottle,
)


# Reaction types allowed on community posts (Stage 4.17 §15 — the model field
# is intentionally free-form; the API whitelists so spam/abuse cannot mint
# arbitrary reaction labels).
REACTION_TYPES = frozenset({"LIKE", "HELPFUL", "LOVE", "CARE", "SOLIDARITY", "CELEBRATE"})


def _is_moderator(user) -> bool:
    return bool(user and user.is_authenticated and user.has_perm_code("community.moderate"))


class CommunityPostViewSet(viewsets.GenericViewSet):
    lookup_field = "uid"
    lookup_url_kwarg = "uid"
    serializer_class = serializers.CommunityPostSerializer
    permission_classes = [CommunityAccess]
    parser_classes = [JSONParser]
    pagination_class = CorePageNumberPagination

    def get_serializer_class(self):
        if getattr(self, "action", None) == "create":
            return serializers.CommunityPostCreateSerializer
        return serializers.CommunityPostSerializer

    def get_throttles(self):
        action = getattr(self, "action", None)
        if action == "create":
            return [CommunityPostThrottle()]
        if action == "react":
            return [CommunityInteractionThrottle()]
        return []

    def _base_queryset(self):
        user = self.request.user
        # Stage 4.18: correlated Subquery counts replace the previous
        # .distinct() Count GROUP BY which fanned out over reactions × comments
        # rows. Same numbers, no row multiplication on hot feeds.
        reaction_count = models.Reaction.objects.filter(
            post=OuterRef("pk"),
        ).order_by().values("post").annotate(n=Count("id")).values("n")
        comment_count = models.Comment.objects.filter(
            post=OuterRef("pk"), status="PUBLISHED",
        ).order_by().values("post").annotate(n=Count("id")).values("n")
        return (
            models.CommunityPost.objects.select_related("author")
            .filter(deleted_at__isnull=True)
            .annotate(
                reaction_count=Subquery(reaction_count),
                comment_count=Subquery(comment_count),
                user_reacted=Exists(
                    models.Reaction.objects.filter(post=OuterRef("pk"), user=user)
                ),
            )
        )

    def get_queryset(self):
        user = self.request.user
        qs = self._base_queryset()
        if _is_moderator(user):
            return qs
        return qs.filter(Q(status="PUBLISHED") | Q(author=user))

    def get_object(self):
        qs = self.get_queryset()
        obj = qs.filter(**{self.lookup_field: self.kwargs[self.lookup_url_kwarg]}).first()
        if obj is None:
            raise NotFound("Not found.")
        self.check_object_permissions(self.request, obj)
        return obj

    def list(self, request):
        qs = self.get_queryset()
        category = request.query_params.get("category")
        if category:
            if category not in models.POST_CATEGORIES:
                raise ValidationError({"category": "Unsupported category."})
            qs = qs.filter(category=category)
        if request.query_params.get("author") == "me":
            qs = qs.filter(author=request.user)
        qs = qs.order_by("-created_at")
        page = self.paginate_queryset(qs)
        serializer = serializers.CommunityPostSerializer(page, many=True, context={"request": request})
        return self.get_paginated_response(serializer.data)

    def retrieve(self, request, uid=None):
        instance = self.get_object()
        serializer = serializers.CommunityPostSerializer(instance, context={"request": request})
        return Response(serializer.data)

    @transaction.atomic
    def create(self, request):
        user = request.user
        if not user.has_perm_code("community.create_post"):
            raise PermissionDenied("You do not have permission to perform this action.")
        serializer = serializers.CommunityPostCreateSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        data = serializer.validated_data
        post = services.create_post(
            author=user,
            title=data.get("title", ""),
            content=data["content"],
            category=data.get("category", "GENERAL"),
        )
        record_audit(
            actor=user, action_code="community_posts.create",
            resource_type="community_post", resource_id=post.pk, request=request,
            details={"category": post.category},
        )
        post = self.get_queryset().get(pk=post.pk)
        return Response(
            serializers.CommunityPostSerializer(post, context={"request": request}).data,
            status=http_status.HTTP_201_CREATED,
        )

    def _assert_author_or_moderator(self, request, obj):
        if obj.author_id != request.user.id and not _is_moderator(request.user):
            raise PermissionDenied("Only the author can change this post.")

    @transaction.atomic
    def partial_update(self, request, uid=None):
        instance = self.get_object()
        self._assert_author_or_moderator(request, instance)
        serializer = serializers.CommunityPostCreateSerializer(data=request.data, partial=True)
        serializer.is_valid(raise_exception=True)
        data = serializer.validated_data
        services.update_post(
            instance,
            title=data.get("title"),
            content=data.get("content"),
            category=data.get("category"),
        )
        record_audit(
            actor=request.user, action_code="community_posts.update",
            resource_type="community_post", resource_id=instance.pk, request=request,
        )
        instance = self.get_queryset().get(pk=instance.pk)
        return Response(serializers.CommunityPostSerializer(instance, context={"request": request}).data)

    def update(self, request, uid=None):
        return self.partial_update(request, uid=uid)

    @transaction.atomic
    def destroy(self, request, uid=None):
        instance = self.get_object()
        self._assert_author_or_moderator(request, instance)
        services.soft_delete_post(instance)
        record_audit(
            actor=request.user, action_code="community_posts.delete",
            resource_type="community_post", resource_id=instance.pk, request=request,
        )
        return Response(status=http_status.HTTP_204_NO_CONTENT)

    @action(detail=True, methods=["post", "delete"], url_path="reactions")
    def react(self, request, uid=None):
        instance = self.get_object()
        reaction_type = (request.data.get("reaction_type") or "LIKE")[:20]
        if reaction_type not in REACTION_TYPES:
            raise ValidationError({"reaction_type": "Unsupported reaction type."})
        if request.method == "DELETE":
            services.clear_reaction(post=instance, user=request.user, reaction_type=reaction_type)
        else:
            services.set_reaction(post=instance, user=request.user, reaction_type=reaction_type)
        instance = self.get_queryset().get(pk=instance.pk)
        return Response({
            "uid": str(instance.uid),
            "reaction_count": instance.reaction_count,
            "reacted": instance.user_reacted,
        })


class CommentListCreateView(GenericAPIView):
    permission_classes = [IsAuthenticatedRespectStatus]
    parser_classes = [JSONParser]
    pagination_class = CorePageNumberPagination

    def get_post(self):
        post = models.CommunityPost.objects.filter(
            uid=self.kwargs["uid"], deleted_at__isnull=True,
        ).first()
        if post is None:
            raise NotFound("Not found.")
        return post

    def get_throttles(self):
        if self.request.method == "POST":
            return [CommunityInteractionThrottle()]
        return []

    def get_queryset(self, post):
        user = self.request.user
        qs = models.Comment.objects.select_related("author").filter(post=post)
        if _is_moderator(user):
            return qs
        return qs.filter(Q(status="PUBLISHED") | Q(author=user))

    def get(self, request, uid=None):
        post = self.get_post()
        # Stage 4.17 §15: moderated (HIDDEN/REMOVED) content stays hidden — its
        # comment thread is not readable by regular members, only moderators.
        if post.status != "PUBLISHED" and not _is_moderator(request.user):
            raise NotFound("Not found.")
        qs = self.get_queryset(post).order_by("created_at")
        page = self.paginate_queryset(qs)
        serializer = serializers.CommentSerializer(page, many=True, context={"request": request})
        return self.get_paginated_response(serializer.data)

    @transaction.atomic
    def post(self, request, uid=None):
        if not request.user.has_perm_code("community.comment"):
            raise PermissionDenied("You do not have permission to perform this action.")
        post = self.get_post()
        if post.status != "PUBLISHED":
            raise ValidationError({"post": "This post is not open for comments."})
        serializer = serializers.CommentCreateSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        comment = services.create_comment(
            post=post, author=request.user, content=serializer.validated_data["content"],
        )
        record_audit(
            actor=request.user, action_code="community_comments.create",
            resource_type="comment", resource_id=comment.pk, request=request,
            details={"post": post.pk},
        )
        return Response(
            serializers.CommentSerializer(comment, context={"request": request}).data,
            status=http_status.HTTP_201_CREATED,
        )


class CommentDetailView(GenericAPIView):
    permission_classes = [IsAuthenticatedRespectStatus]
    parser_classes = [JSONParser]

    def get_object(self):
        comment = models.Comment.objects.select_related("author").filter(
            pk=self.kwargs["pk"], post__uid=self.kwargs["uid"], post__deleted_at__isnull=True,
        ).first()
        if comment is None:
            raise NotFound("Not found.")
        return comment

    def _assert_author_or_moderator(self, request, obj):
        if obj.author_id != request.user.id and not _is_moderator(request.user):
            raise PermissionDenied("Only the author can change this comment.")

    @transaction.atomic
    def patch(self, request, uid=None, pk=None):
        comment = self.get_object()
        self._assert_author_or_moderator(request, comment)
        serializer = serializers.CommentCreateSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        services.update_comment(comment, content=serializer.validated_data["content"])
        return Response(serializers.CommentSerializer(comment, context={"request": request}).data)

    @transaction.atomic
    def delete(self, request, uid=None, pk=None):
        comment = self.get_object()
        self._assert_author_or_moderator(request, comment)
        services.soft_delete_comment(comment)
        record_audit(
            actor=request.user, action_code="community_comments.delete",
            resource_type="comment", resource_id=comment.pk, request=request,
        )
        return Response(status=http_status.HTTP_204_NO_CONTENT)


class ReportCreateView(GenericAPIView):
    permission_classes = [IsAuthenticatedRespectStatus, require("community.report")]
    parser_classes = [JSONParser]

    def get_throttles(self):
        return [CommunityReportThrottle()]

    @transaction.atomic
    def post(self, request):
        serializer = serializers.ReportCreateSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        data = serializer.validated_data
        target = services._target_object(data["target_type"], data["target_id"])
        if target is None:
            raise NotFound("Reported content was not found.")
        if getattr(target, "status", "PUBLISHED") != "PUBLISHED":
            raise ValidationError({"target": "This content is not reportable."})
        try:
            report = services.create_report(
                reporter=request.user,
                target_type=data["target_type"],
                target_id=data["target_id"],
                reason=data["reason"],
            )
        except IntegrityError:
            raise ValidationError({"detail": "You have already reported this content."})
        record_audit(
            actor=request.user, action_code="community_reports.create",
            resource_type="report", resource_id=report.pk, request=request,
            details={"target_type": report.target_type, "target_id": report.target_id},
        )
        return Response(
            {"id": report.pk, "status": report.status, "target_type": report.target_type,
             "target_id": report.target_id, "created_at": report.created_at},
            status=http_status.HTTP_201_CREATED,
        )


class AdminReportViewSet(mixins.ListModelMixin, viewsets.GenericViewSet):
    """GET /admin/community/reports, POST .../{id}/resolve — community.moderate."""

    serializer_class = serializers.AdminReportSerializer
    permission_classes = [IsAuthenticatedRespectStatus, require("community.moderate")]
    pagination_class = CorePageNumberPagination

    def get_throttles(self):
        if getattr(self, "action", None) == "resolve":
            return [CommunityResolveThrottle()]
        return []

    def get_queryset(self):
        qs = models.Report.objects.select_related("reporter", "reviewed_by")
        status_filter = self.request.query_params.get("status")
        if status_filter:
            if status_filter not in models.REPORT_STATUSES:
                raise ValidationError({"status": "Unsupported status."})
            qs = qs.filter(status=status_filter)
        return qs

    def list(self, request):
        qs = self.get_queryset()
        page = self.paginate_queryset(qs)
        serializer = serializers.AdminReportSerializer(page, many=True, context={"request": request})
        return self.get_paginated_response(serializer.data)

    @action(detail=True, methods=["post"], url_path="resolve")
    @transaction.atomic
    def resolve(self, request, pk=None):
        report = self.get_object()
        serializer = serializers.ReportResolveSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        data = serializer.validated_data
        action_value = data.get("action", "NONE")
        if action_value in ("HIDE", "REMOVE") and not data.get("review_notes"):
            raise ValidationError({"review_notes": "A reason is required to moderate content."})
        services.resolve_report(
            report,
            actor=request.user,
            status=data["status"],
            review_notes=data.get("review_notes", ""),
            action=action_value,
        )
        record_audit(
            actor=request.user, action_code="community.moderate",
            resource_type="report", resource_id=report.pk, request=request,
            details={"status": report.status, "action": action_value},
        )
        return Response(
            serializers.AdminReportSerializer(report, context={"request": request}).data
        )
