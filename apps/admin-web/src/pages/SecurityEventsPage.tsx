import { useState } from 'react';
import { listSecurityEvents } from '../lib/api/admin';
import { useAsync } from '../lib/useAsync';
import { Badge, Button, EmptyState, ErrorState, Input, LoadingState, PageHeader, Select, StatusChip } from '../components/ui';

/** Auth/security subset of `SecurityEvent.KINDS` (the backend validates the filter). */
const EVENT_TYPES = [
  'LOGIN_SUCCESS', 'LOGIN_FAILED', 'MFA_CHALLENGE', 'MFA_FAILED', 'REGISTER',
  'LOGOUT', 'PASSWORD_CHANGE', 'PASSWORD_RESET', 'EMAIL_VERIFY_ISSUED',
  'EMAIL_VERIFIED', 'LOGIN_PIN_SET', 'ROLE_CHANGE', 'TOKEN_REFRESH', 'ADMIN_ACTION',
];

const STATUSES = ['SUCCESS', 'FAILED', 'BLOCKED'];

export function SecurityEventsPage() {
  const [status, setStatus] = useState('');
  const [eventType, setEventType] = useState('');
  const [user, setUser] = useState('');
  const { data, loading, error, reload } = useAsync(
    () => listSecurityEvents({
      status: status || undefined,
      event_type: eventType || undefined,
      user: user || undefined,
    }),
    [status, eventType, user],
  );

  return (
    <>
      <PageHeader title="Security events" subtitle="Authentication and security telemetry from the backend." />
      <div className="sw-toolbar">
        <Select value={status} onChange={(e) => setStatus(e.target.value)} aria-label="Filter by status" style={{ maxWidth: 180 }}>
          <option value="">All statuses</option>
          {STATUSES.map((s) => (
            <option key={s} value={s}>{s}</option>
          ))}
        </Select>
        <Select value={eventType} onChange={(e) => setEventType(e.target.value)} aria-label="Filter by event type" style={{ maxWidth: 220 }}>
          <option value="">All event types</option>
          {EVENT_TYPES.map((t) => (
            <option key={t} value={t}>{t}</option>
          ))}
        </Select>
        <Input
          placeholder="Account email…"
          value={user}
          onChange={(e) => setUser(e.target.value)}
          aria-label="Search by account"
          style={{ maxWidth: 220 }}
        />
        <Button variant="secondary" onClick={reload}>Refresh</Button>
      </div>
      {loading ? <LoadingState /> : null}
      {error ? <ErrorState message={error} onRetry={reload} /> : null}
      {!loading && !error ? (
        data && data.length > 0 ? (
          <div className="sw-tablewrap" style={{ marginTop: 16 }}>
            <table className="sw-table">
              <thead>
                <tr>
                  <th scope="col">When</th>
                  <th scope="col">Event</th>
                  <th scope="col">Account</th>
                  <th scope="col">IP</th>
                  <th scope="col">Status</th>
                </tr>
              </thead>
              <tbody>
                {data.map((e) => (
                  <tr key={e.id}>
                    <td style={{ whiteSpace: 'nowrap' }}>
                      {e.created_at ? new Date(e.created_at).toLocaleString() : '—'}
                    </td>
                    <td>
                      <Badge tone={e.event_type.includes('FAILED') ? 'red' : 'blue'}>
                        {e.event_type}
                      </Badge>
                      {e.detail && Object.keys(e.detail).length > 0 ? (
                        <>
                          <br />
                          <span style={{ color: 'var(--sw-text-muted)', fontSize: 12 }}>
                            {Object.entries(e.detail).map(([k, v]) => `${k}: ${String(v)}`).join(' · ')}
                          </span>
                        </>
                      ) : null}
                    </td>
                    <td>{e.user_email || '—'}</td>
                    <td>
                      {e.ip_address || '—'}
                      {e.user_agent ? (
                        <><br /><span style={{ color: 'var(--sw-text-muted)', fontSize: 11 }}>{e.user_agent}</span></>
                      ) : null}
                    </td>
                    <td><StatusChip status={e.status} /></td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        ) : (
          <div style={{ marginTop: 16 }}>
            <EmptyState title="No security events" message="The backend has not recorded any events matching this filter." />
          </div>
        )
      ) : null}
    </>
  );
}
