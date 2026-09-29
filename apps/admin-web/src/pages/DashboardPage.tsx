import { useAuth } from '../lib/auth/AuthContext';
import { useAsync } from '../lib/useAsync';
import { fetchDashboard } from '../lib/api/admin';
import { KpiCard, Card, PageHeader, LoadingState, ErrorState } from '../components/ui';

const KPI_LABELS: Record<string, string> = {
  users_total: 'Total users',
  users_active: 'Active users',
  users_active_patients: 'Active patients',
  verified_doctors: 'Verified doctors',
  verified_docs: 'Verified documents',
  active_blood_requests: 'Active blood requests',
  blood_requests_pending_verification: 'Blood requests pending',
  blood_requests_active: 'Active blood requests',
  campaigns_pending_verification: 'Campaigns pending',
  campaigns_active: 'Active campaigns',
  verification_docs_pending: 'Verification docs pending',
  active_emergencies: 'Active emergencies',
  system_alerts_24h: 'System alerts (24h)',
  pending_moderation: 'Pending moderation',
  pending_verifications: 'Pending verifications',
};

const KPI_TONE: Record<string, 'navy' | 'blue' | 'red' | 'green' | 'amber'> = {
  active_emergencies: 'red',
  system_alerts_24h: 'amber',
  pending_moderation: 'amber',
  pending_verifications: 'amber',
  verified_docs: 'green',
  users_active: 'blue',
  users_total: 'navy',
};

export function DashboardPage() {
  const { user, isSuper } = useAuth();
  const { data, loading, error, reload } = useAsync(() => fetchDashboard(), []);

  if (loading) return <LoadingState label="Loading dashboard…" />;
  if (error) return <ErrorState message={error} onRetry={reload} />;
  if (!data) return <ErrorState message="No dashboard data returned." onRetry={reload} />;

  const kpis = data.kpis ?? {};
  const kernels = Object.entries(kpis).filter(([key]) => KPI_LABELS[key]);
  const trends = data.trends ?? {};

  return (
    <>
      <PageHeader
        title="Dashboard"
        subtitle={
          isSuper
            ? 'Platform-wide overview from live backend data.'
            : `Live overview for ${user?.role_codes?.join(', ') ?? 'your account'}.`
        }
      />
      {data.generated_at ? (
        <p style={{ color: 'var(--sw-text-muted)', fontSize: 12, marginTop: -12 }}>
          Generated {new Date(data.generated_at).toLocaleString()}
        </p>
      ) : null}
      <div className="sw-grid sw-grid-kpis" style={{ marginBottom: 16 }}>
        {kernels.map(([key, value]) => (
          <KpiCard
            key={key}
            label={KPI_LABELS[key]}
            value={typeof value === 'number' ? value.toLocaleString() : value}
            tone={KPI_TONE[key]}
          />
        ))}
      </div>
      {Object.keys(trends).length > 0 ? (
        <div className="sw-grid sw-grid-2">
          {Object.entries(trends).map(([metric, points]) => (
            <Card key={metric} style={{ padding: 16 }}>
              <h3 style={{ textTransform: 'capitalize' }}>{metric.replace(/\./g, ' · ')}</h3>
              <TrendBars points={points ?? []} />
            </Card>
          ))}
        </div>
      ) : null}
    </>
  );
}

function TrendBars({ points }: { points: Array<{ measured_at?: string; date?: string; value?: number }> }) {
  if (!points.length) {
    return <p style={{ color: 'var(--sw-text-muted)' }}>No trend data yet.</p>;
  }
  const values = points.map((p) => p.value ?? 0);
  const max = Math.max(...values, 1);
  return (
    <div style={{ display: 'flex', alignItems: 'flex-end', gap: 4, height: 120 }}>
      {points.map((p, i) => {
        const h = Math.max(4, Math.round(((p.value ?? 0) / max) * 100));
        const label = p.date ?? (p.measured_at ?? '').slice(0, 10);
        return (
          <div key={i} style={{ flex: 1, display: 'flex', flexDirection: 'column', justifyContent: 'flex-end' }}>
            <div
              title={`${label}: ${p.value ?? 0}`}
              style={{
                height: `${h}px`,
                background: 'var(--sw-blue)',
                borderRadius: '4px 4px 0 0',
                minWidth: 4,
              }}
            />
          </div>
        );
      })}
    </div>
  );
}