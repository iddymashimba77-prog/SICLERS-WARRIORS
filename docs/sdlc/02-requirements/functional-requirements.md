# 2.3 Functional Requirements

Format: `FR-[MODULE]-[NUMBER]`

## Authentication (AUTH)

| ID | Requirement |
|---|---|
| FR-AUTH-001 | System shall allow a new user to register. |
| FR-AUTH-002 | System shall authenticate registered users. |
| FR-AUTH-003 | System shall support password reset. |
| FR-AUTH-004 | System shall verify user identity using configured verification mechanisms. |
| FR-AUTH-005 | System shall implement role-based access control. |
| FR-AUTH-006 | System shall terminate/logout authenticated sessions securely. |

## Patient Management (PAT)

| ID | Requirement |
|---|---|
| FR-PAT-001 | System shall allow patients to create and update their profile. |
| FR-PAT-002 | System shall allow patients to maintain their medical profile. |
| FR-PAT-003 | System shall allow patients to define emergency contacts. |
| FR-PAT-004 | System shall allow patients to manage caregiver permissions. |

## Medication (MED)

| ID | Requirement |
|---|---|
| FR-MED-001 | System shall allow users to register medications. |
| FR-MED-002 | System shall allow users to define medication schedules. |
| FR-MED-003 | System shall send medication reminders. |
| FR-MED-004 | System shall allow users to record whether a medication was taken. |
| FR-MED-005 | System shall maintain medication adherence history. |
| FR-MED-006 | System shall generate adherence statistics. |
| FR-MED-007 | System shall record the prescriber's instructions for a medication separately from its reminder schedule, so directions for the patient are not conflated with a single reminder time. |

## Appointments (APP)

| ID | Requirement |
|---|---|
| FR-APP-001 | System shall allow users to create clinic appointments. |
| FR-APP-002 | System shall provide appointment reminders. |
| FR-APP-003 | System shall maintain appointment history. |
| FR-APP-004 | System shall allow authorized healthcare professionals to participate in appointment workflows. |

## Medical Records (MEDREC)

| ID | Requirement |
|---|---|
| FR-MEDREC-001 | System shall maintain patient medical records. |
| FR-MEDREC-002 | System shall restrict medical records to authorized users. |
| FR-MEDREC-003 | System shall allow patients to grant access to specified healthcare professionals. |
| FR-MEDREC-004 | System shall support access expiration. |
| FR-MEDREC-005 | System shall support access revocation. |
| FR-MEDREC-006 | System shall record access to sensitive medical information. |
| FR-MEDREC-007 | System shall maintain an append-only history of every clinical record create, edit, status change, file change, and read. A history row cannot be updated or deleted, including through a bulk queryset operation, and cannot lose its subject. |
| FR-MEDREC-008 | System shall let a patient share one record with one named member, optionally time-boxed, and revoke that share with immediate effect. |
| FR-MEDREC-009 | System shall let a patient keep a single record out of every consent-derived read set, and shall never expose clinical attachments through a public URL. |

## Symptoms / Pain (SYM)

| ID | Requirement |
|---|---|
| FR-SYM-001 | System shall allow patients to record symptoms. |
| FR-SYM-002 | System shall allow patients to record pain severity. |
| FR-SYM-003 | System shall allow patients to record possible triggers. |
| FR-SYM-004 | System shall display historical symptom information. |
| FR-SYM-005 | System shall generate trend information from recorded data. |

## Blood Donation (BLD)

| ID | Requirement |
|---|---|
| FR-BLD-001 | System shall allow users to register as blood donors. |
| FR-BLD-002 | System shall record blood group information. |
| FR-BLD-003 | System shall record donor availability. |
| FR-BLD-004 | System shall record last donation date. |
| FR-BLD-005 | System shall allow authorized users to create blood requests. |
| FR-BLD-006 | System shall classify blood requests according to urgency. |
| FR-BLD-007 | System shall identify potentially suitable donors. |
| FR-BLD-008 | System shall notify eligible donors. |
| FR-BLD-009 | System shall allow donors to accept or decline requests. |
| FR-BLD-010 | System shall track request fulfillment. |
| FR-BLD-011 | System shall maintain an append-only history of every blood-request lifecycle decision: submission, verification, rejection, cancellation, matching round, donor acceptance, donation and fulfilment. A history row cannot be updated or deleted, including through a bulk queryset operation, and cannot lose its subject, and each row names the actor who decided. |
| FR-BLD-012 | System shall let the requester and authorized reviewers read that history, and shall not confirm the existence of a request to anyone else. |

## Emergency (EMG)

| ID | Requirement |
|---|---|
| FR-EMG-001 | System shall allow authorized users to create emergency requests. |
| FR-EMG-002 | System shall classify emergency requests by severity. |
| FR-EMG-003 | System shall prioritize critical requests. |
| FR-EMG-004 | System shall notify relevant responders. |
| FR-EMG-005 | System shall track emergency response status. |
| FR-EMG-006 | System shall maintain an emergency request audit trail. |

