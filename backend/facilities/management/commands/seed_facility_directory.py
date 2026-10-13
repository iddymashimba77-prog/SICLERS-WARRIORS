"""Load the national facility directory into a fresh or partial database.

The bootstrap set also ships in migration ``facilities.0004``; this command is
the operator-facing entry point for environments where migrations were
squashed, the table was truncated, or new referral facilities need adding from a
CSV exported by a verification officer.

Idempotent: rows are matched on ``(name, city)`` and existing rows are never
modified, so this is safe to run repeatedly and after officers have edited the
directory.

    manage.py seed_facility_directory              # load the canonical set
    manage.py seed_facility_directory --show       # preview only
    manage.py seed_facility_directory --csv f.csv  # load extra rows (name,
                                                   # facility_type, region, city)
    manage.py seed_facility_directory --pending    # do NOT mark rows verified
"""

import csv
import sys

from django.core.management.base import BaseCommand, CommandError
from django.db import transaction
from django.utils import timezone

from facilities.models import Facility
from facilities.reference_data import CSV_HEADER, NATIONAL_REFERRAL_FACILITIES

VALID_TYPES = {code for code, _ in Facility.FACILITY_TYPE}


class Command(BaseCommand):
    help = "Seed the national facility directory (idempotent)."

    def add_arguments(self, parser):
        parser.add_argument("--csv", dest="csv_path", help="CSV of extra facilities.")
        parser.add_argument(
            "--show", action="store_true", help="Preview the rows without writing.",
        )
        parser.add_argument(
            "--pending",
            action="store_true",
            help="Create rows unverified, for officers who want to review first.",
        )

    def handle(self, *args, **options):
        rows = list(NATIONAL_REFERRAL_FACILITIES)
        if options.get("csv_path"):
            rows.extend(self._read_csv(options["csv_path"]))

        if not rows:
            raise CommandError("No facility rows to load.")

        if options["show"]:
            for name, facility_type, region, city in rows:
                self.stdout.write(f"would create: {name} [{facility_type}] {region} / {city}")
            self.stdout.write(f"{len(rows)} row(s) — nothing written (--show).")
            return

        created, existing = 0, 0
        now = timezone.now()
        with transaction.atomic():
            for name, facility_type, region, city in rows:
                _, was_created = Facility.objects.get_or_create(
                    name=name,
                    city=city,
                    defaults={
                        "facility_type": facility_type,
                        "region": region,
                        "is_verified": not options["pending"],
                        "verified_at": None if options["pending"] else now,
                    },
                )
                if was_created:
                    created += 1
                else:
                    existing += 1

        self.stdout.write(
            self.style.SUCCESS(
                f"Facility directory: {created} created, {existing} already present."
            )
        )
        if options["pending"]:
            self.stdout.write(
                "Rows were created unverified — a verification officer must approve "
                "them before appointments or blood-request venues accept them."
            )

    def _read_csv(self, path):
        try:
            with open(path, newline="", encoding="utf-8") as handle:
                reader = csv.DictReader(handle)
                missing = [c for c in CSV_HEADER if c not in (reader.fieldnames or [])]
                if missing:
                    raise CommandError(
                        f"CSV is missing required column(s): {', '.join(missing)}."
                    )
                rows = []
                for index, raw in enumerate(reader, start=2):
                    name = (raw.get("name") or "").strip()
                    facility_type = (raw.get("facility_type") or "").strip().upper()
                    region = (raw.get("region") or "").strip()
                    city = (raw.get("city") or "").strip()
                    if not name or not city:
                        self.stderr.write(
                            f"row {index}: skipped (name and city are required)."
                        )
                        continue
                    if facility_type not in VALID_TYPES:
                        raise CommandError(
                            f"row {index}: facility_type must be one of "
                            f"{', '.join(sorted(VALID_TYPES))}."
                        )
                    rows.append((name, facility_type, region, city))
                return rows
        except OSError as exc:
            raise CommandError(f"Could not read {path}: {exc}") from exc
