import { useEffect, useState } from 'react';
import { listUsers, setUserActive, getUserRoles, changeUserRole, listRoles } from '../lib/api/admin';
import { useAsync } from '../lib/useAsync';
import { useAuth } from '../lib/auth/AuthContext';
import { friendlyError } from '../lib/auth/AuthContext';
import { Badge, Button, Card, ConfirmDialog, EmptyState, ErrorState, Field, Input, LoadingState, Modal, PageHeader, Select, StatusChip } from '../components/ui';
import type { AdminUserRow } from '../lib/api/types';
import { pushToast } from '../components/ui';

export function UsersPage() {
  const { hasPerm } = useAuth();
  const [query, setQuery] = useState('');
  const [debounced, setDebounced] = useState('');
  const [status, setStatus] = useState('');
  const [selected, setSelected] = useState<AdminUserRow | null>(null);
  const [busy, setBusy] = useState<string | null>(null);

  const { data, loading, error, reload } = useAsync(
    () => listUsers({ status: status || undefined, query: debounced || undefined }),
    [status, debounced],
  );

  useEffect(() => {
    const t = setTimeout(() => setDebounced(query), 300);
    return () => clearTimeout(t);
  }, [query]);

  const canManageRoles = hasPerm('admin.roles.manage') || hasPerm('admin.permissions.manage');

  async function toggleActive(user: AdminUserRow, activate: boolean) {
    setBusy(user.uid);
    try {
      await setUserActive(user.uid, activate, activate ? 'Reactivated via Admin Panel.' : 'Deactivated via Admin Panel.');
      pushToast('success', activate ? 'Account activated.' : 'Account deactivated.');
      reload();
      setSelected(null);
    } catch (e) {
      pushToast('error', friendlyError(e));
    } finally {
      setBusy(null);
    }
  }

  return (
    <>
      <PageHeader title="Users" subtitle="Search, inspect and manage accounts. Medical data stays protected; only status and roles are shown." />
      <div className="sw-toolbar">
        <Input
          placeholder="Search by email, name or phone…"
          value={query}
          onChange={(e) => setQuery(e.target.value)}
          aria-label="Search users"
          style={{ maxWidth: 320 }}
        />
        <Select value={status} onChange={(e) => setStatus(e.target.value)} aria-label="Filter by status" style={{ maxWidth: 220 }}>
          <option value="">All statuses</option>
          <option value="ACTIVE">ACTIVE</option>
          <option value="PENDING_VERIFICATION">PENDING_VERIFICATION</option>
          <option value="SUSPENDED">SUSPENDED</option>
          <option value="DISABLED">DISABLED</option>
          <option value="DEACTIVATED">DEACTIVATED</option>
        </Select>
        <Button variant="secondary" onClick={reload}>
          Refresh
        </Button>
      </div>

      {loading ? <LoadingState /> : null}
      {error ? <ErrorState message={error} onRetry={reload} /> : null}
      {!loading && !error ? (
        data && data.rows.length > 0 ? (
          <div className="sw-tablewrap" style={{ marginTop: 16 }}>
            <table className="sw-table">
              <thead>
                <tr>
                  <th scope="col">User</th>
                  <th scope="col">Roles</th>
                  <th scope="col">Status</th>
                  <th scope="col">MFA</th>
                  <th scope="col">Actions</th>
                </tr>
              </thead>
              <tbody>
                {data.rows.map((u) => (
                  <tr key={u.uid}>
                    <td>
                      <strong>{u.full_name || u.email}</strong>
                      <br />
                      <span style={{ color: 'var(--sw-text-muted)', fontSize: 12 }}>{u.email}</span>
                    </td>
                    <td>{u.role_codes.length ? u.role_codes.map((r) => <Badge key={r} tone="blue">{r}</Badge>) : <span style={{ color: 'var(--sw-text-muted)' }}>—</span>}</td>
                    <td><StatusChip status={u.account_status} /></td>
                    <td>{u.mfa_enabled ? <Badge tone="green">ON</Badge> : <Badge>OFF</Badge>}</td>
                    <td>
                      <Button variant="secondary" onClick={() => setSelected(u)}>
                        Manage
                      </Button>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        ) : (
          <div style={{ marginTop: 16 }}>
            <EmptyState title="No users found" message="Try a different search or status filter." />
          </div>
        )
      ) : null}

      {selected ? (
        <UserDetailModal
          user={selected}
          canManageRoles={canManageRoles}
          busy={busy}
          onClose={() => setSelected(null)}
          onToggleActive={(activate) => toggleActive(selected, activate)}
          onChanged={reload}
        />
      ) : null}
    </>
  );
}

function UserDetailModal({ user, canManageRoles, busy, onClose, onToggleActive, onChanged }: { user: AdminUserRow; canManageRoles: boolean; busy: string | null; onClose: () => void; onToggleActive: (a: boolean) => void; onChanged: () => void }) {
  const [roles, setRoles] = useState<string[] | null>(null);
  const [allRoles, setAllRoles] = useState<{ code: string; name: string }[]>([]);
  const [grantRole, setGrantRole] = useState('');
  const [reason, setReason] = useState('');
  const [busyRole, setBusyRole] = useState<string | null>(null);
  const [confirmDeactivate, setConfirmDeactivate] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const active = user.account_status === 'ACTIVE' || user.account_status === 'PENDING_VERIFICATION';

  async function refreshRoles() {
    try {
      const [mine, all] = await Promise.all([getUserRoles(user.uid), listRoles()]);
      setRoles(mine);
      setAllRoles(all.map((r) => ({ code: r.code, name: r.name })));
    } catch (e) {
      setError(friendlyError(e));
    }
  }

  function open() {
    void refreshRoles();
  }

  async function toggleRole(code: string, grant: boolean) {
    if (!reason.trim()) {
      setError('A reason is required for role changes.');
      return;
    }
    setBusyRole(code);
    setError(null);
    try {
      await changeUserRole(user.uid, code, grant, reason.trim());
      setReason('');
      onChanged();
      await refreshRoles();
    } catch (e) {
      setError(friendlyError(e));
    } finally {
      setBusyRole(null);
    }
  }

  return (
    <>
      <Modal
        open
        onClose={onClose}
        title={`Manage ${user.full_name || user.email}`}
        footer={
          <>
            <Button variant="ghost" onClick={onClose}>
              Close
            </Button>
          </>
        }
      >
        <div className="sw-tablewrap" style={{ marginBottom: 14 }}>
          <table className="sw-table">
            <tbody>
              <tr><td style={{ width: 160 }}>Email</td><td>{user.email}</td></tr>
              <tr><td>Phone</td><td>{user.phone || '—'}</td></tr>
              <tr><td>Status</td><td><StatusChip status={user.account_status} /></td></tr>
              <tr><td>MFA</td><td>{user.mfa_enabled ? 'Enabled' : 'Not enabled'}</td></tr>
            </tbody>
          </table>
        </div>
        <div style={{ display: 'flex', gap: 12, marginBottom: 10 }}>
          <Button variant={active ? 'danger' : 'primary'} loading={busy === user.uid} onClick={() => (active ? setConfirmDeactivate(true) : onToggleActive(true))}>
            {active ? 'Deactivate account' : 'Activate account'}
          </Button>
        </div>

        {canManageRoles ? (
          <>
            <h3 style={{ fontSize: 15 }}>Roles</h3>
            {error ? (
              <p className="sw-err" role="alert">{error}</p>
            ) : null}
            {roles === null ? (
              <button type="button" onClick={open} className="sw-btn sw-btn-soft">
                Load roles
              </button>
            ) : (
              <Card style={{ padding: 12, marginBottom: 12 }}>
                {roles.length === 0 ? (
                  <p style={{ color: 'var(--sw-text-muted)' }}>No roles assigned.</p>
                ) : (
                  <div style={{ display: 'flex', flexWrap: 'wrap', gap: 8 }}>
                    {roles.map((r) => (
                      <span key={r} style={{ display: 'inline-flex', alignItems: 'center', gap: 6 }}>
                        <Badge tone="blue">{r}</Badge>
                        <button
                          type="button"
                          className="sw-btn sw-btn-ghost"
                          style={{ padding: '4px 8px', fontSize: 12 }}
                          disabled={busyRole === r}
                          onClick={() => toggleRole(r, false)}
                        >
                          Revoke
                        </button>
                      </span>
                    ))}
                  </div>
                )}
              </Card>
            )}
            <Field label="Grant a role" hint="Enter a justification below; changes are audited.">
              <div style={{ display: 'flex', gap: 8 }}>
                <Select value={grantRole} onChange={(e) => setGrantRole(e.target.value)} aria-label="Role to grant">
                  <option value="">Select role…</option>
                  {allRoles
                    .filter((r) => !roles?.includes(r.code))
                    .map((r) => (
                      <option key={r.code} value={r.code}>
                        {r.name} ({r.code})
                      </option>
                    ))}
                </Select>
                <Button variant="soft" disabled={!grantRole} onClick={() => toggleRole(grantRole, true)}>
                  Grant
                </Button>
              </div>
            </Field>
            <Field label="Reason (recorded in audit log)">
              <Input value={reason} onChange={(e) => setReason(e.target.value)} placeholder="Why is this role change needed?" />
            </Field>
          </>
        ) : null}
      </Modal>
      <ConfirmDialog
        open={confirmDeactivate}
        title="Deactivate account?"
        message={`${user.full_name || user.email} will be unable to sign in. This is recorded in the audit log.`}
        confirmLabel="Deactivate"
        destructive
        loading={busy === user.uid}
        onCancel={() => setConfirmDeactivate(false)}
        onConfirm={() => {
          setConfirmDeactivate(false);
          onToggleActive(false);
        }}
      />
    </>
  );
}