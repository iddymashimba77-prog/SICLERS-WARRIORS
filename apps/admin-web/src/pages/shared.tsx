import { useState } from 'react';
import { Button, Field, Modal, TextArea, pushToast } from '../components/ui';
import { openVerificationDocument, verificationDocLabel } from '../lib/api/admin';
import { friendlyError } from '../lib/auth/AuthContext';
import type { AdminVerificationDocument } from '../lib/api/types';

/**
 * The documents an applicant submitted, each openable by the reviewer. The
 * actual file is streamed from the audited admin endpoint (server-side
 * permission + audit), so this renders a plain button, not a public link.
 */
export function SubmittedDocuments({ documents }: { documents?: AdminVerificationDocument[] }) {
  const [opening, setOpening] = useState<number | null>(null);
  const docs = documents ?? [];

  async function open(id: number) {
    setOpening(id);
    try {
      await openVerificationDocument(id);
    } catch (e) {
      pushToast('error', friendlyError(e));
    } finally {
      setOpening(null);
    }
  }

  if (docs.length === 0) {
    return (
      <p style={{ fontSize: 12, color: 'var(--sw-text-2)', marginTop: 10 }}>
        No verification documents attached yet.
      </p>
    );
  }

  return (
    <div style={{ marginTop: 10 }}>
      <p style={{ fontSize: 12, fontWeight: 600, marginBottom: 6 }}>Submitted documents</p>
      <div style={{ display: 'flex', flexWrap: 'wrap', gap: 8 }}>
        {docs.map((doc) => (
          <Button
            key={doc.id}
            variant="secondary"
            loading={opening === doc.id}
            onClick={() => open(doc.id)}
            title={doc.file_name || undefined}
          >
            {verificationDocLabel(doc.doc_type)} · View
          </Button>
        ))}
      </div>
    </div>
  );
}

export function DecisionModal({
  open,
  title,
  subject,
  approve,
  loading,
  reasonRequired,
  confirmLabel,
  reasonLabel,
  onCancel,
  onConfirm,
}: {
  open: boolean;
  title: string;
  subject: string;
  approve: boolean;
  loading?: boolean;
  reasonRequired?: boolean;
  confirmLabel?: string;
  reasonLabel?: string;
  onCancel: () => void;
  onConfirm: (reason: string) => void;
}) {
  const [reason, setReason] = useState('');
  const [touched, setTouched] = useState(false);
  const missing = reasonRequired && reason.trim().length === 0;

  return (
    <Modal
      open={open}
      onClose={onCancel}
      title={title}
      footer={
        <>
          <Button variant="ghost" onClick={onCancel} disabled={loading}>
            Cancel
          </Button>
          <Button
            variant={approve ? 'primary' : 'danger'}
            loading={loading}
            disabled={missing}
            onClick={() => onConfirm(reason.trim())}
          >
            {confirmLabel ?? (approve ? 'Approve' : 'Reject')}
          </Button>
        </>
      }
    >
      <p className="sw-modal-msg" style={{ marginBottom: 14 }}>
        {subject}
      </p>
      <Field
        label={reasonLabel ?? (approve ? 'Approval reason (optional)' : 'Rejection reason')}
        required={reasonRequired || !!approve}
        hint="The reason is recorded in the audit log."
        error={touched && missing ? 'A reason is required.' : undefined}
      >
        <TextArea
          rows={4}
          value={reason}
          onChange={(e) => setReason(e.target.value)}
          onBlur={() => setTouched(true)}
          placeholder="Short justification…"
        />
      </Field>
    </Modal>
  );
}