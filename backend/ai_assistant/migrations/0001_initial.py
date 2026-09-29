"""Initial ai_assistant migration (intentionally table-free).

The approved AI surface adds NO database entity: the database-design has no
``ai_*`` table, so there is nothing to create here. The stage introduces:

* the assistant endpoint surface (AD-2), which persists NOTHING (no transcript,
  no generated text — only audit metadata through the existing ``audit_logs``
  system, traceability TC-AI-003);
* the permission seed in ``0002_seed_ai_permissions``.

``0001_initial`` exists so the app has a stable migration base and an ordered
dependency anchor for the seed.
"""

from django.db import migrations


class Migration(migrations.Migration):

    initial = True

    dependencies = [
        ("accounts", "0003_seed_roles_permissions"),
    ]

    operations: list = []