"""Store the platform logo bytes in the database (Render free tier keeps the
Postgres volume but wipes the filesystem, so FileField-only logos 500 after a
restart)."""

from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ("core", "0003_seed_branding_permission"),
    ]

    operations = [
        migrations.AddField(
            model_name="appbranding",
            name="logo_data",
            field=models.BinaryField(blank=True, null=True),
        ),
    ]
