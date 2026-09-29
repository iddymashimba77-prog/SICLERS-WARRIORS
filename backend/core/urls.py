"""Health check + brand URLs."""

from django.urls import path

from . import branding_views, views

app_name = "health"

urlpatterns = [
    path("v1/health/", views.health_live, name="health-live"),
    path("v1/health/ready/", views.health_ready, name="health-ready"),
    path("branding/", branding_views.BrandingPublicView.as_view(), name="branding-public"),
    path("branding/logo/", branding_views.BrandingLogoFileView.as_view(), name="branding-logo"),
    path("admin/branding/", branding_views.AdminBrandingView.as_view(), name="branding-admin"),
    path("admin/branding/logo/", branding_views.AdminBrandingLogoView.as_view(), name="branding-admin-logo"),
]