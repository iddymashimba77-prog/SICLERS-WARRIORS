"""Versioned health check URLs (``/api/v1/health/…``).

``core.urls`` already exposes ``v1/health/`` under the legacy ``/api/`` base.
This module mounts the same two views at the top of the ``/api/v1/`` tree so
both prefixes resolve, with no duplicated logic.
"""

from django.urls import path

from . import views

app_name = "health_v1"

urlpatterns = [
    path("", views.health_live, name="health-live"),
    path("ready/", views.health_ready, name="health-ready"),
]