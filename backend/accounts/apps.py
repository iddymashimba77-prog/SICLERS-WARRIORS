from django.apps import AppConfig


class AccountsConfig(AppConfig):
    name = "accounts"

    def ready(self):
        # Permission classes and serializer selection routinely call
        # ``request.user.has_perm_code(...)``. ``AnonymousUser`` is not our
        # identity model and does not carry that helper, so unauthenticated
        # requests (and schema generation, which probes views with an anonymous
        # user) raised ``AttributeError``. An anonymous principal by definition
        # holds no permission code, so the correct default is ``False``.
        from django.contrib.auth.models import AnonymousUser

        if not hasattr(AnonymousUser, "has_perm_code"):
            AnonymousUser.has_perm_code = lambda self, code: False
