import { useState } from 'react';
import { listTicker, createTicker, updateTicker, setTickerActive, deleteTicker } from '../lib/api/admin';
import { useAsync } from '../lib/useAsync';
import { friendlyError } from '../lib/auth/AuthContext';
import { Badge, Button, ConfirmDialog, EmptyState, ErrorState, Field, Input, LoadingState, Modal, PageHeader, Select, TextArea, Toggle } from '../components/ui';
import { pushToast } from '../components/ui';
import type { AdminTickerRow } from '../lib/api/types';

const EMPTY_DRAFT = { message: '', announcement_type: 'INFO', link_url: '', is_active: false, priority: 0 };

export function TickerPage() {
  const [activeOnly, setActiveOnly] = useState(false);
  const { data, loading, error, reload } = useAsync(() => listTicker({ active: activeOnly || undefined }), [activeOnly]);
  const [editing, setEditing] = useState<AdminTickerRow | 'new' | null>(null);
  const [deleting, setDeleting] = useState<AdminTickerRow | null>(null);
  const [busy, setBusy] = useState(false);

  return (
    <>
      <PageHeader title="Announcement ticker" subtitle="Splash messages shown across the app on the ticker bar." />
      <div className="sw-toolbar">
        <Toggle label="Active only" checked={activeOnly} onChange={setActiveOnly} />
        <Button variant="secondary" onClick={reload}>Refresh</Button>
        <Button onClick={() => setEditing('new')} style={{ marginLeft: 'auto' }}>New announcement</Button>
      </div>
      {loading ? <LoadingState /> : null}
      {error ? <ErrorState message={error} onRetry={reload} /> : null}
      {!loading && !error ? (
        data && data.length > 0 ? (
          <div className="sw-tablewrap" style={{ marginTop: 16 }}>
            <table className="sw-table">
              <thead>
                <tr>
                  <th scope="col">Message</th>
                  <th scope="col">Type</th>
                  <th scope="col">Active</th>
                  <th scope="col">Priority</th>
                  <th scope="col">Actions</th>
                </tr>
              </thead>
              <tbody>
                {data.map((t) => (
                  <tr key={t.uid}>
                    <td>
                      <strong>{t.message}</strong>
                      {t.link_url ? (
                        <>
                          <br />
                          <span style={{ color: 'var(--sw-text-muted)', fontSize: 12 }}>{t.link_url}</span>
                        </>
                      ) : null}
                    </td>
                    <td><Badge tone={t.announcement_type === 'ALERT' ? 'red' : t.is_active ? 'blue' : 'gray'}>{t.announcement_type_label || t.announcement_type}</Badge></td>
                    <td>{t.is_active ? <Badge tone="green">ACTIVE</Badge> : <Badge>INACTIVE</Badge>}</td>
                    <td>{t.priority}</td>
                    <td>
                      <div style={{ display: 'flex', gap: 6 }}>
                        <Button variant="secondary" onClick={() => setEditing(t)}>Edit</Button>
                        <Button
                          variant={t.is_active ? 'secondary' : 'soft'}
                          onClick={async () => {
                            try {
                              await setTickerActive(t.uid, !t.is_active);
                              reload();
                            } catch (e) {
                              pushToast('error', friendlyError(e));
                            }
                          }}
                        >
                          {t.is_active ? 'Deactivate' : 'Activate'}
                        </Button>
                        <Button variant="danger" onClick={() => setDeleting(t)}>Delete</Button>
                      </div>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        ) : (
          <div style={{ marginTop: 16 }}>
            <EmptyState title="No announcements" message="Create a ticker announcement to reach the community." />
          </div>
        )
      ) : null}

      {editing ? (
        <TickerEditorModal
          ticker={editing === 'new' ? null : editing}
          onClose={() => setEditing(null)}
          onSaved={() => { setEditing(null); reload(); }}
        />
      ) : null}
      <ConfirmDialog
        open={!!deleting}
        title="Delete announcement?"
        message={`"${deleting?.message ?? ''}" will be permanently removed.`}
        confirmLabel="Delete"
        destructive
        loading={busy}
        onCancel={() => setDeleting(null)}
        onConfirm={async () => {
          if (!deleting) return;
          setBusy(true);
          try {
            await deleteTicker(deleting.uid);
            pushToast('success', 'Announcement deleted.');
            setDeleting(null);
            reload();
          } catch (e) {
            pushToast('error', friendlyError(e));
          } finally {
            setBusy(false);
          }
        }}
      />
    </>
  );
}

const TICKER_TYPES = ['INFO', 'URGENT', 'BLOOD', 'EVENT', 'DONATION', 'SUCCESS'];

function TickerEditorModal({ ticker, onClose, onSaved }: { ticker: AdminTickerRow | null; onClose: () => void; onSaved: () => void }) {
  const [draft, setDraft] = useState(
    ticker
      ? { message: ticker.message, announcement_type: ticker.announcement_type, link_url: ticker.link_url ?? '', is_active: ticker.is_active, priority: ticker.priority }
      : EMPTY_DRAFT,
  );
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function save() {
    if (!draft.message.trim()) {
      setError('A message is required.');
      return;
    }
    setBusy(true);
    setError(null);
    try {
      if (ticker) {
        await updateTicker(ticker.uid, draft);
      } else {
        await createTicker(draft);
      }
      pushToast('success', ticker ? 'Announcement updated.' : 'Announcement created.');
      onSaved();
    } catch (e) {
      setError(friendlyError(e));
    } finally {
      setBusy(false);
    }
  }

  return (
    <Modal
      open
      onClose={onClose}
      title={ticker ? 'Edit announcement' : 'New announcement'}
      footer={
        <>
          <Button variant="ghost" onClick={onClose} disabled={busy}>Cancel</Button>
          <Button loading={busy} onClick={save}>{ticker ? 'Save changes' : 'Create'}</Button>
        </>
      }
    >
      {error ? <p className="sw-err" role="alert" style={{ marginBottom: 12 }}>{error}</p> : null}
      <Field label="Message" required>
        <TextArea rows={3} value={draft.message} onChange={(e) => setDraft((d) => ({ ...d, message: e.target.value }))} placeholder="Ticker announcement text" />
      </Field>
      <div className="sw-grid sw-grid-2">
        <Field label="Type">
          <Select value={draft.announcement_type} onChange={(e) => setDraft((d) => ({ ...d, announcement_type: e.target.value }))}>
            {TICKER_TYPES.map((t) => (
              <option key={t} value={t}>{t}</option>
            ))}
          </Select>
        </Field>
        <Field label="Priority">
          <Input type="number" value={draft.priority} onChange={(e) => setDraft((d) => ({ ...d, priority: Number(e.target.value) || 0 }))} />
        </Field>
      </div>
      <Field label="Link URL">
        <Input value={draft.link_url} onChange={(e) => setDraft((d) => ({ ...d, link_url: e.target.value }))} placeholder="https://… (optional)" />
      </Field>
      <Toggle label="Active immediately" checked={draft.is_active} onChange={(v) => setDraft((d) => ({ ...d, is_active: v }))} />
    </Modal>
  );
}