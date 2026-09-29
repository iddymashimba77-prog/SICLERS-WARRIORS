"""Audit routing (Stage 4.8)."""

from django.urls import path

from audit import views

app_name = "audit"

urlpatterns = [
    path("admin/audit-logs/export/", views.AdminAuditLogExportView.as_view(), name="audit-log-export"),
    path("admin/audit-logs/", views.AuditLogListView.as_view(), name="audit-log-list"),
]