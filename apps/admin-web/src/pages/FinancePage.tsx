import { useAsync } from '../lib/useAsync';
import { fetchFinancialSummary } from '../lib/api/admin';
import { ErrorState, KpiCard, LoadingState, PageHeader } from '../components/ui';

export function FinancePage() {
  const { data, loading, error, reload } = useAsync(() => fetchFinancialSummary(), []);

  if (loading) return <LoadingState label="Loading financial summary…" />;
  if (error) return <ErrorState message={error} onRetry={reload} />;
  if (!data) return <ErrorState message="No financial summary returned." onRetry={reload} />;

  const fmt = (n: number | undefined) => (n === undefined ? '—' : n.toLocaleString());
  const money = (n: number | undefined) => (n === undefined ? '—' : n.toLocaleString());

  return (
    <>
      <PageHeader title="Financial summary" subtitle="Confirmed, pending and refunded donations across the platform." />
      {data.last_updated ? (
        <p style={{ color: 'var(--sw-text-muted)', fontSize: 12, marginTop: -12 }}>
          Updated {new Date(data.last_updated.replace('Z', '+00:00')).toLocaleString()}
        </p>
      ) : null}
      <div className="sw-grid sw-grid-kpis">
        <KpiCard label="Confirmed amount" value={money(data.confirmed_donations_total)} tone="green" />
        <KpiCard label="Confirmed donations" value={fmt(data.confirmed_donations_count)} tone="green" />
        <KpiCard label="Pending donations" value={fmt(data.pending_donations_count)} tone="amber" />
        <KpiCard label="Refunded total" value={money(data.refunded_total)} tone="red" />
        <KpiCard label="Active campaigns" value={fmt(data.active_campaigns_count)} tone="blue" />
        <KpiCard label="Closed campaigns" value={fmt(data.closed_campaigns_count)} tone="navy" />
      </div>
    </>
  );
}