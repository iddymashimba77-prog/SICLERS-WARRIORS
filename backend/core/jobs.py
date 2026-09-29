"""Background job queue API (Stage 4.18 — NFR-PERF-004).

``enqueue`` adds a row; ``process_due`` claims and runs due jobs one at a time
within a transaction per row, so a crash mid-run cannot double-execute a job.
A claimed row is marked RUNNING (``updated_at`` bumped); if the worker dies,
the row stays RUNNING and becomes re-claimable once ``RUNNING_STALE_SECONDS``
pass, so it is retried rather than lost or double-run.

Handlers register by task name through ``@job_handler("analytics.sync")``.
An unregistered task is failed immediately with a clear error so a bad
deployment is loud, not silent.

Processors are the ONLY scheduler surface for now: a cron entry running
``manage.py process_jobs`` is the deployment story.
"""

import datetime
import logging
from functools import wraps

from django.db import models, transaction
from django.utils import timezone

from .models import BackgroundJob

logger = logging.getLogger("sicklers.jobs")

# Rows left RUNNING for longer than this (seconds) are considered crashed and
# re-claimable by a subsequent worker.
RUNNING_STALE_SECONDS = 900


def job_handler(task_name):
    """Decorator registering ``fn(payload: dict)`` as the handler for ``task_name``."""

    def decorator(fn):
        _handler_registry[task_name] = fn
        return fn

    return decorator


_handler_registry: dict = {}


def enqueue(*, task, payload=None, scheduled_for=None, max_attempts=3):
    """Create one PENDING job row. Returns the BackgroundJob."""
    if task not in _handler_registry:
        # Non-fatal: workers still fail unknown tasks loudly, but this lets a
        # typo surface at enqueue time.
        logger.warning("enqueue(%s) has no registered handler yet", task)
    return BackgroundJob.objects.create(
        task=task,
        payload=payload or {},
        scheduled_for=scheduled_for or timezone.now(),
        max_attempts=int(max_attempts),
    )


def _claim_next(now, task=None):
    """Claim the next due job (for_update; caller owns the transaction).

    PENDING rows are claimed in ``scheduled_for`` order. A stale RUNNING row
    (crashed worker, no heartbeat for ``RUNNING_STALE_SECONDS``) is re-claimed.
    Returns the row or None.
    """
    stale_limit = now - datetime.timedelta(seconds=RUNNING_STALE_SECONDS)
    candidates = BackgroundJob.objects.select_for_update().filter(
        scheduled_for__lte=now,
        status__in=["PENDING", "RUNNING"],
    )
    if task:
        candidates = candidates.filter(task=task)
    return (
        candidates.filter(
            models.Q(status="PENDING")
            | models.Q(status="RUNNING", updated_at__lte=stale_limit)
        )
        .order_by("scheduled_for", "-created_at")
        .first()
    )


def process_due(limit=10, task=None, now=None):
    """Run up to ``limit`` due jobs.

    Returns a list of ``(BackgroundJob, outcome)`` where outcome is one of
    ``"ok"``, ``"retry"``, ``"failed"``, ``"unknown_task"``. Each row is
    claimed, executed and closed inside its own transaction — a failure in one
    job never rolls back or blocks the others.
    """
    results = []
    now = now or timezone.now()
    for _ in range(int(limit)):
        claimed = None
        with transaction.atomic():
            claimed = _claim_next(now, task=task)
            if claimed is None:
                return results
            if claimed.status != "RUNNING":
                claimed.attempts += 1
            claimed.status = "RUNNING"
            claimed.started_at = timezone.now()
            claimed.save(update_fields=["status", "attempts", "started_at", "updated_at"])
            claimed_pk = claimed.pk

        handler = _handler_registry.get(claimed.task)
        if handler is None:
            with transaction.atomic():
                row = BackgroundJob.objects.select_for_update().get(pk=claimed_pk)
                row.status = "FAILED"
                row.error = f"No handler registered for task {claimed.task!r}."
                row.finished_at = timezone.now()
                row.save(update_fields=["status", "error", "finished_at", "updated_at"])
            results.append((row, "unknown_task"))
            continue

        outcome = "ok"
        error_text = ""
        try:
            handler(claimed.payload)
        except Exception as exc:
            logger.exception(
                "Background job %s failed (attempt %s)", claimed.task, claimed.attempts,
            )
            outcome = "failed"
            error_text = f"{type(exc).__name__}: {exc}"

        with transaction.atomic():
            row = BackgroundJob.objects.select_for_update().get(pk=claimed_pk)
            if outcome == "ok":
                row.status = "SUCCEEDED"
                row.finished_at = timezone.now()
                row.save(update_fields=["status", "finished_at", "updated_at"])
                results.append((row, "ok"))
                continue
            if row.attempts >= row.max_attempts:
                row.status = "FAILED"
                row.error = error_text
                row.finished_at = timezone.now()
                row.save(update_fields=["status", "error", "finished_at", "updated_at"])
                results.append((row, "failed"))
            else:
                row.status = "PENDING"
                row.scheduled_for = timezone.now() + datetime.timedelta(
                    seconds=min(300, 30 * (2 ** (row.attempts - 1)))
                )
                row.error = error_text
                row.finished_at = None
                row.save(update_fields=[
                    "status", "scheduled_for", "error", "finished_at", "updated_at",
                ])
                results.append((row, "retry"))
    return results