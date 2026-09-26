# 2.7 Use Cases

Use cases kuu za mfumo:

| ID | Use Case |
|---|---|
| UC-001 | Register Account |
| UC-002 | Login |
| UC-003 | Manage Patient Profile |
| UC-004 | Manage Medical Profile |
| UC-005 | Track Medication |
| UC-006 | Manage Appointment |
| UC-007 | Record Symptoms |
| UC-008 | Request Blood |
| UC-009 | Register Blood Donor |
| UC-010 | Match Blood Donor |
| UC-011 | Respond to Blood Request |
| UC-012 | Create Emergency Request |
| UC-013 | Verify Doctor |
| UC-014 | Access Authorized Medical Record |
| UC-015 | Chat With Doctor |
| UC-016 | Create Campaign |
| UC-017 | Donate Money |
| UC-018 | Process Payment |
| UC-019 | Create Community Post |
| UC-020 | Report Content |
| UC-021 | Publish Health Education |
| UC-022 | Receive Notification |
| UC-023 | Manage Consent |
| UC-024 | Generate Reports |
| UC-025 | AI Health Assistance |

## Mfano:  UC-008 Request Blood (draft)

- **Actor(s):** Patient (au authorized user)
- **Precondition:** User ameauthenthicatewa; ameanzisha medical profile ya msingi.
- **Main flow:**
  1. User anabofya "Request Blood".
  2. System inachukua blood group (kutoka profile au kuuliza).
  3. User anaeleza urgency na sehemu.
  4. System inaunda blood request (pending verification).
  5. System inaruhusu mwachiliaja ku-response.
- **Postcondition:** Request inaonekana kwa eligible donors baada ya verification.

> Use case kamili za decentralized zitaandikwa na design zao kwenye Stage 3 (API design) na Stage 4/5 (sequence flow).