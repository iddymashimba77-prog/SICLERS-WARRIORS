import { useState } from 'react';
import { Button, Field, Modal, TextArea } from '../components/ui';

export function DecisionModal({
  open,
  title,
  subject,
  approve,
  loading,
  reasonRequired,
  confirmLabel,
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
        label={approve ? 'Approval reason (optional)' : 'Rejection reason'}
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