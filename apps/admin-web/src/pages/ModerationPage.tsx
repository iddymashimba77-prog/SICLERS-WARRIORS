import { useState } from 'react';
import { listCommunityReports, resolveCommunityReport } from '../lib/api/admin';
import type { ReportAction, ReportStatus } from '../lib/api/admin';
import { useAsync } from '../lib/useAsync';
import { friendlyError } from '../lib/auth/AuthContext';
import { Button, EmptyState, ErrorState, Field, Input, LoadingState, Modal, PageHeader, Select, StatusChip } from '../components/ui';
import { pushToast } from '../components/ui';
import type { AdminCommunityReportRow } from '../lib/api/types';

/** One option per legal backend payload (`status` + `action` are a fixed pair). */
const RESOLUTIONS: { value: string; status: ReportStatus; action: ReportAction; label: string }[] = [
  { value: 'RESOLVED:NONE', status: 'RESOLVED', action: 'NONE', label: 'Resolve — no content action' },
  { value: 'RESOLVED:HIDE', status: 'RESOLVED', action: 'HIDE', label: 'Hide the content' },
  { value: 'RESOLVED:REMOVE', status: 'RESOLVED', action: 'REMOVE', label: 'Remove the content' },
  { value: 'DISMISSED:NONE', status: 'DISMISSED', action: 'NONE', label: 'Dismiss — report not upheld' },
];

export function ModerationPage() {
  const [status, setStatus] = useState('');
  const { data, loading, error, reload } = useAsync(() => listCommunityReports({ status: status || undefined }), [status]);
  const [subject, setSubject] = useState<AdminCommunityReportRow | null>(null);
  const [resolution, setResolution] = useState(RESOLUTIONS[0].value);
  const [reason, setReason] = useState('');
  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState<string | null>(null);

  async function resolve() {
    if (!subject) return;
    const chosen = RESOLUTIONS.find((r) => r.value === resolution) ?? RESOLUTIONS[0];
    if (!reason.trim()) {
      setErr('A short explanation is required; it is attached to the audit record.');
      return;
    }
    if ((chosen.action === 'HIDE' || chosen.action === 'REMOVE') && reason.trim().length < 5) {
      setErr('Give at least 5 characters of justification before hiding or removing content.');
      return;
    }
    setBusy(true);
    setErr(null);
    try {
      await resolveCommunityReport(subject.id, chosen.status, chosen.action, reason.trim());
      pushToast('success', `Report ${chosen.status === 'DISMISSED' ? 'dismissed' : 'resolved'}.`);
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
          <option value="DISMISSED">Dismissed</option>
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
                        {r.reporter?.display_name ? `Reported by ${r.reporter.display_name}` : ''}
                        {r.created_at ? ` · ${new Date(r.created_at).toLocaleDateString()}` : ''}
                      </span>
                      {r.target_preview ? (
                        <><br /><span style={{ color: 'var(--sw-text-2)', fontSize: 12 }}>{r.target_preview}</span></>
                      ) : null}
                    </td>
                    <td>{r.reason || '—'}</td>
                    <td><StatusChip status={r.status} /></td>
                    <td>
                      {r.status === 'RESOLVED' || r.status === 'DISMISSED' ? (
                        <StatusChip status="Done" />
                      ) : (
                        <Button
                          variant="secondary"
                          onClick={() => {
                            setSubject(r);
                            setResolution(RESOLUTIONS[0].value);
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
            <Button loading={busy} onClick={resolve}>Submit decision</Button>
          </>
        }
      >
        {err ? <p className="sw-err" role="alert" style={{ marginBottom: 12 }}>{err}</p> : null}
        <Field label="Decision">
          <Select value={resolution} onChange={(e) => setResolution(e.target.value)}>
            {RESOLUTIONS.map((r) => (
              <option key={r.value} value={r.value}>{r.label}</option>
            ))}
          </Select>
        </Field>
        <Field
          label="Review notes"
          required
          hint="Stored on the report and in the audit trail; mandatory when hiding or removing content."
        >
          <Input
            value={reason}
            onChange={(e) => setReason(e.target.value)}
            placeholder="What did you find, and why this decision?"
          />
        </Field>
      </Modal>
    </>
  );
}
