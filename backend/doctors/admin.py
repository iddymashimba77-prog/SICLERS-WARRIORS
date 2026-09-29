from django.contrib import admin

from .models import (
    Conversation,
    ConversationParticipant,
    Message,
    MessageAttachment,
)


@admin.register(Conversation)
class ConversationAdmin(admin.ModelAdmin):
    list_display = ("uid", "type", "status", "created_by", "last_message_at")
    list_filter = ("type", "status")
    search_fields = ("uid",)


@admin.register(ConversationParticipant)
class ConversationParticipantAdmin(admin.ModelAdmin):
    list_display = ("conversation", "user", "role_in_chat", "status", "joined_at")
    list_filter = ("status", "role_in_chat")


@admin.register(Message)
class MessageAdmin(admin.ModelAdmin):
    list_display = ("uid", "conversation", "sender", "message_type", "status", "created_at")
    list_filter = ("message_type", "status")
    search_fields = ("uid",)


@admin.register(MessageAttachment)
class MessageAttachmentAdmin(admin.ModelAdmin):
    list_display = ("id", "message", "content_type", "size_bytes", "uploaded_at")
