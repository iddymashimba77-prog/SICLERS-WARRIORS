"""Content CMS Django admin registrations (ops convenience only)."""

from django.contrib import admin

from .models import NewsArticle, TickerAnnouncement


@admin.register(NewsArticle)
class NewsArticleAdmin(admin.ModelAdmin):
    list_display = (
        "title", "category", "status", "featured", "pinned",
        "deleted_at", "published_at",
    )
    list_filter = ("status", "category", "featured", "pinned", "deleted_at")
    search_fields = ("title", "excerpt")
    readonly_fields = (
        "uid", "created_at", "updated_at", "pinned_at", "pinned_by", "deleted_at", "deleted_by",
    )
    actions = ("soft_delete_selected", "restore_selected")
    actions_on_top = True

    @admin.action(description="Soft delete selected articles (never hard-deleted)")
    def soft_delete_selected(self, request, queryset):
        from . import services

        updated = 0
        for article in queryset.filter(deleted_at__isnull=True):
            services.soft_delete_news(article, actor=request.user)
            updated += 1
        self.message_user(request, f"{updated} article(s) soft deleted and archived.")

    @admin.action(description="Restore selected soft-deleted articles")
    def restore_selected(self, request, queryset):
        from . import services

        updated = 0
        for article in queryset.filter(deleted_at__isnull=False):
            services.restore_news(article, actor=request.user)
            updated += 1
        self.message_user(request, f"{updated} article(s) restored as drafts.")


@admin.register(TickerAnnouncement)
class TickerAnnouncementAdmin(admin.ModelAdmin):
    list_display = ("message", "announcement_type", "is_active", "priority", "created_at")
    list_filter = ("is_active", "announcement_type")
    search_fields = ("message",)
    readonly_fields = ("uid", "created_at", "updated_at")