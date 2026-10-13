"""Appointment routing (§11).

Mounted at both ``/api/`` and ``/api/v1/`` by ``config/urls.py``:

    GET    /api/appointments/                 own / consented / assigned list
    POST   /api/appointments/                 book a visit
    GET    /api/appointments/reminders/due    reminder obligations (staff)
    GET    /api/appointments/{uid}/           detail
    PATCH  /api/appointments/{uid}/           edit time / reminders
    DELETE /api/appointments/{uid}/           cancel (soft, history retained)
    POST   /api/appointments/{uid}/status/    audited status transition
"""

from django.urls import path

from appointments import views

app_name = "appointments"

urlpatterns = [
    path("appointments/", views.AppointmentListCreateView.as_view(), name="appointment-list"),
    path(
        "appointments/reminders/due",
        views.AppointmentReminderStateView.as_view(),
        name="appointment-reminders-due",
    ),
    path(
        "appointments/<uuid:uid>/",
        views.AppointmentDetailView.as_view(),
        name="appointment-detail",
    ),
    path(
        "appointments/<uuid:uid>/status/",
        views.AppointmentStatusView.as_view(),
        name="appointment-status",
    ),
]