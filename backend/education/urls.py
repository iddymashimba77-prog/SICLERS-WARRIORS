"""Education routing (Stage 4.11). Mounted under ``/api/`` by config/urls.py.

Canonical baseline (api-design §20 / endpoint-matrix §18, base used here is the
project's ``/api/`` convention):

    /api/education/categories/
    /api/education/content/
    /api/education/content/{uid}/
    /api/education/content/{uid}/submit/
    /api/admin/education/content/
    /api/admin/education/content/{uid}/review/
"""

from django.urls import path
from rest_framework.routers import DefaultRouter

from education import views

router = DefaultRouter()
router.register("education/content", views.EducationalContentViewSet, basename="education-content")
router.register(
    "admin/education/content",
    views.AdminEducationalContentViewSet,
    basename="education-admin-content",
)

urlpatterns = router.urls + [
    path("education/categories/", views.EducationCategoryListView.as_view(), name="education-categories"),
]