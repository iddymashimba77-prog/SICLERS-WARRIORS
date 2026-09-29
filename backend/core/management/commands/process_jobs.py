"""Run the durable background job queue (Stage 4.18 — NFR-PERF-004).

Claims and executes up to ``--limit`` due jobs, then exits. Designed for a
cron/systemd timer (e.g. every minute); no daemon, no extra dependency.

Usage::

    venv/bin/python manage.py process_jobs [--limit 10] [--task analytics.sync]
    venv/bin/python manage.py process_jobs --seconds 300     # bounded loop
"""

import time

from django.core.management.base import BaseCommand

import core.tasks  # noqa: F401  (registers job handlers)
from core.jobs import process_due


class Command(BaseCommand):
    help = "Run due background jobs (idempotent, safe to cron every minute)."

    def add_arguments(self, parser):
        parser.add_argument("--limit", type=int, default=10, metavar="N",
                            help="Jobs to process before exiting (default 10).")
        parser.add_argument("--task", default=None, metavar="NAME",
                            help="Only process jobs for this task name.")
        parser.add_argument("--seconds", type=int, default=0, metavar="S",
                            help="Keep processing until S seconds elapse (default 0 = one batch).")

    def handle(self, *args, **options):
        limit = options["limit"]
        task = options["task"]
        seconds = options["seconds"]
        deadline = time.monotonic() + seconds if seconds else None
        processed = 0
        while True:
            results = process_due(limit=limit, task=task)
            processed += len(results)
            for _row, outcome in results:
                self.stdout.write(f"job outcome: {outcome}")
            if not results:
                break
            if deadline is not None and time.monotonic() >= deadline:
                break
        self.stdout.write(self.style.SUCCESS(f"process_jobs: {processed} job(s) processed"))