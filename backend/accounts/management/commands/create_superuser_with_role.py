"""
Create a superuser and ensure SUPER_ADMIN role is granted.

Usage:
  python manage.py create_superuser_with_role email password --first-name ... --last-name ...
"""
from django.contrib.auth import get_user_model
from django.core.management.base import BaseCommand, CommandError

from accounts.models import Role, UserRole


class Command(BaseCommand):
    help = "Create superuser and grant SUPER_ADMIN role"

    def add_arguments(self, parser):
        parser.add_argument("email", type=str)
        parser.add_argument("password", type=str)
        parser.add_argument("--first-name", type=str, default="Admin")
        parser.add_argument("--last-name", type=str, default="User")
        parser.add_argument("--phone", type=str, default="")
        parser.add_argument("--is-active", type=bool, default=True)

    def handle(self, *args, **options):
        User = get_user_model()
        email = options["email"].strip().lower()
        if not email:
            raise CommandError("Email required")
        if User.objects.filter(email=email).exists():
            user = User.objects.get(email=email)
            user.set_password(options["password"])
            user.first_name = options["first_name"]
            user.last_name = options["last_name"]
            user.phone = options["phone"]
            user.is_active = options["is_active"]
            user.account_status = "ACTIVE"
            user.save()
            self.stdout.write(self.style.WARNING(f"Updated existing user: {email}"))
        else:
            user = User.objects.create_user(
                email=email,
                password=options["password"],
                first_name=options["first_name"],
                last_name=options["last_name"],
                phone=options["phone"],
            )
            user.account_status = "ACTIVE"
            user.is_active = True
            user.save()
            self.stdout.write(self.style.SUCCESS(f"Created user: {email}"))
        try:
            role = Role.objects.get(code="SUPER_ADMIN")
        except Role.DoesNotExist:
            self.stdout.write(self.style.ERROR("SUPER_ADMIN role does not exist. Seed roles first."))
            return
        UserRole.objects.get_or_create(user=user, role=role)
        self.stdout.write(self.style.SUCCESS("Granted SUPER_ADMIN role"))
