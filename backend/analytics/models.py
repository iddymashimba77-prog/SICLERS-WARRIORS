"""Aggregate analytics domain (approved Stage 4.14).

Source of truth — docs/sdlc/03-system-design/database-design.md §19:
  analytics_snapshots | metric_key, dimensions JSONB, value numeric,
      granularity CHECK(DAILY WEEKLY MONTHLY), measured_at,
      UNIQUE(metric_key, dimensions, granularity, measured_at)

Privacy contract (AD-7 / database-design §19):
  * These rows store AGGREGATES ONLY — no PHI, no duplicated sensitive or
    medical data. Every value is a count / sum / average over a population.
  * Dimensions carry categorical slices only (status, urgency, severity,
    category, symptom-type code, document type) — never identifiers, notes,
    names, contact details or payloads.
  * The unique key is enforced over the canonical dimensions JSON (service
    layer normalises key order so idempotent aggregation jobs never double
    count — see `analytics.services`).
"""

from django.db import models

GRANULARITIES = ["DAILY", "WEEKLY", "MONTHLY"]
GRANULARITY_DEFAULT = "DAILY"


class AnalyticsSnapshot(models.Model):
    GRANULARITY = [(value, value) for value in GRANULARITIES]

    metric_key = models.CharField(max_length=100, db_index=True)
    dimensions = models.JSONField(default=dict, blank=True)
    value = models.DecimalField(max_digits=20, decimal_places=6)
    granularity = models.CharField(
        max_length=10, choices=GRANULARITY, default=GRANULARITY_DEFAULT,
    )
    measured_at = models.DateTimeField(db_index=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        db_table = "analytics_snapshots"
        ordering = ["metric_key", "measured_at"]
        constraints = [
            models.CheckConstraint(
                condition=models.Q(granularity__in=GRANULARITIES),
                name="anl_snap_granularity_ck",
            ),
            models.UniqueConstraint(
                fields=["metric_key", "dimensions", "granularity", "measured_at"],
                name="anl_snap_metric_dim_gr_ts_uk",
            ),
        ]
        indexes = [
            models.Index(
                fields=["metric_key", "measured_at"], name="anl_snap_kpi_ts_idx",
            ),
        ]

    def __str__(self):
        dims = ",".join(f"{k}={v}" for k, v in sorted(self.dimensions.items()))
        return f"{self.metric_key}{{{dims}}}={self.value} ({self.granularity})"