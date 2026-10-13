"""URL configuration for Sickler's Warriors project.

The API is exposed under two prefixes:

* ``/api/…``    — the convention the implemented stages already use (auth at
  ``/api/auth/``, health at ``/api/v1/health/``, domains at ``/api/<domain>/``).
* ``/api/v1/…`` — the versioned prefix named in the API design.

Both prefixes are generated from the single ``API_MOUNTS`` table below, so the
versioned tree is an *alias* of the same views — never a second implementation.
Adding a domain to one prefix adds it to the other automatically, which is the
only way an alias like this stays trustworthy over time.

Uploaded media (``/media/…``) is served by Django only when ``SERVE_MEDIA`` is
enabled (default on for development/staging, off in production where object
storage/CDN is expected). Serving it here is what makes profile pictures, news
covers and education documents resolvable for API clients.
"""

from django.conf import settings
from django.contrib import admin
from django.urls import include, path, re_path
from django.views.static import serve
from drf_spectacular.views import SpectacularAPIView, SpectacularSwaggerView

from core.handlers import api_not_found, api_server_error
from core.schema_gate import SchemaAccess

# (prefix, urlconf module) — shared by /api/ and /api/v1/.
API_MOUNTS = [
    ("", "core.urls_health"),
    ("auth/", "accounts.urls"),
    ("", "accounts.admin_urls"),
    ("patients/", "patients.urls"),
    ("", "patients.caregivers_urls"),
    ("", "medications.urls"),
    ("", "facilities.urls"),
    ("", "blood_network.urls"),
    ("", "emergencies.urls"),
    ("", "community.urls"),
    ("", "content.urls"),
    ("", "education.urls"),
    ("", "doctors.urls"),
    ("", "notifications.urls"),
    ("", "donations.urls"),
    ("", "audit.urls"),
    ("", "medical_records.urls"),
    ("", "analytics.urls"),
    ("", "ai_assistant.urls"),
    ("", "appointments.urls"),
]


def api_urlpatterns(base_prefix: str):
    """Build the domain mounts for one API prefix."""
    return [path(f"{base_prefix}{prefix}", include(urlconf)) for prefix, urlconf in API_MOUNTS]


urlpatterns = [
    path("admin/", admin.site.urls),
    # Legacy base. `core.urls` additionally exposes /api/v1/health/ and the
    # public branding endpoints (/api/branding/…), so it stays mounted here
    # exactly as before rather than being duplicated into the versioned tree.
    path("api/", include("core.urls")),
    *api_urlpatterns("api/"),
    # Versioned base (api-design §7) — same views, new prefix.
    path("api/v1/", include((api_urlpatterns(""), "api_v1"), namespace="v1")),
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

# Uploaded media. `re_path` (not `static()`) so it also works with DEBUG=False,
# and it stays disabled in production unless SERVE_MEDIA is enabled.
if getattr(settings, "SERVE_MEDIA", False):
    urlpatterns += [
        re_path(
            r"^%s(?P<path>.*)$" % settings.MEDIA_URL.lstrip("/"),
            serve,
            {"document_root": settings.MEDIA_ROOT},
            name="media",
        ),
    ]

# JSON catch-all for unmatched /api/ routes (core.handlers) — every client of
# this API is a JSON consumer, so a typo'd endpoint must not answer HTML.
handler404 = api_not_found
handler500 = api_server_error