## Doctors (DOC)

| ID | Requirement |
|---|---|
| FR-DOC-001 | System shall allow healthcare professionals to register. |
| FR-DOC-002 | System shall collect professional verification information. |
| FR-DOC-003 | System shall allow administrators to approve/reject verification. |
| FR-DOC-004 | System shall distinguish verified and unverified professionals. |
| FR-DOC-005 | System shall allow patients to interact with verified professionals according to permissions. |
| FR-DOC-006 | System shall maintain an append-only history of every professional-verification decision: submission, approval, rejection, suspension, reinstatement and resubmission, each with the deciding officer and the reason given. A history row cannot be updated or deleted, including through a bulk queryset operation, and cannot lose its subject. |
| FR-DOC-007 | System shall let a professional read their own verification history at any time, so that a rejection remains answerable after a later approval, and shall restrict any other reader to authorized verifiers. |

## Care Team (PSY / SOC)

| ID | Requirement |
|---|---|
| FR-CARE-001 | System shall support a PSYCHOLOGIST role for licensed mental-health professionals, verified through the same professional registry and decision trail as doctors. |
| FR-CARE-002 | System shall support a SOCIAL_SUPPORT role for care and navigation workers, verified through the same professional registry and decision trail as doctors. |
| FR-CARE-003 | A care-team role shall never be satisfied by being a different profession: an approved psychologist or support worker must not pass a doctor-only gate such as prescribing. |
| FR-CARE-004 | System shall let a patient start a support conversation with a verified psychologist or social support worker, and shall refuse an applicant who is pending, rejected or suspended. |
| FR-CARE-005 | A psychologist may create and update clinical records only where an active consent scope authorizes the patient, attributed to the psychologist as the author; a social support worker may read such records but never author them, even where a consent exists. |
| FR-CARE-006 | Neither role may be self-registered; both are administratively assigned, and verification must be approved by an authorized verification officer before any clinical or chat function becomes available. |

## Financial Donations (CAM)

| ID | Requirement |
|---|---|
| FR-CAM-001 | System shall allow authorized users/organizations to create fundraising campaigns. |
| FR-CAM-002 | System shall require campaign verification before public fundraising. |
| FR-CAM-003 | System shall display campaign progress. |
| FR-CAM-004 | System shall record donations. |
| FR-CAM-005 | System shall maintain donation history. |
| FR-CAM-006 | System shall generate donation transaction records/receipts. |

## Payments (PAY)

| ID | Requirement |
|---|---|
| FR-PAY-001 | System shall support multiple payment providers. |
| FR-PAY-002 | System shall create a unique transaction reference. |
| FR-PAY-003 | System shall track transaction status. |
| FR-PAY-004 | System shall verify payment status server-side. |
| FR-PAY-005 | System shall handle successful, failed, pending and refunded transactions. |

## Community (COM)

| ID | Requirement |
|---|---|
| FR-COM-001 | System shall allow users to create community posts. |
| FR-COM-002 | System shall allow comments. |
| FR-COM-003 | System shall allow users to report inappropriate content. |
| FR-COM-004 | System shall allow administrators to moderate reported content. |
| FR-COM-005 | System shall maintain moderation records. |

## Notifications (NOT)

| ID | Requirement |
|---|---|
| FR-NOT-001 | System shall send medication reminders. |
| FR-NOT-002 | System shall send appointment reminders. |
| FR-NOT-003 | System shall send blood request notifications. |
| FR-NOT-004 | System shall send emergency notifications. |
| FR-NOT-005 | System shall notify users of relevant payment events. |
| FR-NOT-006 | System shall provide notification preferences. |

## Health Education (EDU)

| ID | Requirement |
|---|---|
| FR-EDU-001 | System shall provide sickle cell educational content. |
| FR-EDU-002 | System shall categorize educational content. |
| FR-EDU-003 | System shall support content review. |
| FR-EDU-004 | System shall display publication/update information. |
| FR-EDU-005 | System shall allow a healthcare author to attach a downloadable document (PDF, PPTX, DOCX or image) to an educational article, validated server-side and removable by the author, with published articles immutable until unpublished. |

## AI / Intelligence (AI)

| ID | Requirement |
|---|---|
| FR-AI-001 | System shall provide AI-assisted health education. |
| FR-AI-002 | System shall provide non-diagnostic informational assistance. |
| FR-AI-003 | System shall identify potentially emergency-related conversations for escalation according to defined safety rules. |
| FR-AI-004 | System shall provide health trend analysis from eligible patient-generated data. |
| FR-AI-005 | System shall provide risk indicators only where validated models and appropriate clinical governance are available. |
| FR-AI-006 | System shall clearly communicate that AI output is not a medical diagnosis. |

> Innovations za kubaki zikireferred na FR IDs zao (Health Timeline, Pain/Symptom Intelligence, Smart Blood Matching, Emergency Response Network, Consent-based Medical Records, AI Assistant, Risk/Early Warning Engine).