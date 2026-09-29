import { useState } from 'react';
import { listDoctorQueue, decideDoctor } from '../lib/api/admin';
import { useAsync } from '../lib/useAsync';
import { friendlyError } from '../lib/auth/AuthContext';
import { Button, EmptyState, ErrorState, LoadingState, PageHeader, StatusChip, Card } from '../components/ui';
import { pushToast } from '../components/ui';
import { DecisionModal } from './shared';
import type { AdminDoctorRow } from '../lib/api/types';

export function DoctorsVerificationPage() {
  const { data, loading, error, reload } = useAsync(() => listDoctorQueue(), []);
  const [subject, setSubject] = useState<AdminDoctorRow | null>(null);
  const [approve, setApprove] = useState(true);
  const [busy, setBusy] = useState(false);

  async function onConfirm(reason: string) {
    if (!subject) return;
    setBusy(true);
    try {
      await decideDoctor(subject.uid, approve, reason);
      pushToast('success', approve ? 'Doctor approved.' : 'Doctor rejected.');
      setSubject(null);
      reload();
    } catch (e) {
      pushToast('error', friendlyError(e));
    } finally {
      setBusy(false);
    }
  }

  return (
    <>
      <PageHeader title="Doctor verification" subtitle="Review submitted professional documents and verify qualified doctors." />
      {loading ? <LoadingState /> : null}
      {error ? <ErrorState message={error} onRetry={reload} /> : null}
      {!loading && !error ? (
        data && data.length > 0 ? (
          <div style={{ display: 'grid', gap: 12 }}>
            {data.map((d) => (
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
                </div>
              </Card>
            ))}
          </div>
        ) : (
          <EmptyState title="Queue is clear" message="No doctors are waiting for verification." />
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
        onConfirm={onConfirm}
      />
    </>
  );
}