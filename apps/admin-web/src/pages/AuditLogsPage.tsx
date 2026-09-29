import { useState } from 'react';
import { listAuditLogs } from '../lib/api/admin';
import { useAsync } from '../lib/useAsync';
import { Badge, Button, EmptyState, ErrorState, Input, LoadingState, Modal, PageHeader, Select } from '../components/ui';
import type { AdminAuditLogRow } from '../lib/api/types';

export function AuditLogsPage() {
  const [action, setAction] = useState('');
  const [actor, setActor] = useState('');
  const { data, loading, error, reload } = useAsync(() => listAuditLogs({ action: action || undefined, actor: actor || undefined }), [action, actor]);
  const [details, setDetails] = useState<AdminAuditLogRow | null>(null);

  return (
    <>
      <PageHeader title="Audit logs" subtitle="Every sensitive action is recorded with the actor, resource and reason." />
      <div className="sw-toolbar">
        <Select value={action} onChange={(e) => setAction(e.target.value)} aria-label="Filter by action" style={{ maxWidth: 240 }}>
          <option value="">All actions</option>
          <option value="login">login</option>
          <option value="user_activated">user_activated</option>
          <option value="user_deactivated">user_deactivated</option>
          <option value="role_granted">role_granted</option>
          <option value="role_revoked">role_revoked</option>
          <option value="doctor_verified">doctor_verified</option>
          <option value="campaign_approved">campaign_approved</option>
          <option value="donation_refunded">donation_refunded</option>
        </Select>
        <Input
          placeholder="Actor email…"
          value={actor}
          onChange={(e) => setActor(e.target.value)}
          aria-label="Search by actor"
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
                  <th scope="col">Actor</th>
                  <th scope="col">Action</th>
                  <th scope="col">Resource</th>
                  <th scope="col">Result</th>
                </tr>
              </thead>
              <tbody>
                {data.map((e) => (
                  <tr key={e.id}>
                    <td style={{ whiteSpace: 'nowrap' }}>
                      {e.created_at ? new Date(e.created_at).toLocaleString() : '—'}
                    </td>
                    <td>{e.actor?.email || e.actor?.display_name || '—'}</td>
                    <td><Badge tone="navy">{e.action}</Badge></td>
                    <td>
                      {e.resource_type ? `${e.resource_type} ${e.resource_id ? `#${e.resource_id}` : ''}` : '—'}
                      <br />
                      {typeof e.reason === 'string' && e.reason ? (
                        <span style={{ color: 'var(--sw-text-muted)', fontSize: 12 }}>{e.reason}</span>
                      ) : null}
                    </td>
                    <td>
                      {e.result ? <Badge tone={e.result === 'SUCCESS' ? 'green' : 'amber'}>{e.result}</Badge> : '—'}
                      <Button
                        variant="ghost"
                        style={{ marginLeft: 6 }}
                        onClick={() => setDetails(e)}
                        disabled={!e.details}
                      >
                        Details
                      </Button>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        ) : (
          <div style={{ marginTop: 16 }}>
            <EmptyState title="No log entries" message="Try clearing the filters." />
          </div>
        )
      ) : null}

      {details ? (
        <Modal open onClose={() => setDetails(null)} title={`Log entry #${details.id}`} width={640}>
          <pre
            style={{
              background: 'var(--sw-bg)',
              padding: 14,
              borderRadius: 8,
              overflow: 'auto',
              fontSize: 12,
              color: 'var(--sw-text-2)',
              margin: 0,
            }}
          >
            {JSON.stringify(details.details, null, 2)}
          </pre>
        </Modal>
      ) : null}
    </>
  );
}