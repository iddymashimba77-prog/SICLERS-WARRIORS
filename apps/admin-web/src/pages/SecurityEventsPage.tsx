import { useState } from 'react';
import { listSecurityEvents } from '../lib/api/admin';
import { useAsync } from '../lib/useAsync';
import { Badge, Button, EmptyState, ErrorState, LoadingState, PageHeader, Select, StatusChip } from '../components/ui';

export function SecurityEventsPage() {
  const [status, setStatus] = useState('');
  const { data, loading, error, reload } = useAsync(() => listSecurityEvents({ status: status || undefined }), [status]);

  return (
    <>
      <PageHeader title="Security events" subtitle="Authentication and security telemetry from the backend." />
      <div className="sw-toolbar">
        <Select value={status} onChange={(e) => setStatus(e.target.value)} aria-label="Filter by status" style={{ maxWidth: 220 }}>
          <option value="">All statuses</option>
          <option value="NEW">NEW</option>
          <option value="ACKNOWLEDGED">ACKNOWLEDGED</option>
          <option value="RESOLVED">RESOLVED</option>
        </Select>
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
                  <th scope="col">Actor</th>
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
                      <Badge tone={e.event_type.includes('FAILED') || e.event_type.includes('SUSPICIOUS') ? 'red' : 'blue'}>
                        {e.event_type}
                      </Badge>
                      {typeof e.reason === 'string' && e.reason ? (
                        <>
                          <br />
                          <span style={{ color: 'var(--sw-text-muted)', fontSize: 12 }}>{e.reason}</span>
                        </>
                      ) : null}
                    </td>
                    <td>{e.actor?.email || '—'}</td>
                    <td>{e.ip_address || '—'}</td>
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