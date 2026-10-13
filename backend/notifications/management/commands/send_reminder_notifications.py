"""Dispatch scheduled notification batches.

Run periodically (deployment cron/systemd timer) to materialize due medication
*and* clinic-appointment reminders into the inbox through the central
notification service.

Re-run safe: each reminder is coalesced by a stable delivery key —
``med:reminder:<schedule-uid>:<date>`` for doses and
``appt:reminder:<appointment-uid>:<date>:<slot>`` for visits — so overlapping
runs never create duplicates.

Usage::

    venv/bin/python manage.py send_reminder_notifications
"""

from django.core.management.base import BaseCommand

from notifications.reminders import dispatch_all_reminders


class Command(BaseCommand):
    help = "Dispatch due medication and clinic appointment reminder notifications."

    def handle(self, *args, **options):
        counts = dispatch_all_reminders()
        for kind, count in counts.items():
            self.stdout.write(self.style.SUCCESS(f"{kind.capitalize()} reminders dispatched: {count}"))