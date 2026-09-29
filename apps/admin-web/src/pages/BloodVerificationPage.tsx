import { useState } from 'react';
import { listBloodQueue, decideBloodRequest } from '../lib/api/admin';
import { useAsync } from '../lib/useAsync';
import { friendlyError } from '../lib/auth/AuthContext';
import { Badge, Button, EmptyState, ErrorState, LoadingState, PageHeader, StatusChip, Card } from '../components/ui';
import { pushToast } from '../components/ui';
import { DecisionModal } from './shared';
import type { AdminBloodRequestRow } from '../lib/api/types';

export function BloodVerificationPage() {
  const { data, loading, error, reload } = useAsync(() => listBloodQueue(), []);
  const [subject, setSubject] = useState<AdminBloodRequestRow | null>(null);
  const [approve, setApprove] = useState(true);
  const [busy, setBusy] = useState(false);

  async function onConfirm(reason: string) {
    if (!subject) return;
    setBusy(true);
    try {
      await decideBloodRequest(subject.uid, approve, reason);
      pushToast('success', approve ? 'Blood request verified.' : 'Blood request rejected.');
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
      <PageHeader title="Blood request queue" subtitle="Verify donor-backed blood requests before they go live." />
      {loading ? <LoadingState /> : null}
      {error ? <ErrorState message={error} onRetry={reload} /> : null}
      {!loading && !error ? (
        data && data.length > 0 ? (
          <div style={{ display: 'grid', gap: 12 }}>
            {data.map((b) => (
              <Card key={b.uid} style={{ padding: 16 }}>
                <div style={{ display: 'flex', justifyContent: 'space-between', gap: 16, flexWrap: 'wrap' }}>
                  <div>
                    <h3 style={{ marginBottom: 4 }}>
                      <Badge tone="red">{b.blood_group_needed}</Badge>
                      {' '}
                      Blood request
                    </h3>
                    <p style={{ fontSize: 13 }}>
                      {b.units} unit(s) · {b.urgency} · {b.location || 'Location not provided'}
                    </p>
                    {b.facility?.name ? (
                      <p style={{ fontSize: 13, color: 'var(--sw-text-2)' }}>Facility: {b.facility.name}</p>
                    ) : null}
                  </div>
                  <div style={{ textAlign: 'right' }}>
                    <StatusChip status={b.status} />
                  </div>
                </div>
                <div style={{ display: 'flex', gap: 8, marginTop: 12 }}>
                  <Button onClick={() => { setApprove(true); setSubject(b); }}>Verify</Button>
                  <Button variant="danger" onClick={() => { setApprove(false); setSubject(b); }}>Reject</Button>
                </div>
              </Card>
            ))}
          </div>
        ) : (
          <EmptyState title="Queue is clear" message="No blood requests are waiting for verification." />
        )
      ) : null}

      <DecisionModal
        open={!!subject}
        title={approve ? 'Verify blood request?' : 'Reject blood request?'}
        subject={subject ? `${subject.blood_group_needed} · ${subject.units} unit(s)` : ''}
        approve={approve}
        loading={busy}
        reasonRequired={!approve}
        onCancel={() => setSubject(null)}
        onConfirm={onConfirm}
      />
    </>
  );
}