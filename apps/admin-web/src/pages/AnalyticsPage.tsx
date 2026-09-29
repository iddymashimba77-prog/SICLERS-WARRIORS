import { useState } from 'react';
import { fetchAnalytics } from '../lib/api/admin';
import { useAsync } from '../lib/useAsync';
import { Badge, Button, Card, ErrorState, LoadingState, PageHeader, Select } from '../components/ui';

const METRICS = [
  { value: 'users.total', label: 'Total users' },
  { value: 'users.active', label: 'Active users' },
  { value: 'users.active_patients', label: 'Active patients' },
  { value: 'users.new', label: 'New user registrations' },
  { value: 'donations.confirmed_amount', label: 'Confirmed donation amount' },
  { value: 'donations.by_status', label: 'Donations by status' },
  { value: 'campaigns.by_status', label: 'Campaigns by status' },
  { value: 'blood_requests.by_status', label: 'Blood requests by status' },
  { value: 'community_posts.by_status', label: 'Community posts by status' },
  { value: 'reports.by_status', label: 'Reports by status' },
  { value: 'education.by_status', label: 'Education content by status' },
];

const GRANULARITY = ['DAILY', 'WEEKLY', 'MONTHLY'];

export function AnalyticsPage() {
  const [metric, setMetric] = useState(METRICS[0].value);
  const [granularity, setGranularity] = useState('DAILY');
  const { data, loading, error, reload } = useAsync(() => fetchAnalytics({ metric, granularity }), [metric, granularity]);

  const points = (data?.results ?? []).map((r) => ({
    date: r.period ?? (r.measured_at ?? '').replace('T', ' ').slice(0, 10),
    value: r.value ?? 0,
  }));

  return (
    <>
      <PageHeader title="Analytics" subtitle="Explore platform trends with the backend analytics engine." />
      <div className="sw-toolbar">
        <Select value={metric} onChange={(e) => setMetric(e.target.value)} aria-label="Metric" style={{ maxWidth: 260 }}>
          {METRICS.map((m) => (
            <option key={m.value} value={m.value}>{m.label}</option>
          ))}
        </Select>
        <Select value={granularity} onChange={(e) => setGranularity(e.target.value)} aria-label="Granularity" style={{ maxWidth: 160 }}>
          {GRANULARITY.map((g) => (
            <option key={g} value={g}>{g}</option>
          ))}
        </Select>
        <Button variant="secondary" onClick={reload}>Refresh</Button>
      </div>
      {loading ? <LoadingState /> : null}
      {error ? <ErrorState message={error} onRetry={reload} /> : null}
      {!loading && !error ? (
        <Card style={{ padding: 16 }}>
          {points.length === 0 ? (
            <p style={{ color: 'var(--sw-text-muted)' }}>No analytics returned for this metric. It may not exist in this environment.</p>
          ) : (
            <>
              <div style={{ display: 'flex', gap: 8, flexWrap: 'wrap', marginBottom: 16 }}>
                {points.slice(-7).reverse().map((p, i) => (
                  <Badge key={i} tone="blue">
                    {p.date ?? ''}: {p.value ?? 0}
                  </Badge>
                ))}
              </div>
              <AnalyticsBars points={points} />
            </>
          )}
        </Card>
      ) : null}
    </>
  );
}

function AnalyticsBars({ points }: { points: { date?: string; value?: number }[] }) {
  const values = points.map((p) => p.value ?? 0);
  const max = Math.max(...values, 1);
  return (
    <div style={{ display: 'flex', alignItems: 'flex-end', gap: 4, height: 220 }}>
      {points.map((p, i) => {
        const h = Math.max(4, Math.round(((p.value ?? 0) / max) * 200));
        return (
          <div key={i} style={{ flex: 1, display: 'flex', flexDirection: 'column', justifyContent: 'flex-end', alignItems: 'center', gap: 4 }}>
            <div
              title={`${p.date ?? ''}: ${p.value ?? 0}`}
              style={{
                width: '100%',
                height: `${h}px`,
                background: 'linear-gradient(180deg, var(--sw-red-strong, #C81E3A), var(--sw-navy, #0B1F3D))',
                borderRadius: '4px 4px 0 0',
                minWidth: 4,
              }}
            />
            <span style={{ fontSize: 10, color: 'var(--sw-text-muted)', writingMode: 'horizontal-tb' }}>{p.date ?? ''}</span>
          </div>
        );
      })}
    </div>
  );
}