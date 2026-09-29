import { useState } from 'react';
import { listDonations, refundDonation } from '../lib/api/admin';
import { useAsync } from '../lib/useAsync';
import { friendlyError } from '../lib/auth/AuthContext';
import { Badge, Button, EmptyState, ErrorState, Field, Input, LoadingState, Modal, PageHeader, StatusChip } from '../components/ui';
import { pushToast } from '../components/ui';
import type { AdminDonationRow } from '../lib/api/types';

export function DonationsPage() {
  const { data, loading, error, reload } = useAsync(() => listDonations(), []);
  const [refunding, setRefunding] = useState<AdminDonationRow | null>(null);
  const [reason, setReason] = useState('');
  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState<string | null>(null);

  async function onRefund() {
    if (!refunding) return;
    if (!reason.trim()) {
      setErr('A refund reason is required (donations.refund is audited).');
      return;
    }
    setBusy(true);
    setErr(null);
    try {
      await refundDonation(refunding.uid, reason.trim());
      pushToast('success', 'Refund initiated.');
      setRefunding(null);
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
      <PageHeader title="Donations" subtitle="View all contributions across campaigns. Refunds require a recorded reason." />
      {loading ? <LoadingState /> : null}
      {error ? <ErrorState message={error} onRetry={reload} /> : null}
      {!loading && !error ? (
        data && data.length > 0 ? (
          <div className="sw-tablewrap" style={{ marginTop: 16 }}>
            <table className="sw-table">
              <thead>
                <tr>
                  <th scope="col">Campaign</th>
                  <th scope="col">Donor</th>
                  <th scope="col">Amount</th>
                  <th scope="col">Status</th>
                  <th scope="col">Actions</th>
                </tr>
              </thead>
              <tbody>
                {data.map((d) => (
                  <tr key={d.uid}>
                    <td>{d.campaign_title || '—'}</td>
                    <td>{d.donor_email || '—'}</td>
                    <td>
                      <strong>
                        {d.currency} {d.amount.toLocaleString()}
                      </strong>
                    </td>
                    <td><StatusChip status={d.status} /></td>
                    <td>
                      {d.status === 'confirmed' || d.status === 'refunded' ? (
                        <Button variant="secondary" onClick={() => setRefunding(d)}>Refund</Button>
                      ) : (
                        <Badge>{d.status}</Badge>
                      )}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        ) : (
          <EmptyState title="No donations" message="Donations from the public will appear here." />
        )
      ) : null}

      <Modal
        open={!!refunding}
        onClose={() => setRefunding(null)}
        title="Refund donation?"
        footer={
          <>
            <Button variant="ghost" onClick={() => setRefunding(null)} disabled={busy}>Cancel</Button>
            <Button variant="danger" loading={busy} onClick={onRefund}>Refund</Button>
          </>
        }
      >
        {refunding ? (
          <p className="sw-modal-msg" style={{ marginBottom: 14 }}>
            Refund {refunding.currency} {refunding.amount.toLocaleString()} from {refunding.campaign_title || 'the general fund'}?
          </p>
        ) : null}
        {err ? <p className="sw-err" role="alert" style={{ marginBottom: 12 }}>{err}</p> : null}
        <Field label="Refund reason" required hint="Recorded in the audit log.">
          <Input value={reason} onChange={(e) => setReason(e.target.value)} placeholder="Why is this refund needed?" />
        </Field>
      </Modal>
    </>
  );
}