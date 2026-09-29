import { useAuth } from '../lib/auth/AuthContext';
import { useTheme, type ThemeMode } from '../lib/theme';
import { Card, PageHeader } from '../components/ui';

const APPEARANCE_OPTIONS: { value: ThemeMode; label: string }[] = [
  { value: 'light', label: 'Light' },
  { value: 'dark', label: 'Dark' },
  { value: 'system', label: 'System' },
];

export function SettingsPage() {
  const { user, isSuper } = useAuth();
  const { mode, setMode, resolved } = useTheme();

  return (
    <>
      <PageHeader title="Settings" subtitle="Platform configuration surfaces that the backend exposes." />
      <div className="sw-grid sw-grid-2">
        <Card style={{ padding: 16 }}>
          <h3 style={{ marginBottom: 6 }}>Appearance</h3>
          <p style={{ fontSize: 13, color: 'var(--sw-text-2)', marginBottom: 12 }}>
            Global admin panel theme. Stored on this device only.
          </p>
          <div style={{ display: 'flex', gap: 8 }}>
            {APPEARANCE_OPTIONS.map((opt) => {
              const active = mode === opt.value;
              return (
                <button
                  key={opt.value}
                  type="button"
                  className="sw-segchip"
                  aria-pressed={active}
                  onClick={() => setMode(opt.value)}
                >
                  {opt.label}
                </button>
              );
            })}
          </div>
          {mode === 'system' ? (
            <p style={{ fontSize: 12, color: 'var(--sw-text-muted)', marginTop: 8 }}>
              Following your device — currently showing {resolved} mode.
            </p>
          ) : null}
        </Card>
        <Card style={{ padding: 16 }}>
          <h3 style={{ marginBottom: 6 }}>Session</h3>
          <p style={{ fontSize: 13, color: 'var(--sw-text-2)' }}>
            Signed in as <strong>{user?.email ?? '—'}</strong>.
            <br />
            Session is carried in your browser for this device only.
          </p>
        </Card>
        <Card style={{ padding: 16 }}>
          <h3 style={{ marginBottom: 6 }}>Access</h3>
          <p style={{ fontSize: 13, color: 'var(--sw-text-2)' }}>
            Roles: {user?.role_codes?.join(', ') || '—'}
            {isSuper ? ' (super admin)' : ''}
          </p>
        </Card>
        <Card style={{ padding: 16 }}>
          <h3 style={{ marginBottom: 6 }}>Feature flags</h3>
          <p style={{ fontSize: 13, color: 'var(--sw-text-2)' }}>
            The public app settings are managed on the backend. Feature flags are not exposed as an admin surface.
          </p>
        </Card>
        <Card style={{ padding: 16 }}>
          <h3 style={{ marginBottom: 6 }}>Admin accounts</h3>
          <p style={{ fontSize: 13, color: 'var(--sw-text-2)' }}>
            Admin staff are managed through Users (grant a role) and Roles. There is no separate account table on the backend.
          </p>
        </Card>
      </div>
    </>
  );
}