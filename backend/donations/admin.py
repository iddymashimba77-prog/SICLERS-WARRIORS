from django.contrib import admin

from .models import Campaign, Donation, PaymentTransaction, Refund


@admin.register(Campaign)
class CampaignAdmin(admin.ModelAdmin):
    list_display = ("uid", "title", "owner", "goal_amount", "raised_amount", "status", "created_at")
    list_filter = ("status",)
    readonly_fields = ("uid", "created_at", "updated_at", "verified_at")


@admin.register(Donation)
class DonationAdmin(admin.ModelAdmin):
    list_display = ("uid", "donor", "campaign", "amount", "status", "transaction_ref", "created_at")
    list_filter = ("status",)
    readonly_fields = ("uid", "transaction_ref", "idempotency_key", "created_at", "updated_at")


@admin.register(PaymentTransaction)
class PaymentTransactionAdmin(admin.ModelAdmin):
    list_display = ("id", "donation", "provider", "status", "amount", "provider_ref", "attempt")
    list_filter = ("provider", "status")
    readonly_fields = ("provider_ref", "payload", "created_at", "updated_at")


@admin.register(Refund)
class RefundAdmin(admin.ModelAdmin):
    list_display = ("id", "donation", "amount", "status", "initiated_by", "created_at")
    list_filter = ("status",)
    readonly_fields = ("id", "created_at", "updated_at")