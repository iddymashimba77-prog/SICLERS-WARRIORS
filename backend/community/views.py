"""Community forum API views (Stage 4.10, forum extension).

    GET/POST    /api/community/posts/                       list / create
    GET         /api/community/posts/{uid}/                 retrieve
    PATCH/DELETE /api/community/posts/{uid}/                author / moderator
    POST/DELETE /api/community/posts/{uid}/reactions/       react
    POST        /api/community/posts/{uid}/pin/             moderator
    POST        /api/community/posts/{uid}/lock/            moderator
    GET/POST    /api/community/posts/{uid}/comments/        read / comment
    PATCH/DELETE /api/community/posts/{uid}/comments/{id}/  author / moderator
    GET         /api/community/categories/                  active categories
    POST        /api/community/reports/                     report
    GET         /api/community/notifications/               own forum notifications
    GET         /api/community/notifications/unread-count/  own forum badge
    POST        /api/community/notifications/{id}/read/     mark one own read
    POST        /api/community/notifications/read-all/      mark all own read
    GET         /api/admin/community/reports/               moderation queue
    POST        /api/admin/community/reports/{id}/resolve/  moderation decision

Forum member surfaces are denied to ADMIN/SUPER_ADMIN at the permission layer
(and again by role-aware frontend navigation). Admin moderation routes remain
available to moderators/admins because they are the existing back-office queue,
not the member forum.
"""

from django.db import IntegrityError, transaction
from django.db.models import Count, Exists, OuterRef, Q, Subquery
from drf_spectacular.utils import OpenApiTypes, extend_schema
from rest_framework import mixins, status as http_status, viewsets
from rest_framework.decorators import action
from rest_framework.exceptions import NotFound, PermissionDenied, ValidationError
from rest_framework.generics import GenericAPIView
from rest_framework.parsers import JSONParser
from rest_framework.response import Response

from accounts.permissions import IsAuthenticatedRespectStatus, require
from audit.services import record_audit
from core.pagination import CorePageNumberPagination
from notifications.models import Notification
from notifications.serializers import NotificationSerializer
from notifications.services import mark_read
from . import models, serializers, services
from .permissions import CommunityAccess, ForumMemberOnly
from .throttles import (
    CommunityInteractionThrottle,
    CommunityPostThrottle,
    CommunityReportThrottle,
    CommunityResolveThrottle,
)


REACTION_TYPES = frozenset({"LIKE", "HELPFUL", "LOVE", "CARE", "SOLIDARITY", "CELEBRATE"})
SORT_OPTIONS = frozenset({"latest", "newest", "oldest", "popular"})


def _is_moderator(user) -> bool:
    return bool(user and user.is_authenticated and user.has_perm_code("community.moderate"))


def _forum_notifications(user):
    return (
        Notification.objects.filter(recipient=user, type="COMMUNITY")
        .exclude(status="SUPPRESSED")
    )


