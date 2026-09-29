"""Materialize approved analytics DAILY snapshots (NFR-PERF-003).

Run periodically (deployment cron/systemd timer) so the reporting endpoints
and dashboards read pre-aggregated ``analytics_snapshots`` rows instead of
scanning domain tables live. Re-run safe: every row is idempotently upserted
on the approved unique key (metric_key, dimensions, granularity, measured_at),
so overlapping runs never double-count and backfill is just ``--days N``.

Usage::

    venv/bin/python manage.py sync_analytics_snapshots --days 90
    venv/bin/python manage.py sync_analytics_snapshots            # last 30 days
"""

import datetime

from django.core.management.base import BaseCommand, CommandError
from django.utils import timezone

from analytics.services import compute_daily


class Command(BaseCommand):
    help = "Compute/refresh analytics_snapshots for a trailing window of days."

    def add_arguments(self, parser):
        parser.add_argument(
            "--days", type=int, default=30, metavar="N",
            help="Trailing days to (re)aggregate, including today (default 30).",
        )

    def handle(self, *args, **options):
        days = options["days"]
        if days < 1 or days > 1830:
            raise CommandError("--days must be between 1 and 1830.")
        today = timezone.now().replace(hour=0, minute=0, second=0, microsecond=0)
        written = 0
        for i in range(days - 1, -1, -1):
            written += compute_daily(today - datetime.timedelta(days=i))
        self.stdout.write(
            self.style.SUCCESS(f"Analytics snapshots synced: {written} rows")
        )