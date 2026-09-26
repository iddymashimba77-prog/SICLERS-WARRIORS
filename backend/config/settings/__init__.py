"""
Django settings loader.

Reads DJANGO_ENV (default: "development") and imports the matching module.
"""

import os

_ENV = os.environ.get("DJANGO_ENV", "development")

if _ENV == "production":
    from .production import *  # noqa: F401,F403
elif _ENV == "staging":
    from .staging import *  # noqa: F401,F403
elif _ENV == "test":
    from .test_settings import *  # noqa: F401,F403
else:
    from .development import *  # noqa: F401,F403
