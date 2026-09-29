from django.contrib import admin

from .models import EmergencyAccessGrant, EmergencyRequest, EmergencyResponder


@admin.register(EmergencyRequest)
class EmergencyRequestAdmin(admin.ModelAdmin):
    list_display = ("uid", "severity", "type", "status", "created_at")
    list_filter = ("status", "severity", "type")
    search_fields = ("uid",)


@admin.register(EmergencyResponder)
class EmergencyResponderAdmin(admin.ModelAdmin):
    list_display = ("request", "responder", "responder_role", "status")
    list_filter = ("status",)


@admin.register(EmergencyAccessGrant)
class EmergencyAccessGrantAdmin(admin.ModelAdmin):
    list_display = ("uid", "patient", "grantee", "status", "expires_at")
    list_filter = ("status",)