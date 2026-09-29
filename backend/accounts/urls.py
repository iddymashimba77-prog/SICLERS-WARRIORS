"""Auth endpoint routing for Sickler's Warriors (§ SD-9 / § 07 API design).

All endpoints are mounted under ``/api/v1/auth/`` by ``config/urls.py`` and
follow the approved machine-readable endpoint matrix exactly — no invented
paths, no aliases, no duplicate registrations (§ D-REST-… / § 07).
"""

from django.urls import path

from . import views

app_name = "auth"

urlpatterns = [
    # Registration — self-registerable roles only (PATIENT, CAREGIVER; § C17,
    # roles-permission design § "self-registerable"). Returns user + email
    # verification one-time token; never exposes privileged role assignment.
    path("register/", views.RegisterView.as_view(), name="register"),
    # Login — email-or-phone identity, returns signed access + refresh pair
    # (§ SD-8 JWT strategy) and account status verbatim for client state.
    path("login/", views.LoginView.as_view(), name="login"),
    # Logout — revokes the presented refresh token family (jti denylist) so the
    # session cannot be reused (§ SD-8, § 12 logout; auditor "denylist").
    path("logout/", views.LogoutView.as_view(), name="logout"),
    # Refresh — rotate the refresh token, denylist the old jti (§ SD-8 rotation).
    path("refresh/", views.RefreshView.as_view(), name="refresh"),
    # Issue replacement tokens for a given password-reset/verification one-time
    # token (consumed above) — present but conceptually unused unless the
    # approved design calls for a token-swap; kept for endpoint parity with § 07.
    path("verify/", views.LoginView.as_view(), name="verify"),
    # Email verification — consume the single-use code (FR-AUTH-004 / AUTH-005).
    path("verify/email/", views.EmailVerifyView.as_view(), name="verify-email"),
    # Email verification resend — uniform 202, rate-limited (no enumeration).
    path("verify/email/resend/", views.EmailVerifyResendView.as_view(), name="verify-email-resend"),
    # Password reset request — always 202 regardless of account existence (§ §
    # never reveals whether an account exists; uniform response).
    path("password-reset/request/", views.PasswordResetRequestView.as_view(), name="password-reset-request"),
    # Password reset confirm — validates the expiring one-time token, sets the
    # new password, triggers denylist of active sessions (§ SD-8).
    path("password-reset/confirm/", views.PasswordResetConfirmView.as_view(), name="password-reset-confirm"),
    # Change password — authenticated; requires current password (§ 18).
    path("password/change/", views.ChangePasswordView.as_view(), name="change-password"),
    # Authenticated identity + safe profile ("me") for client state (§ 23/24).
    path("me/", views.MeView.as_view(), name="me"),
    # Profile picture upload/replace — owner-only, validated + re-encoded server
    # side; returns the updated user summary (§ 35 characteristic-of-requestor).
    path("me/photo/", views.MeUploadPhotoView.as_view(), name="me-photo"),
]
