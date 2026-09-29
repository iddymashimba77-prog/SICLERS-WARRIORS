import { useState } from 'react';
import { listCampaignQueue, decideCampaign, setCampaignStatus } from '../lib/api/admin';
import { useAsync } from '../lib/useAsync';
import { friendlyError } from '../lib/auth/AuthContext';
import { Button, EmptyState, ErrorState, LoadingState, PageHeader, StatusChip, Card } from '../components/ui';
import { pushToast } from '../components/ui';
import { DecisionModal } from './shared';
import type { AdminCampaignRow } from '../lib/api/types';

export function CampaignsVerificationPage() {
  const { data, loading, error, reload } = useAsync(() => listCampaignQueue(), []);
  const [subject, setSubject] = useState<AdminCampaignRow | null>(null);
  const [approve, setApprove] = useState(true);
  const [manage, setManage] = useState<AdminCampaignRow | null>(null);
  const [manageMode, setManageMode] = useState<'pause' | 'close'>('pause');
  const [busy, setBusy] = useState(false);

  async function onDecide(reason: string) {
    if (!subject) return;
    setBusy(true);
    try {
      await decideCampaign(subject.uid, approve, reason);
      pushToast('success', approve ? 'Campaign approved.' : 'Campaign rejected.');
      setSubject(null);
      reload();
    } catch (e) {
      pushToast('error', friendlyError(e));
    } finally {
      setBusy(false);
    }
  }

  async function onManage(reason: string) {
    if (!manage) return;
    setBusy(true);
    try {
      await setCampaignStatus(manage.uid, manageMode, reason);
      pushToast('success', manageMode === 'pause' ? 'Campaign paused.' : 'Campaign closed.');
      setManage(null);
      reload();
    } catch (e) {
      pushToast('error', friendlyError(e));
    } finally {
      setBusy(false);
    }
  }

  return (
    <>
      <PageHeader title="Campaign verification" subtitle="Approve fundraising campaigns, or pause and close live ones." />
      {loading ? <LoadingState /> : null}
      {error ? <ErrorState message={error} onRetry={reload} /> : null}
      {!loading && !error ? (
        data && data.length > 0 ? (
          <div style={{ display: 'grid', gap: 12 }}>
            {data.map((c) => (
              <Card key={c.uid} style={{ padding: 16 }}>
                <div style={{ display: 'flex', justifyContent: 'space-between', gap: 16, flexWrap: 'wrap' }}>
                  <div style={{ minWidth: 260 }}>
                    <h3 style={{ marginBottom: 2 }}>{c.title}</h3>
                    <p style={{ fontSize: 13 }}>
                      {c.goal_amount.toLocaleString()} {c.currency} goal
                      {c.owner?.display_name ? ` · by ${c.owner.display_name}` : ''}
                    </p>
                  </div>
                  <div style={{ textAlign: 'right' }}>
                    <StatusChip status={c.status} />
                  </div>
                </div>
                <div style={{ display: 'flex', gap: 8, marginTop: 12, flexWrap: 'wrap' }}>
                  <Button onClick={() => { setApprove(true); setSubject(c); }}>Approve</Button>
                  <Button variant="danger" onClick={() => { setApprove(false); setSubject(c); }}>Reject</Button>
                  <Button variant="secondary" onClick={() => { setManageMode('pause'); setManage(c); }}>Pause</Button>
                  <Button variant="secondary" onClick={() => { setManageMode('close'); setManage(c); }}>Close</Button>
                </div>
              </Card>
            ))}
          </div>
        ) : (
          <EmptyState title="Queue is clear" message="No campaigns are waiting for verification." />
        )
      ) : null}

      <DecisionModal
        open={!!subject}
        title={approve ? 'Approve campaign?' : 'Reject campaign?'}
        subject={subject?.title ?? ''}
        approve={approve}
        loading={busy}
        reasonRequired={!approve}
        onCancel={() => setSubject(null)}
        onConfirm={onDecide}
      />
      <DecisionModal
        open={!!manage}
        title={manageMode === 'pause' ? 'Pause campaign?' : 'Close campaign?'}
        subject={manage?.title ?? ''}
        approve
        confirmLabel={manageMode === 'pause' ? 'Pause' : 'Close'}
        loading={busy}
        reasonRequired
        onCancel={() => setManage(null)}
        onConfirm={onManage}
      />
    </>
  );
}