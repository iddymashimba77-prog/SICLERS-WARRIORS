import { Link } from 'react-router-dom';
import { useAuth } from '../lib/auth/AuthContext';
import { useAsync } from '../lib/useAsync';
import { fetchDashboard } from '../lib/api/admin';
import { navSectionsFor } from '../lib/nav';
import { KpiCard, Card, PageHeader, LoadingState, ErrorState, cx } from '../components/ui';

type Tone = 'navy' | 'blue' | 'red' | 'green' | 'amber';

interface KpiSpec {
  key: string;
  label: string;
  tone: Tone;
}

const KPI_CARDS: KpiSpec[] = [
  { key: 'users_total', label: 'Total users', tone: 'navy' },
  { key: 'users_active', label: 'Active users', tone: 'blue' },
  { key: 'users_pending_verification', label: 'Users pending verification', tone: 'amber' },
  { key: 'users_patient', label: 'Patients', tone: 'blue' },
  { key: 'users_doctor', label: 'Doctors', tone: 'blue' },
  { key: 'users_caregiver', label: 'Caregivers', tone: 'blue' },
  { key: 'users_blood_donor', label: 'Blood donors', tone: 'blue' },
  { key: 'users_financial_donor', label: 'Financial donors', tone: 'blue' },
  { key: 'users_organization', label: 'Organizations', tone: 'navy' },
  { key: 'users_hospital', label: 'Hospitals', tone: 'navy' },
  { key: 'users_healthcare_staff', label: 'Healthcare staff', tone: 'navy' },
  { key: 'verified_docs', label: 'Verified documents', tone: 'green' },
  { key: 'pending_verifications', label: 'Pending verifications', tone: 'amber' },
  { key: 'blood_requests_pending_verification', label: 'Blood requests pending', tone: 'amber' },
  { key: 'active_blood_requests', label: 'Active blood requests', tone: 'red' },
  { key: 'blood_requests_active', label: 'Blood requests in progress', tone: 'red' },
  { key: 'campaigns_pending_verification', label: 'Campaigns pending', tone: 'amber' },
  { key: 'campaigns_active', label: 'Active campaigns', tone: 'green' },
  { key: 'verification_docs_pending', label: 'Verification docs pending', tone: 'amber' },
  { key: 'active_emergencies', label: 'Active emergencies', tone: 'red' },
  { key: 'emergency_requests_critical', label: 'Critical emergencies', tone: 'red' },
  { key: 'system_alerts_24h', label: 'System alerts (24h)', tone: 'amber' },
  { key: 'pending_moderation', label: 'Pending moderation', tone: 'amber' },
  { key: 'open_reports', label: 'Open reports', tone: 'amber' },
  { key: 'published_content', label: 'Published education', tone: 'green' },
];

const KPI_LABELS: Record<string, string> = Object.fromEntries(
  KPI_CARDS.map((card) => [card.key, card.label]),
);

/** Queues with work sitting in them — surfaced in the bento hero. */
const ATTENTION_KEYS = [
  'active_emergencies',
  'emergency_requests_critical',
  'pending_verifications',
  'verification_docs_pending',
  'users_pending_verification',
  'blood_requests_pending_verification',
  'campaigns_pending_verification',
  'pending_moderation',
  'open_reports',
  'system_alerts_24h',
  'active_blood_requests',
  'blood_requests_active',
];

/** Where each queue's work actually happens (null = no admin surface yet). */
const QUEUE_ROUTES: Record<string, string | null> = {
  pending_verifications: '/admin/verification/doctors',
  verification_docs_pending: '/admin/verification/doctors',
  users_pending_verification: '/admin/verification/doctors',
  blood_requests_pending_verification: '/admin/verification/blood',
  active_blood_requests: '/admin/verification/blood',
  blood_requests_active: '/admin/verification/blood',
  campaigns_pending_verification: '/admin/verification/campaigns',
  pending_moderation: '/admin/community',
  open_reports: '/admin/community',
  system_alerts_24h: '/admin/security-events',
  active_emergencies: null,
  emergency_requests_critical: null,
};

const PLATFORM_KEYS = [
  'users_total',
  'users_active',
  'users_patient',
  'users_doctor',
  'users_caregiver',
  'users_blood_donor',
  'users_financial_donor',
  'users_organization',
  'users_hospital',
  'users_healthcare_staff',
];

const PROGRAM_KEYS = ['campaigns_active', 'verified_docs', 'published_content'];

/** Sections the control centre offers as one-click work queues. */
const QUICK_SEGMENTS = [
  'verification/doctors',
  'verification/organizations',
  'verification/blood',
  'verification/campaigns',
  'community',
  'security-events',
];

