import { useState } from 'react';
import { listRoles, listRolePermissions, setRolePermissions } from '../lib/api/admin';
import { useAsync } from '../lib/useAsync';
import { friendlyError, useAuth } from '../lib/auth/AuthContext';
import { Badge, Button, Card, ErrorState, LoadingState, Modal, PageHeader, StatusChip } from '../components/ui';
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

function RolePermissionsModal({ role, canEdit, onClose }: { role: AdminRoleRow; canEdit: boolean; onClose: () => void }) {
  const { hasAnyPerm } = useAuth();
  const { data, loading, error, reload } = useAsync(() => listRolePermissions(role.code), [role.code, role]);
  const [draft, setDraft] = useState<Set<string> | null>(null);
  const [busy, setBusy] = useState(false);
  const [saved, setSaved] = useState(false);

  const perms = draft ?? new Set((data ?? []).map((p) => p.code));

  function toggle(code: string) {
    const next = new Set(perms);
    if (next.has(code)) next.delete(code);
    else next.add(code);
    setDraft(next);
    setSaved(false);
  }

  async function save() {
    setBusy(true);
    try {
      await setRolePermissions(role.code, [...perms]);
      setSaved(true);
      setDraft(null);
      reload();
      pushToast('success', `Permissions for ${role.name} updated.`);
    } catch (e) {
      pushToast('error', friendlyError(e));
    } finally {
      setBusy(false);
    }
  }

  return (
    <Modal
      open
      onClose={onClose}
      title={`${role.name} — permissions`}
      footer={
        <>
          <Button variant="ghost" onClick={onClose}>Close</Button>
          {canEdit ? (
            <Button
              loading={busy}
              disabled={!draft || [...perms].length === (data ?? []).length}
              onClick={save}
            >
              Save changes
            </Button>
          ) : null}
        </>
      }
    >
      {loading ? <LoadingState /> : null}
      {error ? <ErrorState message={error} onRetry={reload} /> : null}
      {!loading && !error ? (
        <>
          {hasAnyPerm([role.code]) ? (
            <p style={{ color: 'var(--sw-text-muted)', fontSize: 12, marginBottom: 10 }}>
              This role also matches your account, so changes are applied carefully.
            </p>
          ) : null}
          {perms.size === 0 ? (
            <p style={{ color: 'var(--sw-text-muted)' }}>No permissions assigned.</p>
          ) : (
            <div style={{ display: 'grid', gap: 6 }}>
              {[...perms].sort().map((code) => (
                <label key={code} style={{ display: 'flex', alignItems: 'center', gap: 10, cursor: canEdit ? 'pointer' : 'default' }}>
                  <input
                    type="checkbox"
                    checked={perms.has(code)}
                    disabled={!canEdit}
                    onChange={() => toggle(code)}
                  />
                  <code style={{ fontSize: 12 }}>{code}</code>
                </label>
              ))}
            </div>
          )}
          {saved ? <p className="sw-ok" style={{ marginTop: 10 }}>Saved.</p> : null}
        </>
      ) : null}
    </Modal>
  );
}