"""Content CMS Django admin registrations (ops convenience only)."""

from django.contrib import admin

from .models import NewsArticle, TickerAnnouncement


@admin.register(NewsArticle)
class NewsArticleAdmin(admin.ModelAdmin):
    list_display = ("title", "category", "status", "featured", "published_at")
    list_filter = ("status", "category", "featured")
    search_fields = ("title", "excerpt")
    readonly_fields = ("uid", "created_at", "updated_at")


@admin.register(TickerAnnouncement)
class TickerAnnouncementAdmin(admin.ModelAdmin):
    list_display = ("message", "announcement_type", "is_active", "priority", "created_at")
    list_filter = ("is_active", "announcement_type")
    search_fields = ("message",)
    readonly_fields = ("uid", "created_at", "updated_at")