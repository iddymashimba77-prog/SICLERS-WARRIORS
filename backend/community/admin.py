from django.contrib import admin

from .models import Comment, CommunityPost, Reaction, Report


@admin.register(CommunityPost)
class CommunityPostAdmin(admin.ModelAdmin):
    list_display = ("uid", "author", "category", "status", "created_at")
    list_filter = ("status", "category")
    search_fields = ("uid", "title")


@admin.register(Comment)
class CommentAdmin(admin.ModelAdmin):
    list_display = ("id", "post", "author", "status", "created_at")
    list_filter = ("status",)


@admin.register(Reaction)
class ReactionAdmin(admin.ModelAdmin):
    list_display = ("id", "post", "user", "reaction_type", "created_at")
    list_filter = ("reaction_type",)


@admin.register(Report)
class ReportAdmin(admin.ModelAdmin):
    list_display = ("id", "target_type", "target_id", "reporter", "status", "created_at")
    list_filter = ("status", "target_type")
