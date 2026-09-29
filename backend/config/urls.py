"""URL configuration for Sickler's Warriors project."""

from django.contrib import admin
from django.urls import path, include
from drf_spectacular.views import SpectacularAPIView, SpectacularSwaggerView

from core.schema_gate import SchemaAccess

urlpatterns = [
    path("admin/", admin.site.urls),
    path("api/", include("core.urls")),
    path("api/auth/", include("accounts.urls")),
    path("api/", include("accounts.admin_urls")),
    path("api/patients/", include("patients.urls")),
    path("api/", include("medications.urls")),
    path("api/", include("facilities.urls")),
    path("api/", include("blood_network.urls")),
    path("api/", include("emergencies.urls")),
    path("api/", include("community.urls")),
    path("api/", include("content.urls")),
    path("api/", include("education.urls")),
    path("api/", include("doctors.urls")),
    path("api/", include("notifications.urls")),
    path("api/", include("donations.urls")),
    path("api/", include("audit.urls")),
    path("api/", include("patients.caregivers_urls")),
    path("api/", include("medical_records.urls")),
    path("api/", include("analytics.urls")),
    path("api/", include("ai_assistant.urls")),
    # OpenAPI schema — gated: DEBUG-only by default, admin.audit.read elsewhere
    # (Stage 4.17 §33). Rejects as 404.
    path(
        "api/schema/",
        SpectacularAPIView.as_view(permission_classes=[SchemaAccess]),
        name="schema",
    ),
    path(
        "api/docs/",
        SpectacularSwaggerView.as_view(url_name="schema", permission_classes=[SchemaAccess]),
        name="swagger-ui",
    ),
]
