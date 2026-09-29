"""Donations & payments routing (Stage 4.12). Mounted under ``/api/`` by config/urls.py."""

from django.urls import path
from rest_framework.routers import DefaultRouter

from . import views

router = DefaultRouter()
router.register("campaigns", views.CampaignViewSet, basename="campaign")
router.register("admin/campaigns", views.AdminCampaignViewSet, basename="admin-campaign")
router.register("donations", views.DonationViewSet, basename="donation")
router.register("admin/donations", views.AdminDonationViewSet, basename="admin-donation")
router.register("payments", views.PaymentViewSet, basename="payment")

urlpatterns = router.urls + [
    path(
        "admin/financial/summary/",
        views.AdminFinancialSummaryView.as_view(),
        name="admin-financial-summary",
    ),
    path(
        "webhooks/payments/<str:provider>/",
        views.PaymentWebhookView.as_view(),
        name="payment-webhook",
    ),
]