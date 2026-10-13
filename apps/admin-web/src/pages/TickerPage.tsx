import { useState } from 'react';
import { listTicker, createTicker, updateTicker, setTickerActive, deleteTicker, uploadTickerImage } from '../lib/api/admin';
import { useAsync } from '../lib/useAsync';
import { friendlyError } from '../lib/auth/AuthContext';
import { Badge, Button, ConfirmDialog, EmptyState, ErrorState, Field, Input, LoadingState, Modal, PageHeader, Select, TextArea, Toggle } from '../components/ui';
import { pushToast } from '../components/ui';
import type { AdminTickerRow } from '../lib/api/types';

const ACCEPTED_IMAGE_TYPES = ['image/jpeg', 'image/png', 'image/webp'];
const MAX_IMAGE_BYTES = 5 * 1024 * 1024;

interface TickerDraftState {
  message: string;
  announcement_type: string;
  link_url: string;
  is_active: boolean;
  priority: number;
  /** `datetime-local` values ("" = no window bound). */
  start_at: string;
  end_at: string;
}

const EMPTY_DRAFT: TickerDraftState = {
  message: '', announcement_type: 'INFO', link_url: '', is_active: false, priority: 0,
  start_at: '', end_at: '',
};

/** ISO timestamp → value for `<input type="datetime-local">` (local time, minute precision). */
function toLocalInput(iso?: string | null): string {
  if (!iso) return '';
  const d = new Date(iso);
  if (Number.isNaN(d.getTime())) return '';
  const shifted = new Date(d.getTime() - d.getTimezoneOffset() * 60000);
  return shifted.toISOString().slice(0, 16);
}

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
                      {t.image_url ? (
                        <div style={{ marginTop: 6 }}>
                          <img
                            src={t.image_url}
                            alt={t.image_alt || t.message}
                            style={{ height: 56, borderRadius: 'var(--sw-radius-sm)', border: '1px solid var(--sw-border)' }}
                          />
                        </div>
                      ) : null}
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
  const [draft, setDraft] = useState<TickerDraftState>(
    ticker
      ? {
          message: ticker.message,
          announcement_type: ticker.announcement_type,
          link_url: ticker.link_url ?? '',
          is_active: ticker.is_active,
          priority: ticker.priority,
          start_at: toLocalInput(ticker.start_at),
          end_at: toLocalInput(ticker.end_at),
        }
      : EMPTY_DRAFT,
  );
  const [imageFile, setImageFile] = useState<File | null>(null);
  const [imagePreview, setImagePreview] = useState<string | null>(null);
  const [imageAlt, setImageAlt] = useState('');
  const [imageError, setImageError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  function pickImage(file: File | null) {
    setImageError(null);
    if (!file) {
      setImageFile(null);
      setImagePreview(null);
      return;
    }
    if (!ACCEPTED_IMAGE_TYPES.includes(file.type)) {
      setImageError('Unsupported image. Use a JPEG, PNG or WebP file.');
      setImageFile(null);
      setImagePreview(null);
      return;
    }
    if (file.size > MAX_IMAGE_BYTES) {
      setImageError('The image exceeds the 5 MB limit.');
      setImageFile(null);
      setImagePreview(null);
      return;
    }
    setImageFile(file);
    const reader = new FileReader();
    reader.onload = () => setImagePreview(reader.result as string);
    reader.readAsDataURL(file);
  }

  async function save() {
    if (!draft.message.trim()) {
      setError('A message is required.');
      return;
    }
    if (draft.start_at && draft.end_at && draft.start_at >= draft.end_at) {
      setError('The window must start before it ends.');
      return;
    }
    setBusy(true);
    setError(null);
    try {
      const payload = {
        ...draft,
        start_at: draft.start_at ? new Date(draft.start_at).toISOString() : null,
        end_at: draft.end_at ? new Date(draft.end_at).toISOString() : null,
      };
      const saved = ticker
        ? await updateTicker(ticker.uid, payload)
        : await createTicker(payload);
      if (imageFile) {
        await uploadTickerImage(saved.uid, imageFile, imageAlt.trim());
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
      <Field label="Image" hint="Optional JPEG, PNG or WebP up to 5 MB — shown on the home-page ticker bar.">
        <div style={{ display: 'flex', alignItems: 'center', gap: 12 }}>
          {(imagePreview || (ticker?.image_url && !imagePreview) ? (
            <img
              src={imagePreview ?? ticker!.image_url ?? ''}
              alt={imageAlt || ticker?.image_alt || 'Announcement image'}
              style={{ height: 64, borderRadius: 'var(--sw-radius-sm)', border: '1px solid var(--sw-border)' }}
            />
          ) : null)}
          <input type="file" accept={ACCEPTED_IMAGE_TYPES.join(',')} onChange={(e) => pickImage(e.target.files?.[0] ?? null)} />
          {imageError ? <span className="sw-err" role="alert">{imageError}</span> : null}
        </div>
      </Field>
      <Field label="Image alt text" hint="Accessible description (optional).">
        <Input value={imageAlt} onChange={(e) => setImageAlt(e.target.value)} placeholder="Describe the image" />
      </Field>
      <div className="sw-grid sw-grid-2">
        <Field label="Window starts" hint="Optional — leave blank to run immediately.">
          <Input
            type="datetime-local"
            value={draft.start_at}
            onChange={(e) => setDraft((d) => ({ ...d, start_at: e.target.value }))}
          />
        </Field>
        <Field label="Window ends" hint="Optional — leave blank for no end date.">
          <Input
            type="datetime-local"
            value={draft.end_at}
            onChange={(e) => setDraft((d) => ({ ...d, end_at: e.target.value }))}
          />
        </Field>
      </div>
      <Toggle label="Active immediately" checked={draft.is_active} onChange={(v) => setDraft((d) => ({ ...d, is_active: v }))} />
    </Modal>
  );
}