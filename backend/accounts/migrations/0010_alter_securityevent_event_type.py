"""Declares the full SecurityEvent taxonomy (AUTH-1).

SSoT: accounts/models.SecurityEvent.KIND. Adds the auth events that were
already emitted but undeclared (REGISTER, LOGOUT, PASSWORD_CHANGE) plus the
AUTH-1 workflow events (doctor verification, consent grant/renew/revoke,
caregiver invite/accept/decline/revoke, emergency access grant/revoke). The
admin security-events filter rejects any type outside KIND, so every emitted
type must be declared here (accounts/admin_views check).
"""

from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ("accounts", "0009_alter_securityevent_event_type"),
    ]

    operations = [
        migrations.AlterField(
            model_name="securityevent",
            name="event_type",
            field=models.CharField(
                choices=[
                    ("LOGIN_SUCCESS", "LOGIN_SUCCESS"),
                    ("LOGIN_FAILED", "LOGIN_FAILED"),
                    ("MFA_CHALLENGE", "MFA_CHALLENGE"),
                    ("MFA_FAILED", "MFA_FAILED"),
                    ("REGISTER", "REGISTER"),
                    ("LOGOUT", "LOGOUT"),
                    ("PASSWORD_CHANGE", "PASSWORD_CHANGE"),
                    ("PASSWORD_RESET", "PASSWORD_RESET"),
                    ("ROLE_CHANGE", "ROLE_CHANGE"),
                    ("TOKEN_REFRESH", "TOKEN_REFRESH"),
                    ("ADMIN_ACTION", "ADMIN_ACTION"),
                    ("PROFILE_CREATED", "PROFILE_CREATED"),
                    ("PROFILE_UPDATED", "PROFILE_UPDATED"),
                    ("PROFILE_VIEWED", "PROFILE_VIEWED"),
                    ("MEDICATION_CREATED", "MEDICATION_CREATED"),
                    ("MEDICATION_UPDATED", "MEDICATION_UPDATED"),
                    ("MEDICATION_DEACTIVATED", "MEDICATION_DEACTIVATED"),
                    ("DOSE_LOGGED", "DOSE_LOGGED"),
                    ("SYMPTOM_RECORDED", "SYMPTOM_RECORDED"),
                    ("BLOOD_DONOR_CREATED", "BLOOD_DONOR_CREATED"),
                    ("BLOOD_DONOR_UPDATED", "BLOOD_DONOR_UPDATED"),
                    ("BLOOD_REQUEST_CREATED", "BLOOD_REQUEST_CREATED"),
                    ("BLOOD_REQUEST_VERIFIED", "BLOOD_REQUEST_VERIFIED"),
                    ("BLOOD_REQUEST_REJECTED", "BLOOD_REQUEST_REJECTED"),
                    ("BLOOD_REQUEST_CANCELLED", "BLOOD_REQUEST_CANCELLED"),
                    ("BLOOD_MATCH_RUN", "BLOOD_MATCH_RUN"),
                    ("BLOOD_MATCH_RESPONDED", "BLOOD_MATCH_RESPONDED"),
                    ("DONATION_RECORDED", "DONATION_RECORDED"),
                    ("EMERGENCY_CREATED", "EMERGENCY_CREATED"),
                    ("EMERGENCY_VALIDATED", "EMERGENCY_VALIDATED"),
                    ("EMERGENCY_VIEWED", "EMERGENCY_VIEWED"),
                    ("EMERGENCY_RESPONDED", "EMERGENCY_RESPONDED"),
                    ("EMERGENCY_ESCALATED", "EMERGENCY_ESCALATED"),
                    ("EMERGENCY_RESOLVED", "EMERGENCY_RESOLVED"),
                    ("EMERGENCY_CANCELLED", "EMERGENCY_CANCELLED"),
                    ("EMERGENCY_ACCESS_GRANTED", "EMERGENCY_ACCESS_GRANTED"),
                    ("EMERGENCY_ACCESS_REVOKED", "EMERGENCY_ACCESS_REVOKED"),
                    ("DOCTOR_VERIFICATION_SUBMITTED", "DOCTOR_VERIFICATION_SUBMITTED"),
                    ("DOCTOR_VERIFIED", "DOCTOR_VERIFIED"),
                    ("DOCTOR_REJECTED", "DOCTOR_REJECTED"),
                    ("DOCTOR_SUSPENDED", "DOCTOR_SUSPENDED"),
                    ("CONSENT_GRANTED", "CONSENT_GRANTED"),
                    ("CONSENT_RENEWED", "CONSENT_RENEWED"),
                    ("CONSENT_REVOKED", "CONSENT_REVOKED"),
                    ("CAREGIVER_INVITED", "CAREGIVER_INVITED"),
                    ("CAREGIVER_ACCEPTED", "CAREGIVER_ACCEPTED"),
                    ("CAREGIVER_DECLINED", "CAREGIVER_DECLINED"),
                    ("CAREGIVER_REVOKED", "CAREGIVER_REVOKED"),
                ],
                max_length=40,
            ),
        ),
    ]