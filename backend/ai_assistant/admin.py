from django.contrib import admin

from .models import Conversation, Message


@admin.register(Conversation)
class ConversationAdmin(admin.ModelAdmin):
    list_display = ("uid", "user", "title", "created_at", "last_activity_at")
    readonly_fields = ("uid", "created_at", "updated_at", "last_activity_at")
    search_fields = ("uid", "user__email", "title")


@admin.register(Message)
class MessageAdmin(admin.ModelAdmin):
    list_display = ("uid", "conversation", "role", "created_at")
    readonly_fields = ("uid", "created_at")
    search_fields = ("uid", "conversation__uid")
