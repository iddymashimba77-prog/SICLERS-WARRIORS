from django.contrib import admin

from .models import Facility


@admin.register(Facility)
class FacilityAdmin(admin.ModelAdmin):
    list_display = ("name", "facility_type", "city", "is_verified")
    list_filter = ("facility_type", "is_verified")
    search_fields = ("name", "city")
    readonly_fields = ("uid", "created_at", "updated_at")