import { useState } from 'react';
import { listCampaignQueue, listCampaigns, decideCampaign, setCampaignStatus } from '../lib/api/admin';
import { useAsync } from '../lib/useAsync';
import { friendlyError } from '../lib/auth/AuthContext';
import { Button, EmptyState, ErrorState, LoadingState, PageHeader, StatusChip, Card, Badge } from '../components/ui';
import { pushToast } from '../components/ui';
import { DecisionModal } from './shared';
import type { AdminCampaignRow } from '../lib/api/types';

/**
 * Two sections, because the backend enforces two different state machines:
 *  - the verification queue only holds PENDING_VERIFICATION campaigns, which
 *    can be approved, rejected or closed (never paused — `admin_pause_campaign`
 *    accepts ACTIVE only, so a Pause button here would always 400);
 *  - live campaigns (ACTIVE/PAUSED) are the ones pause/close actually apply to.
 */
export function CampaignsVerificationPage() {
  const queue = useAsync(() => listCampaignQueue(), []);
  const live = useAsync(
    async () => {
      const [active, paused] = await Promise.all([
        listCampaigns({ status: 'ACTIVE' }),
        listCampaigns({ status: 'PAUSED' }),
      ]);
      return [...active, ...paused];
    },
    [],
  );

  const [subject, setSubject] = useState<AdminCampaignRow | null>(null);
  const [approve, setApprove] = useState(true);
  const [manage, setManage] = useState<AdminCampaignRow | null>(null);
  const [manageMode, setManageMode] = useState<'pause' | 'close'>('pause');
  const [busy, setBusy] = useState(false);

  const reloadAll = () => {
    queue.reload();
    live.reload();
  };

  async function onDecide(reason: string) {
    if (!subject) return;
    setBusy(true);
    try {
      await decideCampaign(subject.uid, approve, reason);
      pushToast('success', approve ? 'Campaign approved.' : 'Campaign rejected.');
      setSubject(null);
      reloadAll();
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
        title="Campaign verification"
        subtitle="Approve fundraising campaigns, or pause and close live ones."
      />

      <h2 style={{ fontSize: 16, marginTop: 8 }}>Verification queue</h2>
      {queue.loading ? <LoadingState /> : null}
      {queue.error ? <ErrorState message={queue.error} onRetry={queue.reload} /> : null}
      {!queue.loading && !queue.error ? (
        queue.data && queue.data.length > 0 ? (
          <div style={{ display: 'grid', gap: 12 }}>
            {queue.data.map((c) => (
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
                  <Button variant="secondary" onClick={() => { setManageMode('close'); setManage(c); }}>Close</Button>
                </div>
              </Card>
            ))}
          </div>
        ) : (
          <EmptyState title="Queue is clear" message="No campaigns are waiting for verification." />
        )
      ) : null}

      <h2 style={{ fontSize: 16, marginTop: 24 }}>Live campaigns</h2>
      <p style={{ fontSize: 13, color: 'var(--sw-text-2)', marginTop: -4, marginBottom: 10 }}>
        ACTIVE and PAUSED campaigns — pause stops new donations, close is terminal.
      </p>
      {live.loading ? <LoadingState /> : null}
      {live.error ? <ErrorState message={live.error} onRetry={live.reload} /> : null}
      {!live.loading && !live.error ? (
        live.data && live.data.length > 0 ? (
          <div className="sw-tablewrap">
            <table className="sw-table">
              <thead>
                <tr>
                  <th scope="col">Campaign</th>
                  <th scope="col">Owner</th>
                  <th scope="col">Raised</th>
                  <th scope="col">Status</th>
                  <th scope="col">Actions</th>
                </tr>
              </thead>
              <tbody>
                {live.data.map((c) => (
                  <tr key={c.uid}>
                    <td><strong>{c.title}</strong></td>
                    <td>{c.owner?.display_name || '—'}</td>
                    <td>
                      {c.raised_amount.toLocaleString()} / {c.goal_amount.toLocaleString()} {c.currency}
                      {typeof c.progress === 'number' ? (
                        <Badge tone="blue"> {Math.round(c.progress)}%</Badge>
                      ) : null}
                    </td>
                    <td><StatusChip status={c.status} /></td>
                    <td>
                      <div style={{ display: 'flex', gap: 8 }}>
                        {c.status === 'ACTIVE' ? (
                          <Button variant="secondary" onClick={() => { setManageMode('pause'); setManage(c); }}>
                            Pause
                          </Button>
                        ) : null}
                        <Button variant="danger" onClick={() => { setManageMode('close'); setManage(c); }}>
                          Close
                        </Button>
                      </div>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        ) : (
          <EmptyState title="No live campaigns" message="Nothing is taking donations right now." />
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
        approve={manageMode === 'pause'}
        confirmLabel={manageMode === 'pause' ? 'Pause' : 'Close'}
        reasonLabel={manageMode === 'pause' ? 'Pause reason' : 'Closure reason'}
        loading={busy}
        reasonRequired
        onCancel={() => setManage(null)}
        onConfirm={onManage}
      />
    </>
  );
}
