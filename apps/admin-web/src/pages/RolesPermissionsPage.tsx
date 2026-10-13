import { useState } from 'react';
import { listRoles, listPermissionCatalog, listRolePermissions, setRolePermission } from '../lib/api/admin';
import { useAsync } from '../lib/useAsync';
import { friendlyError, useAuth } from '../lib/auth/AuthContext';
import { Badge, Button, Card, ErrorState, Field, Input, LoadingState, Modal, PageHeader, StatusChip } from '../components/ui';
import { pushToast } from '../components/ui';
import type { AdminRoleRow } from '../lib/api/types';

export function RolesPermissionsPage() {
  const { hasPerm } = useAuth();
  const { data, loading, error, reload } = useAsync(() => listRoles(), []);
  const [selected, setSelected] = useState<AdminRoleRow | null>(null);
  const canEdit = hasPerm('admin.permissions.manage');

  return (
    <>
      <PageHeader title="Roles & permissions" subtitle="Role-based access across the platform. System roles are managed by the backend." />
      {loading ? <LoadingState /> : null}
      {error ? <ErrorState message={error} onRetry={reload} /> : null}
      {!loading && !error ? (
        data && data.length > 0 ? (
          <div style={{ display: 'grid', gap: 12 }}>
            {data.map((r) => (
              <Card key={r.code} style={{ padding: 16 }}>
                <div style={{ display: 'flex', justifyContent: 'space-between', gap: 16, flexWrap: 'wrap' }}>
                  <div>
                    <h3 style={{ marginBottom: 2 }}>
                      {r.name} <Badge tone="navy">{r.code}</Badge>
                    </h3>
                    <p style={{ fontSize: 13, color: 'var(--sw-text-2)' }}>
                      {r.member_count ?? 0} member(s) · {r.permission_count ?? 0} permission(s)
                      {r.is_system ? ' · System role' : ''}
                    </p>
                  </div>
                  <Button variant="secondary" onClick={() => setSelected(r)}>View permissions</Button>
                </div>
              </Card>
            ))}
          </div>
        ) : (
          <Card style={{ padding: 16 }}>
            <StatusChip status="No roles returned by the backend." />
          </Card>
        )
      ) : null}

      {selected ? (
        <RolePermissionsModal
          role={selected}
          canEdit={canEdit}
          onClose={() => setSelected(null)}
        />
      ) : null}
    </>
  );
}

interface MatrixData {
  catalog: { code: string; module?: string; resource?: string; action?: string; name?: string }[];
  granted: string[];
}

function RolePermissionsModal({ role, canEdit, onClose }: { role: AdminRoleRow; canEdit: boolean; onClose: () => void }) {
  const { user } = useAuth();
  const { data, loading, error, reload } = useAsync<MatrixData>(async () => {
    const [catalog, granted] = await Promise.all([
      listPermissionCatalog(),
      listRolePermissions(role.code),
    ]);
    return { catalog, granted };
  }, [role.code]);

  const [draft, setDraft] = useState<Set<string> | null>(null);
  const [reason, setReason] = useState('');
  const [busy, setBusy] = useState(false);

  const granted = data?.granted ?? [];
  const catalog = data?.catalog ?? [];
  const perms = draft ?? new Set(granted);

  const added = catalog.map((p) => p.code).filter((c) => perms.has(c) && !granted.includes(c));
  const removed = granted.filter((c) => !perms.has(c));
  const dirty = added.length > 0 || removed.length > 0;
  const reasonOk = reason.trim().length >= 5;
  const holdsOwnRole = (user?.role_codes ?? []).includes(role.code);

  function toggle(code: string) {
    const next = new Set(perms);
    if (next.has(code)) next.delete(code);
    else next.add(code);
    setDraft(next);
  }

  async function save() {
    if (!reasonOk) return;
    setBusy(true);
    try {
      // One edge per request: the backend grants/revokes a single
      // role↔permission edge per call and audits each change separately.
      for (const code of added) {
        await setRolePermission(role.code, code, true, reason.trim());
      }
      for (const code of removed) {
        await setRolePermission(role.code, code, false, reason.trim());
      }
      setDraft(null);
      setReason('');
      reload();
      pushToast('success', `Permissions for ${role.name} updated.`);
    } catch (e) {
      pushToast('error', friendlyError(e));
      reload();
    } finally {
      setBusy(false);
    }
  }

  const modules = new Map<string, typeof catalog>();
  for (const p of catalog) {
    const key = p.module || 'other';
    if (!modules.has(key)) modules.set(key, []);
    modules.get(key)!.push(p);
  }

  return (
    <Modal
      open
      onClose={onClose}
      title={`${role.name} — permissions`}
      footer={
        <>
          <Button variant="ghost" onClick={onClose} disabled={busy}>Close</Button>
          {canEdit ? (
            <Button loading={busy} disabled={!dirty || !reasonOk} onClick={save}>
              Save {added.length + removed.length || ''} change(s)
            </Button>
          ) : null}
        </>
      }
    >
      {loading ? <LoadingState /> : null}
      {error ? <ErrorState message={error} onRetry={reload} /> : null}
      {!loading && !error ? (
        <>
          {holdsOwnRole ? (
            <p style={{ color: 'var(--sw-warning)', fontSize: 12, marginBottom: 10 }}>
              Your account holds this role — revoking permissions here takes effect on your own session.
            </p>
          ) : null}

          {granted.length === 0 && catalog.length === 0 ? (
            <p style={{ color: 'var(--sw-text-muted)' }}>No permissions assigned.</p>
          ) : (
            <div style={{ display: 'grid', gap: 14 }}>
              {[...modules.entries()].map(([mod, rows]) => (
                <div key={mod}>
                  <p style={{ fontSize: 11, textTransform: 'uppercase', letterSpacing: 0.4, color: 'var(--sw-text-muted)', marginBottom: 6 }}>
                    {mod}
                  </p>
                  <div style={{ display: 'grid', gap: 6 }}>
                    {rows.map((p) => (
                      <label
                        key={p.code}
                        style={{ display: 'flex', alignItems: 'center', gap: 10, cursor: canEdit ? 'pointer' : 'default' }}
                      >
                        <input
                          type="checkbox"
                          checked={perms.has(p.code)}
                          disabled={!canEdit}
                          onChange={() => toggle(p.code)}
                        />
                        <code style={{ fontSize: 12 }}>{p.code}</code>
                        <span style={{ fontSize: 12, color: 'var(--sw-text-muted)' }}>{p.name ?? ''}</span>
                      </label>
                    ))}
                  </div>
                </div>
              ))}
            </div>
          )}

          {canEdit && dirty ? (
            <div style={{ marginTop: 14, paddingTop: 12, borderTop: '1px solid var(--sw-border)' }}>
              <p style={{ fontSize: 12, color: 'var(--sw-text-2)', marginBottom: 8 }}>
                Pending: <strong>+{added.length}</strong> granted, <strong>−{removed.length}</strong> revoked.
                Each change is written as its own audited edge.
              </p>
              <Field label="Reason" required hint="Recorded in the audit trail for every change (min 5 characters).">
                <Input
                  value={reason}
                  onChange={(e) => setReason(e.target.value)}
                  placeholder="e.g. quarterly access review"
                />
              </Field>
            </div>
          ) : null}
        </>
      ) : null}
    </Modal>
  );
}