export function DashboardPage() {
  const { user, isSuper } = useAuth();
  const { data, loading, error, reload } = useAsync(() => fetchDashboard(), []);

  if (loading) return <LoadingState label="Loading dashboard…" />;
  if (error) return <ErrorState message={error} onRetry={reload} />;
  if (!data) return <ErrorState message="No dashboard data returned." onRetry={reload} />;

  const kpis = data.kpis ?? {};
  const sources = data.kpi_sources ?? {};
  // Explicit order so the board does not reshuffle when a KPI is added, then
  // any unexpected key the backend introduces is appended rather than hidden.
  const ordered = KPI_CARDS.filter((card) => kpis[card.key] !== undefined);
  const extras = Object.keys(kpis)
    .filter((key) => !KPI_LABELS[key])
    .map((key) => ({ key, label: key.replace(/_/g, ' '), tone: 'navy' as Tone }));
  const kernels = [...ordered, ...extras];
  const stale = kernels.filter((card) => sources[card.key] === 'snapshot');
  const trends = data.trends ?? {};

  const byKey = (key: string) => kernels.find((card) => card.key === key);
  const attention = ATTENTION_KEYS.map(byKey).filter((c): c is KpiSpec => !!c);
  const platform = PLATFORM_KEYS.map(byKey).filter((c): c is KpiSpec => !!c);
  const programs = PROGRAM_KEYS.map(byKey).filter((c): c is KpiSpec => !!c);
  const grouped = new Set([...ATTENTION_KEYS, ...PLATFORM_KEYS, ...PROGRAM_KEYS]);
  const others = kernels.filter((card) => !grouped.has(card.key));

  const count = (key: string) => (typeof kpis[key] === 'number' ? kpis[key] : 0);
  const attentionTotal = attention.reduce((sum, card) => sum + count(card.key), 0);
  const openQueues = attention.filter((card) => count(card.key) > 0);
  const quickActions = (user ? navSectionsFor(user, isSuper) : [])
    .flatMap((section) => section.links)
    .filter((link) => QUICK_SEGMENTS.includes(link.segment))
    .slice(0, 4);

  const renderValue = (key: string) =>
    typeof kpis[key] === 'number' ? kpis[key].toLocaleString() : kpis[key];

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
      {stale.length > 0 ? (
        <p style={{ color: 'var(--sw-text-muted)', fontSize: 12 }}>
          Last aggregation run: {stale.map((card) => card.label).join(', ')}.
        </p>
      ) : null}

      <h2 className="sw-section-title">Needs attention</h2>
      <div className="sw-bento">
        <Card className="sw-bento__hero">
          <span className="sw-kpi-label">Outstanding now</span>
          <div className={cx('sw-kpi-value', attentionTotal > 0 ? 'is-amber' : 'is-green')}>
            {attentionTotal.toLocaleString()}
          </div>
          {openQueues.length === 0 ? (
            <p className="sw-allclear">
              <span aria-hidden="true">✓</span> Nothing is waiting for review right now.
            </p>
          ) : (
            <ul className="sw-queue-list">
              {openQueues.slice(0, 6).map((card) => {
                const route = QUEUE_ROUTES[card.key];
                const body = (
                  <>
                    <span>{card.label}</span>
                    <span className="sw-queue-count">{renderValue(card.key)}</span>
                  </>
                );
                return (
                  <li key={card.key}>
                    {route ? <Link to={route}>{body}</Link> : <span className="sw-queue-static">{body}</span>}
                  </li>
                );
              })}
            </ul>
          )}
          {quickActions.length > 0 ? (
            <div className="sw-quick-actions">
              {quickActions.map((link) => (
                <Link key={link.segment} className="sw-quick-action" to={`/admin/${link.segment}`}>
                  {link.label}
                </Link>
              ))}
            </div>
          ) : null}
        </Card>
        {attention.map((card) => (
          <KpiCard
            key={card.key}
            label={card.label}
            value={renderValue(card.key)}
            tone={card.tone}
            className={card.key === 'pending_verifications' ? 'sw-bento__wide' : undefined}
          />
        ))}
      </div>

      {platform.length > 0 ? (
        <>
          <h2 className="sw-section-title">Platform</h2>
          <div className="sw-bento">
            {platform.map((card) => (
              <KpiCard
                key={card.key}
                label={card.label}
                value={renderValue(card.key)}
                tone={card.tone}
                className={card.key === 'users_total' ? 'sw-bento__wide' : undefined}
              />
            ))}
          </div>
        </>
      ) : null}

      {programs.length > 0 ? (
        <>
          <h2 className="sw-section-title">Programs &amp; trust</h2>
          <div className="sw-bento">
            {programs.map((card) => (
              <KpiCard key={card.key} label={card.label} value={renderValue(card.key)} tone={card.tone} />
            ))}
          </div>
        </>
      ) : null}

      {others.length > 0 ? (
        <>
          <h2 className="sw-section-title">Other metrics</h2>
          <div className="sw-bento">
            {others.map((card) => (
              <KpiCard key={card.key} label={card.label} value={renderValue(card.key)} tone={card.tone} />
            ))}
          </div>
        </>
      ) : null}

      {Object.keys(trends).length > 0 ? (
        <div className="sw-grid sw-grid-2" style={{ marginTop: 24 }}>
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
