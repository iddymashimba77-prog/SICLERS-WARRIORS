import { useState } from 'react';
import { exportAuditLogs, listAuditLogs } from '../lib/api/admin';
import { useAsync } from '../lib/useAsync';
import { friendlyError } from '../lib/auth/AuthContext';
import { Badge, Button, EmptyState, ErrorState, Input, LoadingState, Modal, PageHeader, Select } from '../components/ui';
import { pushToast } from '../components/ui';
import type { AdminAuditLogRow } from '../lib/api/types';

const RESULTS = ['', 'SUCCESS', 'FAILURE', 'DENIED'];

function downloadCsv(text: string, filename: string) {
  const blob = new Blob([text], { type: 'text/csv;charset=utf-8' });
  const url = URL.createObjectURL(blob);
  const a = document.createElement('a');
  a.href = url;
  a.download = filename;
  document.body.appendChild(a);
  a.click();
  a.remove();
  URL.revokeObjectURL(url);
}

export function AuditLogsPage() {
  const [action, setAction] = useState('');
  const [actor, setActor] = useState('');
  const [result, setResult] = useState('');
  const { data, loading, error, reload } = useAsync(
    () => listAuditLogs({
      action_code: action || undefined,
      actor: actor || undefined,
      result: result || undefined,
    }),
    [action, actor, result],
  );
  const [details, setDetails] = useState<AdminAuditLogRow | null>(null);
  const [exporting, setExporting] = useState(false);
  const [exportReason, setExportReason] = useState('');
  const [exportErr, setExportErr] = useState<string | null>(null);

  async function doExport() {
    if (exportReason.trim().length < 5) {
      setExportErr('A reason of at least 5 characters is mandatory; the export is audited.');
      return;
    }
    setExporting(true);
    setExportErr(null);
    try {
      const csv = await exportAuditLogs(exportReason.trim());
      downloadCsv(csv, 'audit-log.csv');
      pushToast('success', 'Audit CSV exported and recorded.');
      setDetails(null);
      setExportReason('');
      reload();
    } catch (e) {
      setExportErr(friendlyError(e));
    } finally {
      setExporting(false);
    }
  }

  return (
    <>
      <PageHeader title="Audit logs" subtitle="Every sensitive action is recorded with the actor, resource and result." />
      <div className="sw-toolbar">
        <Input
          placeholder="Action contains… e.g. users.activate"
          value={action}
          onChange={(e) => setAction(e.target.value)}
          aria-label="Filter by action code"
          style={{ maxWidth: 260 }}
        />
        <Input
          placeholder="Actor email…"
          value={actor}
          onChange={(e) => setActor(e.target.value)}
          aria-label="Search by actor"
          style={{ maxWidth: 220 }}
        />
        <Select value={result} onChange={(e) => setResult(e.target.value)} aria-label="Filter by result" style={{ maxWidth: 180 }}>
          {RESULTS.map((r) => (
            <option key={r} value={r}>{r === '' ? 'All results' : r}</option>
          ))}
        </Select>
        <Button variant="secondary" onClick={reload}>Refresh</Button>
        <Button variant="secondary" onClick={() => setDetails({ id: -1 } as AdminAuditLogRow)}>Export CSV</Button>
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
                    <td>{e.actor_email || '—'}</td>
                    <td><Badge tone="navy">{e.action_code}</Badge></td>
                    <td>
                      {e.resource_type ? `${e.resource_type} ${e.resource_id ? `#${e.resource_id}` : ''}` : '—'}
                      {e.ip_address ? (
                        <><br /><span style={{ color: 'var(--sw-text-muted)', fontSize: 12 }}>{e.ip_address}</span></>
                      ) : null}
                    </td>
                    <td>
                      {e.result ? <Badge tone={e.result === 'SUCCESS' ? 'green' : 'amber'}>{e.result}</Badge> : '—'}
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

      {details && details.id !== -1 ? (
        <Modal open onClose={() => setDetails(null)} title={`Log entry #${details.id}`} width={640}>
          <pre
            style={{
              background: 'var(--sw-bg)',
              padding: 14,
              borderRadius: 'var(--sw-radius-sm)',
              overflow: 'auto',
              fontSize: 12,
              color: 'var(--sw-text-2)',
              margin: 0,
            }}
          >
            {JSON.stringify(
              {
                actor_email: details.actor_email,
                action_code: details.action_code,
                resource_type: details.resource_type,
                resource_id: details.resource_id,
                result: details.result,
                ip_address: details.ip_address,
                request_id: details.request_id,
                created_at: details.created_at,
              },
              null,
              2,
            )}
          </pre>
        </Modal>
      ) : null}

      {details && details.id === -1 ? (
        <Modal
          open
          onClose={() => { setDetails(null); setExportErr(null); }}
          title="Export audit log (CSV)"
          footer={
            <>
              <Button variant="ghost" onClick={() => { setDetails(null); setExportErr(null); }} disabled={exporting}>Cancel</Button>
              <Button loading={exporting} onClick={doExport}>Export</Button>
            </>
          }
        >
          {exportErr ? <p className="sw-err" role="alert" style={{ marginBottom: 12 }}>{exportErr}</p> : null}
          <p style={{ fontSize: 13, color: 'var(--sw-text-2)', marginBottom: 10 }}>
            Exports the current filter (max 5,000 rows) and appends its own entry to the audit trail.
          </p>
          <Input
            value={exportReason}
            onChange={(e) => setExportReason(e.target.value)}
            placeholder="Reason for this export (min 5 characters)"
            aria-label="Export reason"
          />
        </Modal>
      ) : null}
    </>
  );
}
