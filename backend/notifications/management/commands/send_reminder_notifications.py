"""Dispatch scheduled notification batches.

Run periodically (deployment cron/systemd timer) to materialize due medication
reminders into the inbox through the central notification service.

Re-run safe: reminders are coalesced per (schedule, day) with stable
delivery keys, so overlapping runs never create duplicates.

Usage::

    venv/bin/python manage.py send_reminder_notifications
"""

from django.core.management.base import BaseCommand

from notifications.reminders import dispatch_medication_reminders


class Command(BaseCommand):
    help = "Dispatch due medication reminder notifications."

    def handle(self, *args, **options):
        created = dispatch_medication_reminders()
        self.stdout.write(self.style.SUCCESS(f"Medication reminders dispatched: {created}"))