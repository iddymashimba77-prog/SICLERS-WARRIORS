from django.contrib import admin

from .models import Notification, NotificationPreference


@admin.register(Notification)
class NotificationAdmin(admin.ModelAdmin):
    list_display = ("id", "recipient", "type", "status", "created_at")
    list_filter = ("type", "status")
    search_fields = ("recipient__email", "title")


@admin.register(NotificationPreference)
class NotificationPreferenceAdmin(admin.ModelAdmin):
    list_display = ("user", "category", "enabled")
    list_filter = ("category", "enabled")