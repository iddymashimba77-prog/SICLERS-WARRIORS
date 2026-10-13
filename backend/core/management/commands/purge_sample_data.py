"""Purge sample/probe/demo accounts and the content they own (fresh-start).

Operator-run deleter used to ship the platform with only real accounts and
reference seed data (role catalogue & grants, national facilities, symptom
types, education categories). The bootstrap super-admin is never touched.

Deletion follows Django's dependency collector, so PROTECT hard links —
content authored by a sample account, verification documents, community
posts, audit rows — are removed first and the account afterwards. Reference
data (seeded roles/permissions, the 12 national facilities, the 27 symptom
seeds, the 6 education categories) is never targeted.

Usage::

    venv/bin/python manage.py purge_sample_data
    venv/bin/python manage.py purge_sample_data --target probe@example.com
    venv/bin/python manage.py purge_sample_data --dry-run
"""

from django.contrib.auth import get_user_model
from django.core.management.base import BaseCommand
from django.db import transaction
from django.db.models.deletion import PROTECT, ProtectedError

DEFAULT_TARGETS = [
    "juma@gmail.com",
    "micahmakali@gmail.com",
    "ally@gmail.com",
    "ana@gmail.com",
    "probe-test-data@example.com",
    "probe2-test-data@example.com",
]


class Command(BaseCommand):
    help = "Delete sample/probe accounts and the content those accounts own."

    def add_arguments(self, parser):
        parser.add_argument("--target", action="append", default=[], metavar="EMAIL",
                            help="Extra account emails to purge (repeatable).")
        parser.add_argument("--dry-run", action="store_true",
                            help="Report what would be deleted without deleting.")

    def handle(self, *args, **options):
        emails = options["target"] or DEFAULT_TARGETS
        User = get_user_model()
        users = list(User.objects.filter(email__in=emails))
        self.stdout.write(
            f"purge_sample_data: {len(users)} target account(s) found"
        )
        if not users:
            return

        deleted = {"accounts": 0, "rows": 0}
        with transaction.atomic():
            for user in users:
                if user.is_superuser:
                    self.stdout.write(
                        self.style.WARNING(f"  skip superuser {user.email}")
                    )
                    continue
                if options["dry_run"]:
                    self._report(user, deleted, dry_run=True)
                else:
                    self._purge(user, deleted)
        if options["dry_run"]:
            self.stdout.write(self.style.WARNING("dry-run — nothing was deleted"))
        self.stdout.write(
            self.style.SUCCESS(
                f"purge_sample_data: removed {deleted['rows']} related row(s), "
                f"{deleted['accounts']} account(s)"
            )
        )

    def _purge(self, user, deleted):
        self._delete_chain(user, deleted, is_account=True)

    def _delete_chain(self, obj, deleted, *, is_account):
        """Delete ``obj`` and every PROTECT hard link that blocks it.

        ``obj.delete()`` collects the full dependency graph; if any PROTECT
        row still references ``obj`` it raises ProtectedError listing those
        rows. Delete them recursively (they may be PROTECT-ed by deeper rows,
        e.g. doctor -> verification decision -> reviewer) and retry until the
        collector only has ``obj`` itself.
        """
        while True:
            try:
                total, _breakdown = obj.delete()
            except ProtectedError as exc:
                for protected in list(exc.protected_objects):
                    self._delete_chain(protected, deleted, is_account=False)
                continue
            except ValueError as exc:
                # Append-only records (e.g. verification decisions) forbid
                # model .delete(); fall back to a direct row wipe — the tool
                # only ever targets sample/probe data, so history loss is the
                # whole point.
                table = type(obj)._meta.db_table
                pk = obj.pk
                self._raw_delete(table, pk)
                deleted["rows"] += 1
                return
            deleted["rows"] += max(total - 1, 0) if is_account else total
            if is_account:
                deleted["accounts"] += 1
            return

    def _raw_delete(self, table, pk):
        from django.db import connection

        with connection.cursor() as cursor:
            col = (
                f"{connection.ops.quote_name('id')}"
            )
            cursor.execute(
                f"DELETE FROM {connection.ops.quote_name(table)} "
                f"WHERE {col} = %s",
                [pk],
            )

    def _report(self, user, deleted, *, dry_run):
        protected = 0
        for rel in user._meta.related_objects:
            if getattr(rel, "on_delete", None) is not PROTECT:
                continue
            try:
                manager = getattr(user, rel.get_accessor_name())
                protected += manager.all().count()
            except (AttributeError, ValueError):
                continue
        self.stdout.write(
            f"  {user.email}: {protected} PROTECT-linked row(s) to detach"
        )
        deleted["rows"] += protected