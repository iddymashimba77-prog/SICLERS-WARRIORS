"""Registered background tasks (Stage 4.18).

Central registration file for ``core.jobs`` handlers. Importing this module
registers every task; ``core.jobs.process_due`` runs whatever is due.

Admin/maintenance tasks only — no patient-data tasks belong here.
"""

from core.jobs import job_handler


@job_handler("analytics.sync")
def analytics_sync(payload):
    """(Re)materialize the analytics DAILY snapshots via the job queue.

    Mirrors ``sync_analytics_snapshots`` (identical, idempotent semantics);
    ``payload.days`` defaults to 30. Run on a cron/systemd timer rather than a
    500-row loop so reporting excessive tasks never block an HTTP worker.
    """
    import datetime

    from django.utils import timezone

    from analytics.services import compute_daily

    days = int((payload or {}).get("days", 30))
    today = timezone.now().replace(hour=0, minute=0, second=0, microsecond=0)
    written = 0
    for i in range(days - 1, -1, -1):
        written += compute_daily(today - datetime.timedelta(days=i))
    return written