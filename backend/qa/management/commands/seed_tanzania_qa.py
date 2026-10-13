"""Seed a comprehensive Tanzania-based QA dataset (tag ``SWQA-TZ-2026``).

Creates 25 independent accounts for every supported non-admin sign-in role,
their organizations/facilities, connected clinical / blood / community /
donation workflows, admin approval + rejection trails, and notification
inboxes — then (optionally) verifies every account can authenticate through the
real login API and writes the QA reports under ``qa/reports/``.

Idempotent: re-running never duplicates rows (deterministic emails/phones and
``uuid5`` ids). The whole run is one transaction — any failure rolls it back.

    python manage.py seed_tanzania_qa
    python manage.py seed_tanzania_qa --skip-login-check
"""

from __future__ import annotations

import os
from pathlib import Path

from django.conf import settings
from django.core.management.base import BaseCommand, CommandError
from django.db import transaction

from qa.seeding import base
from qa.seeding.base import DEFAULT_PASSWORD, PER_ROLE, SeedContext


class Command(BaseCommand):
    help = "Seed the Tanzania QA dataset (SWQA-TZ-2026). Idempotent."

    def add_arguments(self, parser):
        parser.add_argument("--password", default=None, help="Password for every seeded account.")
        parser.add_argument("--per-role", type=int, default=PER_ROLE, help="Accounts per role (default 25).")
        parser.add_argument("--skip-workflows", action="store_true", help="Skip API approval workflows.")
        parser.add_argument("--skip-login-check", action="store_true", help="Skip verifying every account can log in.")
        parser.add_argument("--skip-reports", action="store_true", help="Do not write qa/reports/*.")
        parser.add_argument("--only", default=None, help="Comma-separated phase names to run.")

    def handle(self, *args, **options):
        password = (
            options["password"]
            or os.environ.get("QA_SEED_PASSWORD")
            or DEFAULT_PASSWORD
        )
        base.PER_ROLE = options["per_role"]

        from qa.seeding import (
            identity, relationships, clinical, blood, community,
            content_edu, finance, emergencies, notifications_seed,
            workflows, login_check, reports,
        )

        phases = [
            ("identity", identity.seed),
            ("relationships", relationships.seed),
            ("clinical", clinical.seed),
            ("blood", blood.seed),
            ("community", community.seed),
            ("content", content_edu.seed),
            ("finance", finance.seed),
            ("emergencies", emergencies.seed),
            ("notifications", notifications_seed.seed),
        ]

        only = None
        if options["only"]:
            only = {p.strip() for p in options["only"].split(",") if p.strip()}

        ctx = SeedContext(password=password, admin=None)

        self.stdout.write(self.style.MIGRATE_HEADING(
            f"Seeding Tanzania QA dataset ({base.TAG}) — {options['per_role']} per role"
        ))

        with transaction.atomic():
            for name, fn in phases:
                if only and name not in only:
                    continue
                self.stdout.write(f"  → {name}")
                fn(ctx)

            if not options["skip_workflows"] and (not only or "workflows" in only):
                self.stdout.write("  → workflows (real approval/rejection APIs)")
                workflows.run(ctx)

        if not options["skip_login_check"] and (not only or "login_check" in only):
            self.stdout.write("  → login verification")
            login_check.run(ctx, self.stdout)

        if not options["skip_reports"]:
            out = reports.write_all(ctx)
            self.stdout.write(self.style.SUCCESS(f"Reports written to {out}"))

        self._print_summary(ctx)

    def _print_summary(self, ctx):
        self.stdout.write(self.style.SUCCESS("Seed complete."))
        for key in sorted(ctx.counts):
            self.stdout.write(f"    {key}: {ctx.counts[key]}")
