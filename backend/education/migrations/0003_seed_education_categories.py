"""Seed approved education categories (Stage 4.11).

Topics approved in `docs/sdlc/03-system-design/mobile-ui-ux-design.md` §21:
  Sickle-cell basics, crisis prevention, nutrition, exercise, careers/family
  planning, living well.

The design lists display names only; machine ``code`` values are stable slugs
used by the API category filter, chosen here for the six approved topics.
"""

from django.db import migrations

CATEGORIES = [
    ("SICKLE_BASICS", "Sickle Cell Basics", 1),
    ("CRISIS_PREVENTION", "Crisis Prevention", 2),
    ("NUTRITION", "Nutrition", 3),
    ("EXERCISE", "Exercise", 4),
    ("CAREERS_FAMILY", "Careers & Family Planning", 5),
    ("LIVING_WELL", "Living Well", 6),
]


def seed(apps, schema_editor):
    EducationCategory = apps.get_model("education", "EducationCategory")
    for code, name, sort_order in CATEGORIES:
        EducationCategory.objects.get_or_create(
            code=code, defaults={"name": name, "sort_order": sort_order},
        )


def unseed(apps, schema_editor):
    EducationCategory = apps.get_model("education", "EducationCategory")
    EducationCategory.objects.filter(code__in=[c[0] for c in CATEGORIES]).delete()


class Migration(migrations.Migration):

    dependencies = [
        ("education", "0002_seed_education_permissions"),
    ]

    operations = [
        migrations.RunPython(seed, unseed),
    ]