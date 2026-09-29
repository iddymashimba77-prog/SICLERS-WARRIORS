import { useState } from 'react';
import { listCommunityReports, resolveCommunityReport } from '../lib/api/admin';
import { useAsync } from '../lib/useAsync';
import { friendlyError } from '../lib/auth/AuthContext';
import { Badge, Button, EmptyState, ErrorState, Field, Input, LoadingState, Modal, PageHeader, Select, StatusChip } from '../components/ui';
import { pushToast } from '../components/ui';
import type { AdminCommunityReportRow } from '../lib/api/types';

const ACTIONS = [
  { value: 'clean', label: 'Clean — no action needed' },
  { value: 'warn', label: 'Warn the author' },
  { value: 'remove', label: 'Remove the content' },
  { value: 'ban', label: 'Suspend the author' },
];

export function ModerationPage() {
  const [status, setStatus] = useState('');
  const { data, loading, error, reload } = useAsync(() => listCommunityReports({ status: status || undefined }), [status]);
  const [subject, setSubject] = useState<AdminCommunityReportRow | null>(null);
  const [action, setAction] = useState('clean');
  const [reason, setReason] = useState('');
  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState<string | null>(null);

  async function resolve() {
    if (!subject) return;
    if (!reason.trim()) {
      setErr('A short explanation is required; it is attached to the audit record.');
      return;
    }
    setBusy(true);
    setErr(null);
    try {
      await resolveCommunityReport(subject.id, action, reason.trim());
      pushToast('success', 'Report resolved.');
      setSubject(null);
      setReason('');
      reload();
    } catch (e) {
      setErr(friendlyError(e));
    } finally {
      setBusy(false);
    }
  }

  return (
    <>
      <PageHeader title="Community moderation" subtitle="Review user reports on community content and resolve them with a recorded action." />
      <div className="sw-toolbar">
        <Select value={status} onChange={(e) => setStatus(e.target.value)} aria-label="Filter by status" style={{ maxWidth: 220 }}>
          <option value="">All statuses</option>
          <option value="OPEN">Open</option>
          <option value="IN_REVIEW">In review</option>
          <option value="RESOLVED">Resolved</option>
          <option value="dismissed">Dismissed</option>
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
                  <th scope="col">Report</th>
                  <th scope="col">Reason</th>
                  <th scope="col">Status</th>
                  <th scope="col">Actions</th>
                </tr>
              </thead>
              <tbody>
                {data.map((r) => (
                  <tr key={r.id}>
                    <td>
                      <strong>
                        {r.target_type || 'content'} {r.target_id ? `#${r.target_id}` : ''}
                      </strong>
                      <br />
                      <span style={{ color: 'var(--sw-text-muted)', fontSize: 12 }}>
                        {r.reporter ? `Reported by ${r.reporter}` : ''} · {r.created_at ? new Date(r.created_at).toLocaleDateString() : ''}
                      </span>
                    </td>
                    <td>{r.reason || '—'}</td>
                    <td><StatusChip status={r.status} /></td>
                    <td>
                      {r.status === 'RESOLVED' || r.status === 'dismissed' ? (
                        <Badge>Done</Badge>
                      ) : (
                        <Button
                          variant="secondary"
                          onClick={() => {
                            setSubject(r);
                            setAction('clean');
                            setReason('');
                            setErr(null);
                          }}
                        >
                          Resolve
                        </Button>
                      )}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        ) : (
          <EmptyState title="No reports" message="Nothing to moderate right now." />
        )
      ) : null}

      <Modal
        open={!!subject}
        onClose={() => setSubject(null)}
        title="Resolve report"
        footer={
          <>
            <Button variant="ghost" onClick={() => setSubject(null)} disabled={busy}>Cancel</Button>
            <Button loading={busy} onClick={resolve}>Resolve</Button>
          </>
        }
      >
        {err ? <p className="sw-err" role="alert" style={{ marginBottom: 12 }}>{err}</p> : null}
        <Field label="Action">
          <Select value={action} onChange={(e) => setAction(e.target.value)}>
            {ACTIONS.map((a) => (
              <option key={a.value} value={a.value}>{a.label}</option>
            ))}
          </Select>
        </Field>
        <Field label="Explanation" required hint="Attached to the audit record.">
          <Input value={reason} onChange={(e) => setReason(e.target.value)} placeholder="What did you find, and why this action?" />
        </Field>
      </Modal>
    </>
  );
}