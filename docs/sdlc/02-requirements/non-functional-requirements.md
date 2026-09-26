# 2.4 Non-Functional Requirements

## Security

| ID | Requirement |
|---|---|
| NFR-SEC-001 | Sensitive data shall be protected during transmission. |
| NFR-SEC-002 | Passwords shall never be stored in plaintext. |
| NFR-SEC-003 | Sensitive medical information shall require authorization. |
| NFR-SEC-004 | Critical operations shall be auditable. |
| NFR-SEC-005 | The system shall implement protection against common web/API attacks. |

## Performance

| ID | Requirement |
|---|---|
| NFR-PERF-001 | Normal API operations should respond within an agreed performance threshold under defined test conditions. |
| NFR-PERF-002 | The system shall support pagination for large datasets. |
| NFR-PERF-003 | Heavy operations should be processed asynchronously where appropriate. |

## Availability

| ID | Requirement |
|---|---|
| NFR-AVL-001 | Production services should be designed for high availability. |
| NFR-AVL-002 | The system shall provide health monitoring. |

## Scalability

| ID | Requirement |
|---|---|
| NFR-SCAL-001 | The architecture shall support increasing numbers of patients, doctors, donors, requests, transactions and messages without requiring fundamental architectural redesign. |

## Usability

| ID | Requirement |
|---|---|
| NFR-USE-001 | The mobile interface shall be understandable to users with different levels of digital literacy. |
| NFR-USE-002 | Critical workflows shall require minimal unnecessary steps. |
| NFR-USE-003 | Emergency-related interfaces shall prioritize clarity and speed. |

## Maintainability

| ID | Requirement |
|---|---|
| NFR-MAIN-001 | The system shall use modular architecture. |
| NFR-MAIN-002 | Business logic shall be separated from presentation logic. |
| NFR-MAIN-003 | The system shall provide automated tests for critical functionality. |

## Acceptance thresholds (dhafini)

- NFR-PERF-001: API p95 latency target itabainishwa wakati wa design na load testing (agreed threshold e.g. 500 ms kwa normal reads).
- NFR-AVL-001: target 99.5% uptime for production; inathibitishwa na monitoring + alerting.
- NFR-SEC-001: TLS 1.2+ lazima kwa usafirishaji wote (HTTPS).