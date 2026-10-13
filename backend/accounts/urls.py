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
    # roles-permission design § "self-registerable"). Returns the signed-in
    # JWT pair + safe user summary; never exposes privileged role assignment.
    path("register/", views.RegisterView.as_view(), name="register"),
    # Login — email-or-phone identity, returns signed access + refresh pair
    # (§ SD-8 JWT strategy) and account status verbatim for client state.
    path("login/", views.LoginView.as_view(), name="login"),
    # Login PIN — set (authenticated) then sign in with the 4-digit PIN for the
    # device-remembered identity.
    path("pin/set/", views.SetLoginPinView.as_view(), name="pin-set"),
    path("pin/login/", views.LoginPinView.as_view(), name="pin-login"),
    # Logout — revokes the presented refresh token family (jti denylist) so the
    # session cannot be reused (§ SD-8, § 12 logout; auditor "denylist").
    path("logout/", views.LogoutView.as_view(), name="logout"),
    # Refresh — rotate the refresh token, denylist the old jti (§ SD-8 rotation).
    path("refresh/", views.RefreshView.as_view(), name="refresh"),
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
    # Verification-document upload — professional/facility applicants upload a
    # government-issued scan for their C5 verification pipeline. Returns the
    # storage key the caller attaches to a doctors/facilities submit call.
    path("verification/documents/upload/", views.VerificationDocumentUploadView.as_view(), name="verification-document-upload"),
]
