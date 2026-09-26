# 2.12 Requirements Traceability Matrix

Kila requirement inafuatiliwa toka requirements to design to code to test to deployment:

```
Requirement
     │
     ▼
Design Component
     │
     ▼
Code
     │
     ▼
Test Case
     │
     ▼
Deployment
```

## Mfano (draft fill)

| Requirement | Design Component | Code Module | Test Case | Deployment |
|---|---|---|---|---|
| FR-AUTH-002 (Login) | Auth Service | `auth/` | TC-AUTH-002 | API deployment |
| FR-BLD-007 (Match donors) | Blood Matching Service | `blood_matching` | TC-BLD-007 | Matching service deployment |
| FR-MEDREC-003 (Consent grant) | Consent service | `consent/` | TC-MEDREC-003 | API + consent engine |
| FR-EMG-001 (Emergency request) | Emergency service | `emergency/` | TC-EMG-001 | Emergency notify pipeline |
| FR-AI-003 (Emergency escalation) | AI safety layer | `ai/` | TC-AI-003 | AI service deployment |

## Matumizi
- Wakati wa design (Stage 3), kila FR itaunganishwa na design component (module/service/table/endpoint).
- Wakati wa coding (Stage 5), kila component itaunganishwa na code module + test case.
- Wakati wa staging/deployment, kila module ina deployment target.

> Matrix ya kamili (FR × Design × Code × Test × Deploy) itaendelezwa hatua kwa hatua kadri stages zinaendelea.