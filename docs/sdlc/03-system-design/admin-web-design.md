# 3.7 Admin Web Design

> **SUPERSEDED** — replaced by the Stage 3.7 admin-web deliverables
> (`admin-web-ui-ux-design.md` and companions). Kept for history only; do not
> use as the active design.

## Platform
- Desktop browser. Target: modern browsers (Chrome, Firefox, Edge).
- Admin panel ni kwa admin roles pekee: SUPER_ADMIN, ADMIN, VERIFICATION_OFFICER, MODERATOR.
- Hutumia API ile ile ya `/api/v1/...`.

## Structure

```
Admin Dashboard
│
├── Users
│   ├── User list (search, filter, pagination)
│   ├── User detail (roles, permissions)
│   └── User actions (disable, reset password)
│
├── Doctors
│   ├── Verification queue (pending)
│   ├── Doctor profile (license, specialty, facility)
│   └── Approve / Reject + reason
│
├── Blood Network
│   ├── Donors (search, filter, blood group)
│   ├── Requests (status, urgency)
│   └── Matching oversight
│
├── Emergency
│   ├── Live request feed
│   ├── Severity classification
│   └── Response status monitoring
│
├── Campaigns
│   ├── Verification queue
│   ├── Campaign detail (progress, donations)
│   └── Approve / Reject
│
├── Payments
│   ├── Transaction list (status, provider)
│   ├── Transaction detail (receipt, timeline)
│   └── Refund / dispute handling
│
├── Community Moderation
│   ├── Reports queue
│   ├── Reported content (post/comment)
│   └── Action: resolve, dismiss, remove
│
├── Education
│   ├── Content management (create, edit, publish)
│   ├── Category management
│   └── Review workflow
│
├── Notifications
│   ├── Notification preferences
│   └── Manual broadcast (system admin)
│
├── Analytics / Reports
│   ├── Usage metrics
│   ├── Health trends (anonymized)
│   ├── Donation summary
│   └── Emergency response metrics
│
├── Audit Logs
│   ├── Filter by user, action, resource, time
│   └── Detail view (IP, user agent, details JSON)
│
├── Security
│   ├── MFA settings
│   ├── Rate limiting config
│   └── API key management (if needed)
│
└── System Settings
    ├── Blood matching config (matching rules)
    ├── Emergency config (severity thresholds)
    ├── AI config (safety rules)
    └── Notification config (channels, templates)
```

## UX principles
- Dashboard: overview cards (pending verifications, active emergencies, recent donations, system health).
- Quick actions: approve/reject with one click + reason modal.
- Filter/search everywhere.
- Audit logs: read-only, filterable, exportable.

## Responsibilities
- Admin panel = management tool. Haina direct access to medical records (except audit logs).
- Medical data access ya admin ni kwa audit purposes only; consent-scoped still applies.
- Emergency monitor: admin anaweza kuona emergency requests na status, lakini sio medical records (bila consent).