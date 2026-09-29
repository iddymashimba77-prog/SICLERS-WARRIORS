"""Performance & scalability test app (Stage 4.18).

No production models/views — this app exists to host the deterministic
query-count, pagination, caching, job-queue and health-observability tests
that gate NFR-PERF-001..004, plus a repeatable baseline reporting command.

``manage.py measure_perf_baseline`` runs a representative endpoint matrix
under the ephemeral SQLite profile and prints query counts + timings so the
numbers in the 4.18 reports stay reproducible.
"""

from django.apps import AppConfig


class PerformanceConfig(AppConfig):
    default_auto_field = "django.db.models.BigAutoField"
    name = "performance"
    verbose_name = "Performance baseline"