# 3.8 Security & Privacy Architecture

> **SUPERSEDED** — replaced by the full Stage 3.8 security deliverables
> (`security-design.md` and companions: `security-risk-register.md`,
> `data-classification-security.md`, `security-control-matrix.md`,
> `security-api-traceability.md`, `security-database-traceability.md`,
> `security-implementation-checklist.md`, `security-review.md`).
> Kept for history only; do not use as the active design.

## 3.8.1 Security Layers

```
User
 ↓
Authentication
 ↓
Token Validation
 ↓
Role Check
 ↓
Permission Check
 ↓
Consent Check (medical data)
 ↓
Business Rule Check
 ↓
Resource Access
 ↓
Audit Log
```

## 3.8.2 Authentication

- **Token-based**: JWT access + refresh tokens (DRF default token or JWT library).
- Password hashing: Django's PBKDF2 + salt (default).
- MFA: TOTP-based MFA (optional, admin-required).
- Rate limiting: login attempts, password reset requests (per IP/email).

## 3.8.3 Authorization

- Role-based access control (RBAC) per 3.3.
- Permission checks at API layer (DRF permissions).
- Medical access: RBAC + Patient Consent + Context (per 3.3 consent model).

## 3.8.4 Data Protection

- **Transit**: TLS 1.2+ (NFR-SEC-001). No plaintext credentials.
- **Rest**: PostgreSQL passwords never stored in plaintext. Sensitive fields encrypted at rest where possible.
- **Backup**: encrypted backups, access-controlled.
- **Export**: audit logs for data access.

## 3.8.5 API Security (NFR-SEC-005)

- CSRF protection (Django default).
- Rate limiting per IP/user.
- Input validation + sanitization (DRF serializers).
- CORS restricted to known origins.
- No sensitive data in URL params or logs.
- Security headers: X-Content-Type-Options, X-Frame-Options, CSP.

## 3.8.6 Privacy Principles

- **Data minimization**: collect only what's needed.
- **Purpose limitation**: medical data used only for specified purposes.
- **Access control**: medical data requires consent + authorized access.
- **Data retention**: configurable retention policies (audit logs, session data).
- **Right to access**: patient can request export of their data.
- **Right to erasure**: patient can request deletion (audit trail for compliance).

## 3.8.7 Consent Architecture (Detailed)

```
Patient
   │
   ▼
Consent Management
   │
   ├── Doctor Access
   ├── Caregiver Access
   ├── Record Category
   ├── Duration (expires_at)
   └── Revocation
```

Mfano: Patient A → Doctor B → Medical history ✓, Medication ✓, Blood info ✓, Private notes ✗.

Fine-grained: per-record, per-category, per-user, per-duration.

Revocation: real-time, immediate effect (no cache delay).

Emergency override: limited, audited, policy-defined (see 3.9 Emergency).

## 3.8.8 Audit Trail

- Kila critical operation: who, what, when, where, details.
- Medical access: logged with patient consent reference.
- Admin actions: logged with reason.
- System actions: logged with context.
- Logs: append-only, no deletion (retention policy applies).

## 3.8.9 Threat Model (kwa design)

| Threat | Mitigation |
|---|---|
| Unauthorized medical access | Consent + RBAC + audit |
| Password compromise | Hashing + MFA + rate limiting |
| API abuse | Rate limiting + input validation |
| Data breach | TLS + encryption + access control |
| Emergency abuse | Rate limiting + verification + audit |
| AI misinformation | Safety layer + human oversight |
| Payment fraud | Server-side verification + webhook validation |

## 3.8.10 Traceability

- NFR-SEC-* → 3.8 Security Architecture
- BR-001/002/003/004/005/006/007/008/009/012 → Security enforcement
- 3.3 Roles & Permissions → 3.8 Authorization