class CommunityPostViewSet(viewsets.GenericViewSet):
    lookup_field = "uid"
    lookup_url_kwarg = "uid"
    serializer_class = serializers.CommunityPostSerializer
    queryset = models.CommunityPost.objects.none()
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
        reaction_count = models.Reaction.objects.filter(
            post=OuterRef("pk"),
        ).order_by().values("post").annotate(n=Count("id")).values("n")
        comment_count = models.Comment.objects.filter(
            post=OuterRef("pk"), status="PUBLISHED",
        ).order_by().values("post").annotate(n=Count("id")).values("n")
        return (
            models.CommunityPost.objects.select_related("author", "forum_category")
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

    def _ordered(self, qs, sort):
        if sort == "newest":
            return qs.order_by("-is_pinned", "-created_at")
        if sort == "oldest":
            return qs.order_by("-is_pinned", "created_at")
        if sort == "popular":
            return qs.order_by("-is_pinned", "-reaction_count", "-comment_count", "-created_at")
        return qs.order_by("-is_pinned", "-last_activity_at", "-created_at")

    def list(self, request):
        qs = self.get_queryset()
        category = request.query_params.get("category") or request.query_params.get("category_slug")
        if category:
            if category in models.POST_CATEGORIES:
                qs = qs.filter(category=category)
            elif models.ForumCategory.objects.filter(slug=category, is_active=True).exists():
                qs = qs.filter(forum_category__slug=category)
            else:
                raise ValidationError({"category": "Unsupported category."})
        search = (request.query_params.get("search") or "").strip()[:200]
        if search:
            qs = qs.filter(Q(title__icontains=search) | Q(content__icontains=search))
        if request.query_params.get("author") == "me":
            qs = qs.filter(author=request.user)
        sort = (request.query_params.get("sort") or "latest").lower()
        if sort not in SORT_OPTIONS:
            raise ValidationError({"sort": "Unsupported sort order."})
        qs = self._ordered(qs, sort)
        page = self.paginate_queryset(qs)
        serializer = serializers.CommunityPostSerializer(
            page, many=True, context={"request": request},
        )
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
            forum_category=data.get("forum_category"),
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

    def _assert_moderator(self, request):
        if not _is_moderator(request.user):
            raise PermissionDenied("Only a moderator can perform this action.")

    @transaction.atomic
    def partial_update(self, request, uid=None):
        instance = self.get_object()
        self._assert_author_or_moderator(request, instance)
        serializer = serializers.CommunityPostCreateSerializer(
            data=request.data, partial=True,
        )
        serializer.is_valid(raise_exception=True)
        data = serializer.validated_data
        services.update_post(
            instance,
            title=data.get("title"),
            content=data.get("content"),
            category=data.get("category"),
            forum_category=data.get("forum_category"),
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

    @action(detail=True, methods=["post"], url_path="pin")
    def pin(self, request, uid=None):
        instance = self.get_object()
        self._assert_moderator(request)
        value = request.data.get("is_pinned", True)
        if not isinstance(value, bool):
            raise ValidationError({"is_pinned": "Expected a boolean."})
        services.set_post_flags(instance, is_pinned=value)
        record_audit(
            actor=request.user, action_code="community_posts.pin",
            resource_type="community_post", resource_id=instance.pk, request=request,
            details={"is_pinned": value},
        )
        instance = self.get_queryset().get(pk=instance.pk)
        return Response(serializers.CommunityPostSerializer(instance, context={"request": request}).data)

    @action(detail=True, methods=["post"], url_path="lock")
    def lock(self, request, uid=None):
        instance = self.get_object()
        self._assert_moderator(request)
        value = request.data.get("is_locked", True)
        if not isinstance(value, bool):
            raise ValidationError({"is_locked": "Expected a boolean."})
        services.set_post_flags(instance, is_locked=value)
        record_audit(
            actor=request.user, action_code="community_posts.lock",
            resource_type="community_post", resource_id=instance.pk, request=request,
            details={"is_locked": value},
        )
        instance = self.get_queryset().get(pk=instance.pk)
        return Response(serializers.CommunityPostSerializer(instance, context={"request": request}).data)

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
    permission_classes = [ForumMemberOnly]
    parser_classes = [JSONParser]
    pagination_class = CorePageNumberPagination

    def get_serializer_class(self):
        if self.request.method == "POST":
            return serializers.CommentCreateSerializer
        return serializers.CommentSerializer

    def get_post(self):
        post = models.CommunityPost.objects.select_related(
            "author", "forum_category",
        ).filter(uid=self.kwargs["uid"], deleted_at__isnull=True).first()
        if post is None:
            raise NotFound("Not found.")
        return post

    def get_throttles(self):
        if self.request.method == "POST":
            return [CommunityInteractionThrottle()]
        return []

    def get_queryset(self, post):
        user = self.request.user
        reply_count = models.Comment.objects.filter(
            parent=OuterRef("pk"), status="PUBLISHED",
        ).order_by().values("parent").annotate(n=Count("id")).values("n")
        qs = (
            models.Comment.objects.select_related("author", "parent")
            .filter(post=post)
            .annotate(reply_count=Subquery(reply_count))
        )
        if _is_moderator(user):
            return qs
        # Deleted/hidden parents stay as tombstones while they have live
        # replies so the thread never loses its structure.
        return qs.filter(
            Q(status="PUBLISHED") | Q(author=user) | Q(replies__status="PUBLISHED")
        ).distinct()

    def get(self, request, uid=None):
        post = self.get_post()
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
        if post.is_locked:
            raise ValidationError({"post": "This discussion is locked."})
        serializer = serializers.CommentCreateSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        parent = None
        parent_id = serializer.validated_data.get("parent_id")
        if parent_id:
            parent = models.Comment.objects.filter(
                pk=parent_id, post=post, status="PUBLISHED",
            ).first()
            if parent is None:
                raise ValidationError({"parent_id": "Reply target was not found."})
            if parent.depth >= services.MAX_COMMENT_DEPTH:
                raise ValidationError({"parent_id": "Reply depth limit reached."})
        comment = services.create_comment(
            post=post,
            author=request.user,
            content=serializer.validated_data["content"],
            parent=parent,
        )
        record_audit(
            actor=request.user, action_code="community_comments.create",
            resource_type="comment", resource_id=comment.pk, request=request,
            details={"post": post.pk, "parent": parent.pk if parent else None},
        )
        return Response(
            serializers.CommentSerializer(comment, context={"request": request}).data,
            status=http_status.HTTP_201_CREATED,
        )


class CommentDetailView(GenericAPIView):
    permission_classes = [ForumMemberOnly]
    parser_classes = [JSONParser]

    def get_serializer_class(self):
        if self.request.method == "PATCH":
            return serializers.CommentCreateSerializer
        return serializers.CommentSerializer

    def get_object(self):
        comment = models.Comment.objects.select_related("author", "parent").filter(
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
        if comment.status != "PUBLISHED":
            raise ValidationError({"comment": "Deleted comments cannot be edited."})
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


class ForumCategoryListView(GenericAPIView):
    permission_classes = [ForumMemberOnly]
    serializer_class = serializers.ForumCategorySerializer

    def get(self, request):
        qs = (
            models.ForumCategory.objects.filter(is_active=True)
            .annotate(
                post_count=Count(
                    "posts",
                    filter=Q(posts__status="PUBLISHED", posts__deleted_at__isnull=True),
                    distinct=True,
                )
            )
            .order_by("sort_order", "name")
        )
        return Response({
            "results": serializers.ForumCategorySerializer(qs, many=True).data,
        })


class ForumNotificationListView(GenericAPIView):
    permission_classes = [ForumMemberOnly]
    pagination_class = CorePageNumberPagination
    serializer_class = NotificationSerializer

    def get_queryset(self):
        qs = _forum_notifications(self.request.user)
        if self.request.query_params.get("unread") in ("1", "true", "True"):
            qs = qs.exclude(status="READ")
        return qs.order_by("-created_at")

    def get(self, request):
        qs = self.get_queryset()
        page = self.paginate_queryset(qs)
        serializer = NotificationSerializer(page, many=True)
        return self.get_paginated_response(serializer.data)


class ForumNotificationUnreadCountView(GenericAPIView):
    permission_classes = [ForumMemberOnly]

    def get(self, request):
        count = _forum_notifications(request.user).exclude(status="READ").count()
        return Response({"unread": count})


class ForumNotificationReadView(GenericAPIView):
    permission_classes = [ForumMemberOnly]
    serializer_class = NotificationSerializer

    def post(self, request, pk=None):
        notification = _forum_notifications(request.user).filter(pk=pk).first()
        if notification is None:
            raise NotFound("Not found.")
        mark_read(notification)
        return Response(NotificationSerializer(notification).data)


class ForumNotificationReadAllView(GenericAPIView):
    permission_classes = [ForumMemberOnly]

    def post(self, request):
        updated = _forum_notifications(request.user).exclude(status="READ").update(
            status="READ",
        )
        # Use the shared service semantics for read_at consistency.
        from django.utils import timezone

        _forum_notifications(request.user).filter(status="READ", read_at__isnull=True).update(
            read_at=timezone.now(),
        )
        return Response({"updated": updated})


@extend_schema(responses=OpenApiTypes.OBJECT)
class ReportCreateView(GenericAPIView):
    permission_classes = [ForumMemberOnly, require("community.report")]
    parser_classes = [JSONParser]

    def get_serializer_class(self):
        return serializers.ReportCreateSerializer

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
