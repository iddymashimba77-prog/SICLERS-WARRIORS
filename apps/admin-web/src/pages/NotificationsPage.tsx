import { useState } from 'react';
import { broadcastNotification } from '../lib/api/admin';
import { friendlyError } from '../lib/auth/AuthContext';
import { Button, Card, Field, Input, PageHeader, Select, TextArea } from '../components/ui';
import { pushToast } from '../components/ui';

const AUDIENCES = [
  { value: 'ALL_USERS', label: 'All users' },
  { value: 'PATIENTS', label: 'Patients only' },
  { value: 'DONORS', label: 'Donors only' },
  { value: 'VERIFIED_DOCTORS', label: 'Verified doctors' },
  { value: 'FACILITY_ADMINS', label: 'Facility administrators' },
  { value: 'ADMIN_STAFF', label: 'Admin staff only' },
];

export function NotificationsPage() {
  const [audience, setAudience] = useState('ALL_USERS');
  const [title, setTitle] = useState('');
  const [message, setMessage] = useState('');
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function send() {
    if (!title.trim() || !message.trim()) {
      setError('A title and message are required.');
      return;
    }
    setBusy(true);
    setError(null);
    try {
      await broadcastNotification({ audience, title: title.trim(), message: message.trim() });
      pushToast('success', `Broadcast queued for ${audience}.`);
      setTitle('');
      setMessage('');
    } catch (e) {
      setError(friendlyError(e));
    } finally {
      setBusy(false);
    }
  }

  return (
    <>
      <PageHeader title="Notifications" subtitle="Broadcast announcements to users. Sent through the backend's official channel." />
      <Card style={{ padding: 16, maxWidth: 560 }}>
        {error ? <p className="sw-err" role="alert" style={{ marginBottom: 12 }}>{error}</p> : null}
        <Field label="Audience">
          <Select value={audience} onChange={(e) => setAudience(e.target.value)}>
            {AUDIENCES.map((a) => (
              <option key={a.value} value={a.value}>{a.label}</option>
            ))}
          </Select>
        </Field>
        <Field label="Title" required>
          <Input value={title} onChange={(e) => setTitle(e.target.value)} placeholder="Headline" />
        </Field>
        <Field label="Message" required>
          <TextArea rows={5} value={message} onChange={(e) => setMessage(e.target.value)} placeholder="Notification body" />
        </Field>
        <Button loading={busy} onClick={send}>Send broadcast</Button>
        <p style={{ color: 'var(--sw-text-muted)', fontSize: 12, marginTop: 10 }}>
          Broadcasts are recorded in the audit log.
        </p>
      </Card>
    </>
  );
}