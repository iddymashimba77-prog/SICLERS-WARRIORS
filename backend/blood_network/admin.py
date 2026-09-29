from django.contrib import admin

from .models import BloodDonationEvent, BloodDonor, BloodMatch, BloodRequest


@admin.register(BloodDonor)
class BloodDonorAdmin(admin.ModelAdmin):
    list_display = ("id", "user", "blood_group", "city", "is_available", "is_verified")
    list_filter = ("blood_group", "is_available", "is_verified")
    search_fields = ("user__email", "city")


@admin.register(BloodRequest)
class BloodRequestAdmin(admin.ModelAdmin):
    list_display = ("uid", "blood_group_needed", "units", "urgency", "status")
    list_filter = ("status", "urgency", "blood_group_needed")
    search_fields = ("uid", "reason")


@admin.register(BloodMatch)
class BloodMatchAdmin(admin.ModelAdmin):
    list_display = ("id", "request", "donor", "match_score", "status")
    list_filter = ("status",)


@admin.register(BloodDonationEvent)
class BloodDonationEventAdmin(admin.ModelAdmin):
    list_display = ("donation_serial", "donor", "outcome", "donated_at")
    list_filter = ("outcome",)

    def has_delete_permission(self, request, obj=None):
        return False  # immutable history