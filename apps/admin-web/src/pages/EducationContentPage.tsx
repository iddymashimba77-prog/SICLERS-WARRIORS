import { useState } from 'react';
import {
  listEducationContent,
  reviewEducationContent,
  listEducationCategories,
  createEducation,
  updateEducation,
  publishEducation,
  deleteEducation,
  type EducationDraft,
  type EducationCategoryOption,
} from '../lib/api/admin';
import { useAsync } from '../lib/useAsync';
import { friendlyError } from '../lib/auth/AuthContext';
import { Button, EmptyState, ErrorState, Field, Input, LoadingState, Modal, PageHeader, Select, StatusChip, TextArea, ConfirmDialog } from '../components/ui';
import { pushToast } from '../components/ui';
import type { AdminEducationItemRow } from '../lib/api/types';

const EMPTY_DRAFT: EducationDraft = { title: '', body: '', category: '', cover_url: '' };

export function EducationContentPage() {
  const [status, setStatus] = useState('');
  const { data, loading, error, reload } = useAsync(() => listEducationContent({ status: status || undefined }), [status]);
  const [editing, setEditing] = useState<AdminEducationItemRow | 'new' | null>(null);
  const [subject, setSubject] = useState<AdminEducationItemRow | null>(null);
  const [deleting, setDeleting] = useState<AdminEducationItemRow | null>(null);
  const [approve, setApprove] = useState(true);
  const [busy, setBusy] = useState(false);

  async function onConfirm(reason: string) {
    if (!subject) return;
    setBusy(true);
    try {
      await reviewEducationContent(subject.uid, approve, reason);
      pushToast('success', approve ? 'Content approved.' : 'Content rejected.');
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
      <PageHeader title="Education content" subtitle="Write, publish and review the Warrior Academy library. Users only see published articles." />
      <div className="sw-toolbar">
        <Select value={status} onChange={(e) => setStatus(e.target.value)} aria-label="Filter by status" style={{ maxWidth: 220 }}>
          <option value="">All statuses</option>
          <option value="DRAFT">DRAFT</option>
          <option value="IN_REVIEW">PENDING</option>
          <option value="PUBLISHED">PUBLISHED</option>
          <option value="REJECTED">REJECTED</option>
          <option value="ARCHIVED">ARCHIVED</option>
        </Select>
        <Button variant="secondary" onClick={reload}>Refresh</Button>
        <Button onClick={() => setEditing('new')} style={{ marginLeft: 'auto' }}>New article</Button>
      </div>
      {loading ? <LoadingState /> : null}
      {error ? <ErrorState message={error} onRetry={reload} /> : null}
      {!loading && !error ? (
        data && data.length > 0 ? (
          <div style={{ display: 'grid', gap: 12 }}>
            {data.map((e) => (
              <EditorCard
                key={e.uid}
                item={e}
                onEdit={() => setEditing(e)}
                onPublish={async () => { await act(`publish-${e.uid}`, () => publishEducation(e.uid)); }}
                onDelete={async () => setDeleting(e)}
                onApprove={() => { setApprove(true); setSubject(e); }}
                onReject={() => { setApprove(false); setSubject(e); }}
              />
            ))}
          </div>
        ) : (
          <EmptyState title="No content found" message="No educational items match the current filter. Write one for the library." />
        )
      ) : null}

      {editing ? (
        <EditorModal
          item={editing === 'new' ? null : editing}
          onClose={() => setEditing(null)}
          onSaved={() => { setEditing(null); reload(); }}
        />
      ) : null}

      <DecisionModal
        open={!!subject}
        title={approve ? 'Approve content?' : 'Reject content?'}
        subject={subject?.title ?? ''}
        approve={approve}
        loading={busy}
        reasonRequired={!approve}
        onCancel={() => setSubject(null)}
        onConfirm={onConfirm}
      />

      <ConfirmDialog
        open={!!deleting}
        title="Delete article?"
        message={deleting ? `"${deleting.title}" will be permanently removed.` : ''}
        confirmLabel="Delete"
        destructive
        loading={busy}
        onCancel={() => setDeleting(null)}
        onConfirm={async () => {
          if (!deleting) return;
          setBusy(true);
          try {
            await deleteEducation(deleting.uid);
            pushToast('success', 'Article deleted.');
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

  async function act(_key: string, fn: () => Promise<void>) {
    setBusy(true);
    try {
      await fn();
      reload();
    } catch (e) {
      pushToast('error', friendlyError(e));
    } finally {
      setBusy(false);
    }
  }
}

function EditorCard({ item, onEdit, onPublish, onDelete, onApprove, onReject }: {
  item: AdminEducationItemRow;
  onEdit: () => void;
  onPublish: () => Promise<void>;
  onDelete: () => Promise<void>;
  onApprove: () => void;
  onReject: () => void;
}) {
  return (
    <div className="sw-card" style={{ padding: 16 }}>
      <div style={{ display: 'flex', justifyContent: 'space-between', gap: 16, flexWrap: 'wrap' }}>
        <div>
          <h3 style={{ marginBottom: 2 }}>{item.title}</h3>
          <p style={{ fontSize: 13, color: 'var(--sw-text-2)' }}>
            {item.category?.name ?? item.category?.code ?? 'Uncategorized'}
            {item.author?.display_name ? ` · by ${item.author.display_name}` : ''}
          </p>
        </div>
        <div style={{ textAlign: 'right' }}>
          <StatusChip status={item.status} />
        </div>
      </div>
      <div style={{ display: 'flex', gap: 8, marginTop: 12, flexWrap: 'wrap' }}>
        {item.status === 'DRAFT' || item.status === 'REJECTED' || item.status === 'ARCHIVED' ? (
          <Button variant="secondary" onClick={onEdit}>Edit</Button>
        ) : null}
        {item.status === 'DRAFT' || item.status === 'REJECTED' || item.status === 'ARCHIVED' ? (
          <Button onClick={onPublish}>Publish</Button>
        ) : null}
        {item.status === 'DRAFT' ? (
          <Button variant="danger" onClick={onDelete}>Delete</Button>
        ) : null}
        {item.status === 'IN_REVIEW' ? (
          <>
            <Button onClick={onApprove}>Approve</Button>
            <Button variant="danger" onClick={onReject}>Reject</Button>
          </>
        ) : null}
      </div>
    </div>
  );
}

function EditorModal({ item, onClose, onSaved }: { item: AdminEducationItemRow | null; onClose: () => void; onSaved: () => void }) {
  const [draft, setDraft] = useState<EducationDraft>(
    item
      ? { title: item.title, body: item.body ?? '', category: item.category?.code ?? '', cover_url: item.cover_url ?? '' }
      : EMPTY_DRAFT,
  );
  const [uid, setUid] = useState<string | null>(item?.uid ?? null);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const { data: categories } = useAsync(() => listEducationCategories(), []);

  function update<K extends keyof EducationDraft>(key: K, value: EducationDraft[K]) {
    setDraft((d) => ({ ...d, [key]: value }));
  }

  function validate(): boolean {
    if (!draft.title.trim() || !draft.body.trim()) {
      setError('A title and body are required.');
      return false;
    }
    if (!draft.category) {
      setError('Choose a category.');
      return false;
    }
    return true;
  }

  async function save(next: 'save' | 'publish') {
    if (!validate()) return;
    setBusy(true);
    setError(null);
    try {
      if (uid) {
        await updateEducation(uid, draft);
        if (next === 'publish') await publishEducation(uid);
      } else {
        const created = await createEducation(draft);
        setUid(created.uid);
        if (next === 'publish') await publishEducation(created.uid);
      }
      pushToast('success', next === 'publish' ? 'Article published to the library.' : 'Article saved.');
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
      title={item ? 'Edit article' : 'New article'}
      width={640}
      footer={
        <>
          <Button variant="ghost" onClick={onClose} disabled={busy}>Cancel</Button>
          <Button loading={busy} onClick={() => save('save')}>{uid ? 'Save changes' : 'Save draft'}</Button>
          {item?.status !== 'PUBLISHED' ? (
            <Button loading={busy} onClick={() => save('publish')}>Save &amp; publish</Button>
          ) : null}
        </>
      }
    >
      {error ? <p className="sw-err" role="alert" style={{ marginBottom: 12 }}>{error}</p> : null}
      <Field label="Title" required>
        <Input value={draft.title} onChange={(e) => update('title', e.target.value)} placeholder="Article headline" />
      </Field>
      <Field label="Category" required>
        <Select value={draft.category} onChange={(e) => update('category', e.target.value)}>
          <option value="">Select a category…</option>
          {(categories ?? []).map((c: EducationCategoryOption) => (
            <option key={c.code} value={c.code}>{c.name}</option>
          ))}
        </Select>
      </Field>
      <Field label="Body" required>
        <TextArea rows={10} value={draft.body} onChange={(e) => update('body', e.target.value)} placeholder="Full article content" />
      </Field>
      <Field label="Cover image URL">
        <Input value={draft.cover_url ?? ''} onChange={(e) => update('cover_url', e.target.value)} placeholder="https://…" />
      </Field>
    </Modal>
  );
}

function DecisionModal({ open, title, subject, approve, loading, reasonRequired, onCancel, onConfirm }: {
  open: boolean;
  title: string;
  subject: string;
  approve: boolean;
  loading: boolean;
  reasonRequired: boolean;
  onCancel: () => void;
  onConfirm: (reason: string) => Promise<void> | void;
}) {
  const [reason, setReason] = useState('');
  return (
    <Modal
      open={open}
      onClose={onCancel}
      title={title}
      footer={
        <>
          <Button variant="ghost" onClick={onCancel} disabled={loading}>Cancel</Button>
          <Button
            loading={loading}
            disabled={reasonRequired && !reason.trim()}
            onClick={() => onConfirm(reason.trim())}
          >
            {approve ? 'Approve' : 'Reject'}
          </Button>
        </>
      }
    >
      <p style={{ marginBottom: 12 }}>“{subject}”</p>
      <Field label={approve ? 'Note (optional)' : 'Reason (required to reject)'} required={reasonRequired}>
        <TextArea rows={3} value={reason} onChange={(e) => setReason(e.target.value)} placeholder={approve ? 'Optional note for the author…' : 'Why is this being rejected?'} />
      </Field>
    </Modal>
  );
}