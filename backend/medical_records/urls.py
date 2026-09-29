"""Consent routing (AUTH-1). Mounted under ``/api/`` by config/urls.py.

    GET/POST    /api/consents/
    GET         /api/consents/active/
    GET/PATCH   /api/consents/{uid}/
    POST        /api/consents/{uid}/revoke/
    POST        /api/consents/{uid}/renew/
"""

from rest_framework.routers import DefaultRouter

from medical_records import views

router = DefaultRouter()
router.register("consents", views.ConsentViewSet, basename="consent")

urlpatterns = router.urls