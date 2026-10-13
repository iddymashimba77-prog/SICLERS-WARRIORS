"""Bootstrap the national facility directory with published referral facilities.

The `facilities` table shipped empty, which left every downstream surface with
nothing to select: the patient treating-facility field, the blood-request venue
picker and clinic appointments all resolve against this directory.

These are long-established, publicly documented Tanzanian referral facilities.
Only fields that are verifiable from public reference material are populated —
name, type, region and city. Street addresses, phone numbers and registration
numbers are deliberately left blank: fabricating a registration number would let
an unverified organisation present itself as a licensed facility.

``is_verified`` is set so the directory is usable immediately; ``verified_by``
stays NULL because no individual officer vouched for the row. A verification
officer should review this bootstrap set and re-verify through the normal
facility workflow (see ``manage.py seed_facility_directory --help``).

Idempotent: keyed on ``(name, city)`` with ``get_or_create``, so re-running the
migration or the management command never duplicates or overwrites officer
changes to existing rows.
"""

import django.utils.timezone
from django.db import migrations

from facilities.reference_data import NATIONAL_REFERRAL_FACILITIES


def seed_facilities(apps, schema_editor):
    Facility = apps.get_model("facilities", "Facility")
    now = django.utils.timezone.now()
    for name, facility_type, region, city in NATIONAL_REFERRAL_FACILITIES:
        Facility.objects.get_or_create(
            name=name,
            city=city,
            defaults={
                "facility_type": facility_type,
                "region": region,
                "is_verified": True,
                "verified_at": now,
            },
        )


def unseed_facilities(apps, schema_editor):
    """Remove only the rows this migration created (never officer edits)."""
    Facility = apps.get_model("facilities", "Facility")
    Facility.objects.filter(
        name__in=[row[0] for row in NATIONAL_REFERRAL_FACILITIES],
        verified_by__isnull=True,
    ).delete()


class Migration(migrations.Migration):

    dependencies = [
        ("facilities", "0003_facility_facility_type_ck"),
    ]

    operations = [
        migrations.RunPython(seed_facilities, unseed_facilities),
    ]