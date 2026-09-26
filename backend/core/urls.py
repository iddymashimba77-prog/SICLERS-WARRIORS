"""Health check URLs."""

from django.urls import path

from . import views

app_name = "health"

urlpatterns = [
    path("v1/health/", views.health_live, name="health-live"),
    path("v1/health/ready/", views.health_ready, name="health-ready"),
]
