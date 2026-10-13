"""Consent + clinical-record routing (AUTH-1, FR-MEDREC). Mounted under ``/api/``
and ``/api/v1/`` by ``config/urls.py``.

Consent surface (unchanged):

    GET/POST    /api/consents/
    GET         /api/consents/active/
    GET/PATCH   /api/consents/{uid}/
    POST        /api/consents/{uid}/revoke/
    POST        /api/consents/{uid}/renew/

Clinical record surface (FR-MEDREC-001/002/006). Every flat route below also
exists under the approved nested shape `/api/patients/{patient_uid}/...`:

    GET/POST              /api/medical-records/
    GET/PATCH/DELETE       /api/medical-records/{uid}/
    POST                  /api/medical-records/{uid}/status/
    POST                  /api/medical-records/{uid}/visibility/
    GET/POST              /api/medical-records/{uid}/files/
    GET/DELETE            /api/medical-records/{uid}/files/{file_uid}/
    GET                   /api/medical-records/files/{file_uid}/download/
    GET/POST              /api/medical-records/{uid}/share/
    POST                  /api/medical-records/{uid}/share/revoke/
    GET                   /api/medical-records/{uid}/history/
    GET                   /api/medical-records/history/
    GET                   /api/record-categories/
    GET/POST              /api/clinical-encounters/

    GET/POST              /api/patients/{patient_uid}/medical-records/
    GET/PATCH/DELETE      /api/patients/{patient_uid}/medical-records/{uid}/
    GET/POST              /api/patients/{patient_uid}/medical-records/{uid}/files/
    GET                   /api/patients/{patient_uid}/medical-records/{uid}/history/
    ... and the same status/visibility/share/download actions.
"""

from rest_framework.routers import DefaultRouter

from medical_records import views

router = DefaultRouter()
router.register("consents", views.ConsentViewSet, basename="consent")
router.register(
    "medical-records", views.MedicalRecordViewSet, basename="medical-record",
)
# The same viewset under the patient-nested paths of endpoint-matrix §9, so the
# approved `/patients/{uid}/medical-records` shape and the flat resource share
# one implementation of the read gate.
router.register(
    r"patients/(?P<patient_uid>[^/.]+)/medical-records",
    views.PatientScopedMedicalRecordViewSet,
    basename="patient-medical-record",
)
router.register(
    "record-categories", views.RecordCategoryListView, basename="record-category",
)
router.register(
    "clinical-encounters", views.ClinicalEncounterViewSet, basename="clinical-encounter",
)

urlpatterns = router.urls