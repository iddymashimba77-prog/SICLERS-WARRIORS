import { useState } from 'react';
import { broadcastNotification, listRoles } from '../lib/api/admin';
import { useAsync } from '../lib/useAsync';
import { friendlyError } from '../lib/auth/AuthContext';
import { Button, Card, Field, Input, PageHeader, Select, TextArea } from '../components/ui';
import { pushToast } from '../components/ui';

/** Backend vocabulary (`AdminBroadcastIn`): ALL | ROLE | USERS. */
const AUDIENCES = [
  { value: 'ALL', label: 'All users' },
  { value: 'ROLE', label: 'Everyone holding a role…' },
  { value: 'USERS', label: 'Specific accounts (by uid)…' },
];

export function NotificationsPage() {
  const { data: roles } = useAsync(() => listRoles(), []);
  const [audience, setAudience] = useState<'ALL' | 'ROLE' | 'USERS'>('ALL');
  const [roleCode, setRoleCode] = useState('');
  const [recipients, setRecipients] = useState('');
  const [title, setTitle] = useState('');
  const [message, setMessage] = useState('');
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function send() {
    if (!title.trim() || !message.trim()) {
      setError('A title and message are required.');
      return;
    }
    if (audience === 'ROLE' && !roleCode) {
      setError('Choose the role this broadcast should reach.');
      return;
    }
    const uids = recipients
      .split(/[\s,]+/)
      .map((s) => s.trim())
      .filter(Boolean);
    if (audience === 'USERS' && uids.length === 0) {
      setError('Paste at least one account uid.');
      return;
    }
    if (uids.length > 500) {
      setError('A targeted broadcast is capped at 500 recipients.');
      return;
    }
    setBusy(true);
    setError(null);
    try {
      await broadcastNotification({
        audience,
        title: title.trim(),
        body: message.trim(),
        ...(audience === 'ROLE' ? { role_code: roleCode } : {}),
        ...(audience === 'USERS' ? { user_uid: uids } : {}),
      });
      pushToast('success', `Broadcast sent to ${audience === 'ALL' ? 'all users' : audience === 'ROLE' ? roleCode : `${uids.length} account(s)`}.`);
      setTitle('');
      setMessage('');
      setRecipients('');
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
          <Select
            value={audience}
            onChange={(e) => setAudience(e.target.value as 'ALL' | 'ROLE' | 'USERS')}
          >
            {AUDIENCES.map((a) => (
              <option key={a.value} value={a.value}>{a.label}</option>
            ))}
          </Select>
        </Field>
        {audience === 'ROLE' ? (
          <Field label="Role" required>
            <Select value={roleCode} onChange={(e) => setRoleCode(e.target.value)}>
              <option value="">Choose a role…</option>
              {(roles ?? []).map((r) => (
                <option key={r.code} value={r.code}>{r.name} ({r.code})</option>
              ))}
            </Select>
          </Field>
        ) : null}
        {audience === 'USERS' ? (
          <Field label="Account uids" required hint="Comma or newline separated, maximum 500 recipients.">
            <TextArea rows={4} value={recipients} onChange={(e) => setRecipients(e.target.value)} placeholder="uid-1, uid-2, …" />
          </Field>
        ) : null}
        <Field label="Title" required>
          <Input value={title} onChange={(e) => setTitle(e.target.value)} placeholder="Headline" maxLength={200} />
        </Field>
        <Field label="Message" required>
          <TextArea rows={5} value={message} onChange={(e) => setMessage(e.target.value)} placeholder="Notification body" maxLength={5000} />
        </Field>
        <Button loading={busy} onClick={send}>Send broadcast</Button>
        <p style={{ color: 'var(--sw-text-muted)', fontSize: 12, marginTop: 10 }}>
          Broadcasts create in-app system notifications and are recorded in the audit log.
        </p>
      </Card>
    </>
  );
}
