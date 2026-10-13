import { useRef, useState } from 'react';
import { listNews, createNews, updateNews, setNewsStatus, setNewsFeatured, setNewsPinned, deleteNews, restoreNews, uploadNewsCover, type NewsDraft } from '../lib/api/admin';
import { useAsync } from '../lib/useAsync';
import { friendlyError } from '../lib/auth/AuthContext';
import { Badge, Button, ConfirmDialog, EmptyState, ErrorState, Field, Input, LoadingState, Modal, PageHeader, Select, StatusChip, TextArea } from '../components/ui';
import { pushToast } from '../components/ui';
import type { AdminNewsRow } from '../lib/api/types';

const EMPTY_DRAFT: NewsDraft = { title: '', category: 'HEALTH', body: '', excerpt: '', cover_url: '', cover_alt: '', tags: [] };

/** The API speaks upper-case statuses; normalise defensively so a status chip
 *  or filter never silently fails to match. */
const isDeleted = (a: AdminNewsRow) => Boolean(a.deleted_at);

export function NewsPage() {
  const [status, setStatus] = useState('');
  const [showDeleted, setShowDeleted] = useState(false);
  const { data, loading, error, reload } = useAsync(
    () => listNews({ status: status || undefined, includeDeleted: showDeleted }),
    [status, showDeleted],
  );
  const [editing, setEditing] = useState<AdminNewsRow | 'new' | null>(null);
  const [deleting, setDeleting] = useState<AdminNewsRow | null>(null);
  const [busy, setBusy] = useState(false);

  return (
    <>
      <PageHeader title="News management" subtitle="Write, review and publish public health news for the community." />
      <div className="sw-toolbar">
        <Select value={status} onChange={(e) => setStatus(e.target.value)} aria-label="Filter by status" style={{ maxWidth: 220 }}>
          <option value="">All statuses</option>
          <option value="DRAFT">DRAFT</option>
          <option value="PUBLISHED">PUBLISHED</option>
          <option value="ARCHIVED">ARCHIVED</option>
        </Select>
        <label style={{ display: 'flex', alignItems: 'center', gap: 6 }}>
          <input type="checkbox" checked={showDeleted} onChange={(e) => setShowDeleted(e.target.checked)} />
          <span>Show deleted</span>
        </label>
        <Button variant="secondary" onClick={reload}>Refresh</Button>
        <Button onClick={() => setEditing('new')} style={{ marginLeft: 'auto' }}>New article</Button>
      </div>
      {loading ? <LoadingState /> : null}
      {error ? <ErrorState message={error} onRetry={reload} /> : null}
      {!loading && !error ? (
        data && data.length > 0 ? (
          <div className="sw-tablewrap" style={{ marginTop: 16 }}>
            <table className="sw-table">
              <thead>
                <tr>
                  <th scope="col">Article</th>
                  <th scope="col">Category</th>
                  <th scope="col">Status</th>
                  <th scope="col">Flags</th>
                  <th scope="col">Actions</th>
                </tr>
              </thead>
              <tbody>
                {data.map((a) => (
                  <tr key={a.uid}>
                    <td>
                      <strong>{a.title}</strong>
                      <br />
                      <span style={{ color: 'var(--sw-text-muted)', fontSize: 12 }}>
                        {a.author?.display_name ? `by ${a.author.display_name} · ` : ''}
                        {a.published_at ? new Date(a.published_at).toLocaleDateString() : 'not published'}
                      </span>
                    </td>
                    <td><Badge tone="blue">{a.category_label || a.category}</Badge></td>
                    <td><StatusChip status={a.status} /></td>
                    <td>
                      <div style={{ display: 'flex', gap: 6, flexWrap: 'wrap' }}>
                        {a.featured ? <Badge tone="amber">Featured</Badge> : null}
                        {a.pinned ? <Badge tone="blue">Pinned</Badge> : null}
                        {isDeleted(a) ? <Badge tone="red">Deleted</Badge> : null}
                        {!a.featured && !a.pinned && !isDeleted(a) ? '—' : null}
                      </div>
                    </td>
                    <td>
                      <div style={{ display: 'flex', gap: 6, flexWrap: 'wrap' }}>
                        {isDeleted(a) ? (
                          <Button onClick={() => act(`restore-${a.uid}`, () => restoreNews(a.uid))}>Restore</Button>
                        ) : (
                          <>
                            <Button variant="secondary" onClick={() => setEditing(a)}>Edit</Button>
                            {a.status === 'DRAFT' || a.status === 'ARCHIVED' ? (
                              <Button onClick={() => act(`publish-${a.uid}`, () => setNewsStatus(a.uid, 'publish'))}>Publish</Button>
                            ) : null}
                            {a.status === 'PUBLISHED' ? (
                              <>
                                <Button variant="secondary" onClick={() => act(`unpublish-${a.uid}`, () => setNewsStatus(a.uid, 'unpublish'))}>Unpublish</Button>
                                <Button variant="soft" onClick={() => act(`archive-${a.uid}`, () => setNewsStatus(a.uid, 'archive'))}>Archive</Button>
                                <Button
                                  variant="soft"
                                  onClick={() => act(`pin-${a.uid}`, () => setNewsPinned(a.uid, !a.pinned))}
                                  title={a.pinned ? 'Remove from the top of the public list' : 'Show at the top of the public list'}
                                >
                                  {a.pinned ? 'Unpin' : 'Pin to top'}
                                </Button>
                              </>
                            ) : null}
                            {a.status === 'PUBLISHED' ? (
                              <Button
                                variant="soft"
                                onClick={() => act(`feature-${a.uid}`, () => setNewsFeatured(a.uid, !a.featured))}
                              >
                                {a.featured ? 'Unfeature' : 'Feature'}
                              </Button>
                            ) : null}
                            <Button variant="danger" onClick={() => setDeleting(a)}>Delete</Button>
                          </>
                        )}
                      </div>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        ) : (
          <div style={{ marginTop: 16 }}>
            <EmptyState title="No articles" message="Create the first news article for the community." />
          </div>
        )
      ) : null}

      {editing ? (
        <NewsEditorModal
          article={editing === 'new' ? null : editing}
          onClose={() => setEditing(null)}
          onSaved={() => { setEditing(null); reload(); }}
        />
      ) : null}
      <ConfirmDialog
        open={!!deleting}
        title="Remove article from the site?"
        message={
          deleting
            ? `"${deleting.title}" will be hidden from all public pages and unarchived. The article is kept in the database and can be restored afterwards.`
            : ''
        }
        confirmLabel="Remove"
        destructive
        loading={busy}
        onCancel={() => setDeleting(null)}
        onConfirm={async () => {
          if (!deleting) return;
          setBusy(true);
          try {
            await deleteNews(deleting.uid);
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

const NEWS_CATEGORIES = ['HEALTH', 'BLOOD', 'COMMUNITY', 'EDUCATION', 'EVENTS', 'ANNOUNCEMENTS', 'FUNDRAISING'];

function NewsEditorModal({ article, onClose, onSaved }: { article: AdminNewsRow | null; onClose: () => void; onSaved: () => void }) {
  const [draft, setDraft] = useState<NewsDraft>(
    article
      ? { title: article.title, category: article.category, body: article.body, excerpt: article.excerpt, cover_url: article.cover_url, cover_alt: article.cover_alt, tags: article.tags }
      : EMPTY_DRAFT,
  );
  const [tagsText, setTagsText] = useState((article?.tags ?? []).join(', '));
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [coverBusy, setCoverBusy] = useState(false);
  const [uid, setUid] = useState(article?.uid ?? null);
  const fileRef = useRef<HTMLInputElement>(null);

  function update<K extends keyof NewsDraft>(key: K, value: NewsDraft[K]) {
    setDraft((d) => ({ ...d, [key]: value }));
  }

  async function save() {
    if (!draft.title.trim() || !draft.body.trim()) {
      setError('A title and body are required.');
      return;
    }
    setBusy(true);
    setError(null);
    try {
      const payload = { ...draft, tags: tagsText.split(',').map((t) => t.trim()).filter(Boolean) };
      if (uid) {
        await updateNews(uid, payload);
        pushToast('success', 'Article updated.');
      } else {
        const created = await createNews(payload);
        setUid(created.uid);
        pushToast('success', 'Article saved. Publish it when ready.');
      }
      onSaved();
    } catch (e) {
      setError(friendlyError(e));
    } finally {
      setBusy(false);
    }
  }

  async function saveAndPublish() {
    if (!draft.title.trim() || !draft.body.trim()) {
      setError('A title and body are required.');
      return;
    }
    setBusy(true);
    setError(null);
    try {
      const payload = { ...draft, tags: tagsText.split(',').map((t) => t.trim()).filter(Boolean) };
      if (uid) {
        await updateNews(uid, payload);
        if (article?.status !== 'PUBLISHED') {
          await setNewsStatus(uid, 'publish');
        }
      } else {
        const created = await createNews(payload);
        setUid(created.uid);
        await setNewsStatus(created.uid, 'publish');
      }
      pushToast('success', 'Article published.');
      onSaved();
    } catch (e) {
      setError(friendlyError(e));
    } finally {
      setBusy(false);
    }
  }

  async function onCover(e: React.ChangeEvent<HTMLInputElement>) {
    const file = e.target.files?.[0];
    if (!file || !uid) return;
    setCoverBusy(true);
    setError(null);
    try {
      await uploadNewsCover(uid, file, draft.cover_alt);
      pushToast('success', 'Cover image uploaded.');
    } catch (err) {
      setError(friendlyError(err));
    } finally {
      setCoverBusy(false);
      if (fileRef.current) fileRef.current.value = '';
    }
  }

  return (
    <Modal
      open
      onClose={onClose}
      title={article ? 'Edit article' : 'New article'}
      footer={
        <>
          <Button variant="ghost" onClick={onClose} disabled={busy}>Cancel</Button>
          <Button loading={busy} onClick={save}>{uid ? 'Save changes' : 'Save draft'}</Button>
          {uid === null || article?.status !== 'PUBLISHED' ? (
            <Button loading={busy} onClick={saveAndPublish}>Save &amp; publish</Button>
          ) : null}
        </>
      }
    >
      {error ? <p className="sw-err" role="alert" style={{ marginBottom: 12 }}>{error}</p> : null}
      <Field label="Title" required>
        <Input value={draft.title} onChange={(e) => update('title', e.target.value)} placeholder="Article headline" />
      </Field>
      <div className="sw-grid sw-grid-2">
        <Field label="Category">
          <Select value={draft.category} onChange={(e) => update('category', e.target.value)}>
            {NEWS_CATEGORIES.map((c) => (
              <option key={c} value={c}>{c}</option>
            ))}
          </Select>
        </Field>
        <Field label="Tags">
          <Input value={tagsText} onChange={(e) => setTagsText(e.target.value)} placeholder="sickle-cell, care, …" />
        </Field>
      </div>
      <Field label="Excerpt">
        <TextArea rows={2} value={draft.excerpt} onChange={(e) => update('excerpt', e.target.value)} placeholder="Short summary shown in lists" />
      </Field>
      <Field label="Body" required>
        <TextArea rows={8} value={draft.body} onChange={(e) => update('body', e.target.value)} placeholder="Full article content" />
      </Field>
      <Field label="Cover image URL">
        <Input value={draft.cover_url} onChange={(e) => update('cover_url', e.target.value)} placeholder="https://…" />
      </Field>
      <Field label="Cover alt text">
        <Input value={draft.cover_alt} onChange={(e) => update('cover_alt', e.target.value)} placeholder="Description for accessibility" />
      </Field>
      {uid ? (
        <Field label="Upload cover image" hint="PNG, JPEG or WebP.">
          <div style={{ display: 'flex', gap: 8 }}>
            <input ref={fileRef} type="file" accept="image/png,image/jpeg,image/webp" onChange={onCover} />
            {coverBusy ? <LoadingState label="Uploading…" /> : null}
          </div>
        </Field>
      ) : null}
    </Modal>
  );
}