"""Tanzania QA seeding package.

Idempotent, deterministic seeding of a realistic Tanzania-based test dataset
for the Sickler's Warriors platform. Imported only by the
``seed_tanzania_qa`` management command (and its tests); never by production
code.

Every seeded row is tagged with the ``SWQA-TZ-2026`` marker (in emails/phones/
names/notes) so the dataset is identifiable and can be re-run safely.
"""
