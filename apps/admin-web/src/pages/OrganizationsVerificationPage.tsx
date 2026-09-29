import { useState } from 'react';
import { listFacilities, verifyFacility } from '../lib/api/admin';
import { useAsync } from '../lib/useAsync';
import { friendlyError } from '../lib/auth/AuthContext';
import { Badge, Button, EmptyState, ErrorState, LoadingState, PageHeader, Select, StatusChip } from '../components/ui';
import { pushToast } from '../components/ui';
import { DecisionModal } from './shared';
import type { AdminFacilityRow } from '../lib/api/types';

const TYPES = ['', 'hospital', 'clinic', 'blood_bank', 'research'];
const TYPES_LABEL: Record<string, string> = {
  '': 'All types',
  hospital: 'Hospital',
  clinic: 'Clinic',
  blood_bank: 'Blood bank',
  research: 'Research',
};

export function OrganizationsVerificationPage() {
  const [status, setStatus] = useState('');
  const [fType, setFType] = useState('');
  const { data, loading, error, reload } = useAsync(() => listFacilities({ status: status || undefined, facilityType: fType || undefined }), [status, fType]);
  const [subject, setSubject] = useState<AdminFacilityRow | null>(null);
  const [approve, setApprove] = useState(true);
  const [busy, setBusy] = useState(false);

  async function onConfirm(reason: string) {
    if (!subject) return;
    setBusy(true);
    try {
      await verifyFacility(subject.uid, approve, reason);
      pushToast('success', approve ? 'Organization verified.' : 'Organization rejected.');
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
      <PageHeader title="Organizations" subtitle="Hospitals, clinics and blood banks — verify legitimacy before they operate." />
      <div className="sw-toolbar">
        <Select value={status} onChange={(e) => setStatus(e.target.value)} aria-label="Filter by status" style={{ maxWidth: 220 }}>
          <option value="">All statuses</option>
          <option value="PENDING_VERIFICATION">PENDING_VERIFICATION</option>
          <option value="VERIFIED">VERIFIED</option>
          <option value="rejected">REJECTED</option>
          <option value="SUSPENDED">SUSPENDED</option>
        </Select>
        <Select value={fType} onChange={(e) => setFType(e.target.value)} aria-label="Filter by type" style={{ maxWidth: 220 }}>
          {TYPES.map((t) => (
            <option key={t} value={t}>{TYPES_LABEL[t]}</option>
          ))}
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
                  <th scope="col">Organization</th>
                  <th scope="col">Type</th>
                  <th scope="col">Status</th>
                  <th scope="col">Actions</th>
                </tr>
              </thead>
              <tbody>
                {data.map((f) => (
                  <tr key={f.uid}>
                    <td>
                      <strong>{f.name}</strong>
                      <br />
                      <span style={{ color: 'var(--sw-text-muted)', fontSize: 12 }}>{f.operator_email}</span>
                    </td>
                    <td><Badge tone="blue">{f.facility_type || '—'}</Badge></td>
                    <td><StatusChip status={f.verification_status} /></td>
                    <td style={{ whiteSpace: 'nowrap' }}>
                      <Button variant="secondary" style={{ marginRight: 6 }} onClick={() => { setApprove(true); setSubject(f); }}>
                        Verify
                      </Button>
                      <Button variant="danger" onClick={() => { setApprove(false); setSubject(f); }}>
                        Reject
                      </Button>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        ) : (
          <div style={{ marginTop: 16 }}>
            <EmptyState title="No organizations found" message="Try adjusting the filters." />
          </div>
        )
      ) : null}

      <DecisionModal
        open={!!subject}
        title={approve ? 'Verify organization?' : 'Reject organization?'}
        subject={subject?.name ?? ''}
        approve={approve}
        loading={busy}
        reasonRequired={!approve}
        onCancel={() => setSubject(null)}
        onConfirm={onConfirm}
      />
    </>
  );
}