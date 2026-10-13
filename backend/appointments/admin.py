from django.contrib import admin

from .models import ClinicAppointment


@admin.register(ClinicAppointment)
class ClinicAppointmentAdmin(admin.ModelAdmin):
    list_display = [
        "uid", "patient", "facility", "doctor", "appointment_type",
        "status", "scheduled_at", "follow_up_status", "created_at",
    ]
    list_filter = ["status", "appointment_type", "follow_up_required", "reminder_enabled"]
    search_fields = ["patient__email", "patient__username", "facility__name", "reason"]
    readonly_fields = ["uid", "created_at", "updated_at", "reminders_sent", "last_reminder_sent_at"]
    date_hierarchy = "scheduled_at"