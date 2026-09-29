"""Analytics & reporting routing (Stage 4.14).

Mounted under ``/api/`` by ``config/urls.py``. Approved endpoint surface
(api-design §22 / api-endpoint-matrix §12, admin rows):

    GET  /api/admin/dashboard/    analytics.view (SUP/ADM, C6 VO)
    GET  /api/admin/analytics/    analytics.view (+ analytics.export CSV, C4)

The `/ai/trends` / report-export gap endpoints from the design (AD-2,
``POST /admin/exports``) are NOT routed — they are placeholders awaiting
sign-off (documented in 4.14-implementation note).
"""

from django.urls import path

from . import views

app_name = "analytics"

urlpatterns = [
    path("admin/dashboard/", views.AdminDashboardView.as_view(), name="admin-dashboard"),
    path("admin/analytics/", views.AdminAnalyticsView.as_view(), name="admin-analytics"),
]