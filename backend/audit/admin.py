from django.contrib import admin

from .models import AuditLog


@admin.register(AuditLog)
class AuditLogAdmin(admin.ModelAdmin):
    """Read-only oversight — AuditLog is append-only and must never be edited."""

    list_display = ("id", "created_at", "actor", "action_code", "resource_type", "result")
    list_filter = ("action_code", "result")
    search_fields = ("action_code",)

    def has_add_permission(self, request):
        return False

    def has_change_permission(self, request, obj=None):
        return False

    def has_delete_permission(self, request, obj=None):
        return False