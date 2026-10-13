import { useState } from 'react';
import { listDoctorQueue, decideDoctor, suspendDoctor, listDoctorDecisions, reinstateDoctor } from '../lib/api/admin';
import { useAsync } from '../lib/useAsync';
import { friendlyError } from '../lib/auth/AuthContext';
import { Button, EmptyState, ErrorState, LoadingState, PageHeader, StatusChip, Card, Badge } from '../components/ui';
import { pushToast } from '../components/ui';
import { DecisionModal, SubmittedDocuments } from './shared';
import type { AdminDoctorDecisionRow, AdminDoctorRow } from '../lib/api/types';

/**
 * Queue + the append-only decision trail (FR-DOC-006/007, C6): every decision
 * carries its reason, and a suspension can be reversed from the same screen
 * instead of by editing the row behind the API.
 */
export function DoctorsVerificationPage() {
  const queue = useAsync(() => listDoctorQueue(), []);
  const history = useAsync(() => listDoctorDecisions(), []);

  const [subject, setSubject] = useState<AdminDoctorRow | null>(null);
  const [approve, setApprove] = useState(true);
  const [suspend, setSuspend] = useState<AdminDoctorRow | null>(null);
  const [reinstate, setReinstate] = useState<AdminDoctorDecisionRow | null>(null);
  const [busy, setBusy] = useState(false);

  const reloadAll = () => {
    queue.reload();
    history.reload();
  };

  async function onDecide(reason: string) {
    if (!subject) return;
    setBusy(true);
    try {
      await decideDoctor(subject.uid, approve, reason);
      pushToast('success', approve ? 'Doctor approved.' : 'Doctor rejected.');
      setSubject(null);
      reloadAll();
    } catch (e) {
      pushToast('error', friendlyError(e));
    } finally {
      setBusy(false);
    }
  }

  async function onSuspend(reason: string) {
    if (!suspend) return;
    setBusy(true);
    try {
      await suspendDoctor(suspend.uid, reason);
      pushToast('success', 'Doctor suspended.');
      setSuspend(null);
      reloadAll();
    } catch (e) {
      pushToast('error', friendlyError(e));
    } finally {
      setBusy(false);
    }
  }

  async function onReinstate(reason: string) {
    if (!reinstate) return;
    setBusy(true);
    try {
      await reinstateDoctor(reinstate.doctor_uid, reason);
      pushToast('success', 'Doctor reinstated.');
      setReinstate(null);
      reloadAll();
    } catch (e) {
      pushToast('error', friendlyError(e));
    } finally {
      setBusy(false);
    }
  }

  return (
    <>
      <PageHeader
        title="Doctor verification"
        subtitle="Review submitted professional documents and verify qualified doctors."
      />

      <h2 style={{ fontSize: 16, marginTop: 8 }}>Verification queue</h2>
      {queue.loading ? <LoadingState /> : null}
      {queue.error ? <ErrorState message={queue.error} onRetry={queue.reload} /> : null}
      {!queue.loading && !queue.error ? (
        queue.data && queue.data.length > 0 ? (
          <div style={{ display: 'grid', gap: 12 }}>
            {queue.data.map((d) => (
              <Card key={d.uid} style={{ padding: 16 }}>
                <div style={{ display: 'flex', justifyContent: 'space-between', gap: 16, flexWrap: 'wrap' }}>
                  <div style={{ minWidth: 240 }}>
                    <h3 style={{ marginBottom: 2 }}>{d.display_name}</h3>
                    <p style={{ color: 'var(--sw-text-2)' }}>{d.email}</p>
                    <p style={{ fontSize: 13 }}>
                      <strong>{d.specialty || '—'}</strong>
                      {' · '}
                      License {d.license_number || '—'}
                      {' · '}
                      {d.registration_body || '—'}
                    </p>
                  </div>
                  <div style={{ textAlign: 'right' }}>
                    <StatusChip status={d.verification_status} />
                  </div>
                </div>
                <SubmittedDocuments documents={d.verification_documents} />
                <div style={{ display: 'flex', gap: 8, marginTop: 12 }}>
                  <Button
                    onClick={() => {
                      setApprove(true);
                      setSubject(d);
                    }}
                  >
                    Approve
                  </Button>
                  <Button
                    variant="danger"
                    onClick={() => {
                      setApprove(false);
                      setSubject(d);
                    }}
                  >
                    Reject
                  </Button>
                  <Button variant="secondary" onClick={() => setSuspend(d)}>
                    Suspend
                  </Button>
                </div>
              </Card>
            ))}
          </div>
        ) : (
          <EmptyState title="Queue is clear" message="No doctors are waiting for verification." />
        )
      ) : null}

      <h2 style={{ fontSize: 16, marginTop: 24 }}>Recent decisions</h2>
      <p style={{ fontSize: 13, color: 'var(--sw-text-2)', marginTop: -4, marginBottom: 10 }}>
        The append-only trail — newest first, with the reason each officer gave.
      </p>
      {history.loading ? <LoadingState /> : null}
      {history.error ? <ErrorState message={history.error} onRetry={history.reload} /> : null}
      {!history.loading && !history.error ? (
        history.data && history.data.length > 0 ? (
          <div className="sw-tablewrap">
            <table className="sw-table">
              <thead>
                <tr>
                  <th scope="col">License</th>
                  <th scope="col">Decision</th>
                  <th scope="col">Transition</th>
                  <th scope="col">Reason</th>
                  <th scope="col">Officer</th>
                  <th scope="col">When</th>
                  <th scope="col">Action</th>
                </tr>
              </thead>
              <tbody>
                {history.data.map((r) => (
                  <tr key={r.uid}>
                    <td>{r.license_number || '—'}</td>
                    <td><Badge tone={badgeTone(r.decision)}>{r.decision}</Badge></td>
                    <td style={{ fontSize: 12, color: 'var(--sw-text-2)' }}>
                      {r.from_status || '—'} → {r.to_status || '—'}
                    </td>
                    <td style={{ maxWidth: 280 }}>{r.reason || '—'}</td>
                    <td>{r.actor_name || '—'}</td>
                    <td style={{ whiteSpace: 'nowrap' }}>{formatWhen(r.decided_at)}</td>
                    <td>
                      {r.to_status === 'SUSPENDED' && isLatestSuspended(history.data ?? [], r) ? (
                        <Button variant="secondary" onClick={() => setReinstate(r)}>
                          Reinstate
                        </Button>
                      ) : (
                        <span style={{ color: 'var(--sw-text-muted)' }}>—</span>
                      )}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        ) : (
          <EmptyState title="No decisions yet" message="Decisions appear here as soon as an officer makes one." />
        )
      ) : null}

      <DecisionModal
        open={!!subject}
        title={approve ? 'Approve doctor?' : 'Reject doctor?'}
        subject={`${subject?.display_name ?? ''} — license ${subject?.license_number ?? ''}`}
        approve={approve}
        loading={busy}
        reasonRequired={!approve}
        onCancel={() => setSubject(null)}
        onConfirm={onDecide}
      />
      <DecisionModal
        open={!!suspend}
        title="Suspend doctor?"
        subject={`${suspend?.display_name ?? ''} — license ${suspend?.license_number ?? ''}`}
        approve={false}
        confirmLabel="Suspend"
        reasonLabel="Suspension reason"
        loading={busy}
        reasonRequired
        onCancel={() => setSuspend(null)}
        onConfirm={onSuspend}
      />
      <DecisionModal
        open={!!reinstate}
        title="Reinstate doctor?"
        subject={`License ${reinstate?.license_number ?? ''}`}
        approve
        confirmLabel="Reinstate"
        reasonLabel="Reinstatement reason"
        loading={busy}
        reasonRequired
        onCancel={() => setReinstate(null)}
        onConfirm={onReinstate}
      />
    </>
  );
}

function badgeTone(decision: string): 'blue' | 'red' | 'green' | 'amber' | 'navy' | 'gray' {
  if (decision === 'APPROVED' || decision === 'REINSTATED') return 'green';
  if (decision === 'REJECTED' || decision === 'SUSPENDED') return 'red';
  if (decision === 'SUBMITTED' || decision === 'RESUBMITTED') return 'amber';
  if (decision === 'NOTE') return 'gray';
  return 'blue';
}

function formatWhen(iso: string): string {
  if (!iso) return '—';
  const d = new Date(iso);
  return Number.isNaN(d.getTime()) ? iso : d.toLocaleString();
}

/** The history is newest-first; a suspension is only reversible while it is
 *  still that doctor's most recent state (rows below may predate it). */
function isLatestSuspended(rows: AdminDoctorDecisionRow[], row: AdminDoctorDecisionRow): boolean {
  const first = rows.find((r) => r.doctor_uid === row.doctor_uid);
  return first?.uid === row.uid;
}
