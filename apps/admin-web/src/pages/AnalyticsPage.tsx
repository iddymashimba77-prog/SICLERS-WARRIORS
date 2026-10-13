import { useState } from 'react';
import { exportAnalyticsCsv, fetchAnalytics } from '../lib/api/admin';
import { useAsync } from '../lib/useAsync';
import { friendlyError, useAuth } from '../lib/auth/AuthContext';
import { Button, Card, ErrorState, Field, Input, LoadingState, Modal, PageHeader, Select } from '../components/ui';
import { pushToast } from '../components/ui';

/**
 * Mirrors `analytics.services.allowed_metrics()` exactly:
 *   SUPER_ADMIN/ADMIN -> ADMIN-scope metrics, VERIFICATION_OFFICER -> the
 *   verification set, everybody else -> nothing. Offering a metric the backend
 *   will refuse (403 + `analytics.access_denied` audit row) is a broken control.
 */
const ADMIN_METRICS = [
  { value: 'users.total', label: 'Total users' },
  { value: 'users.active', label: 'Active users' },
  { value: 'users.active_patients', label: 'Active patients' },
  { value: 'users.new', label: 'New user registrations' },
  { value: 'donations.confirmed_amount', label: 'Confirmed donation amount' },
  { value: 'donations.by_status', label: 'Donations by status' },
  { value: 'blood_donations.by_outcome', label: 'Blood donations by outcome' },
  { value: 'blood_matches.by_status', label: 'Blood matches by status' },
  { value: 'emergency_requests.by_status', label: 'Emergency requests by status' },
  { value: 'emergency_requests.by_severity', label: 'Emergency requests by severity' },
  { value: 'community_posts.by_status', label: 'Community posts by status' },
  { value: 'community_posts.by_category', label: 'Community posts by category' },
  { value: 'comments.by_status', label: 'Comments by status' },
  { value: 'reports.by_status', label: 'Reports by status' },
  { value: 'education.by_status', label: 'Education content by status' },
  { value: 'education.by_category', label: 'Education content by category' },
  { value: 'symptoms.by_type', label: 'Symptoms by type (de-identified)' },
  { value: 'symptoms.avg_pain', label: 'Average pain level (de-identified)' },
  { value: 'medication_events.by_status', label: 'Medication events by status' },
  { value: 'security_events.non_success', label: 'Non-success security events' },
];

const VERIFICATION_METRICS = [
  { value: 'verification_docs.by_status', label: 'Verification documents by status' },
  { value: 'blood_requests.by_status', label: 'Blood requests by status' },
  { value: 'blood_requests.by_urgency', label: 'Blood requests by urgency' },
  { value: 'campaigns.by_status', label: 'Campaigns by status' },
];

const GRANULARITY = ['DAILY', 'WEEKLY', 'MONTHLY'];

// The approved brand family — a red->navy gradient for the main series and a
// fixed chromatic scale for breakdowns so a donut stays recognisable across
// every metric.
const CHART_COLORS = ['#C81E3A', '#0B1F3D', '#1B5FAE', '#16803C', '#B7791F', '#9F1530', '#4B8BD9', '#667085'];
const AREA_FROM = '#C81E3A';
const AREA_TO = '#0B1F3D';

function metricsForRole(roleCodes: string[]) {
  if (roleCodes.includes('SUPER_ADMIN') || roleCodes.includes('ADMIN')) return ADMIN_METRICS;
  if (roleCodes.includes('VERIFICATION_OFFICER')) return VERIFICATION_METRICS;
  return [];
}

interface Point { date: string; value: number }

function niceCeil(n: number): number {
  if (n <= 0) return 1;
  const mag = Math.pow(10, Math.floor(Math.log10(n)));
  const norm = n / mag;
  const step = norm <= 1 ? 1 : norm <= 2 ? 2 : norm <= 2.5 ? 2.5 : norm <= 5 ? 5 : 10;
  return step * mag;
}

function fmt(n: number): string {
  if (n >= 1000000) return `${(n / 1000000).toFixed(1)}M`;
  if (n >= 1000) return `${(n / 1000).toFixed(1)}k`;
  return `${Math.round(n)}`;
}

function deltaLabel(prev: number | null, latest: number): string | null {
  if (prev === null || latest === prev) return null;
  const diff = latest - prev;
  const pct = prev === 0 ? 100 : Math.abs((diff / prev) * 100);
  return `${diff > 0 ? '▲' : '▼'} ${fmt(Math.abs(diff))} (${pct.toFixed(0)}%) vs previous`;
}

export function AnalyticsPage() {
  const { user } = useAuth();
  const roleCodes = user?.role_codes ?? [];
  const metrics = metricsForRole(roleCodes);

  const [metric, setMetric] = useState(metrics[0]?.value ?? '');
  const [granularity, setGranularity] = useState('DAILY');
  const [dateFrom, setDateFrom] = useState('');
  const [dateTo, setDateTo] = useState('');
  const { data, loading, error, reload } = useAsync(
    () => fetchAnalytics({
      metric,
      granularity,
      date_from: dateFrom || undefined,
      date_to: dateTo || undefined,
    }),
    [metric, granularity, dateFrom, dateTo],
  );

  const [showExport, setShowExport] = useState(false);
  const [exporting, setExporting] = useState(false);
  const [exportErr, setExportErr] = useState<string | null>(null);
  const [reason, setReason] = useState('');

  const points: Point[] = (data?.results ?? []).map((r) => ({
    date: r.period ?? (r.measured_at ?? '').replace('T', ' ').slice(0, 10),
    value: r.value ?? 0,
  }));

  const latestRow = data?.results?.[data.results.length - 1];
  const dimensions = (latestRow?.dimensions ?? null) as Record<string, number> | null;

  async function doExport() {
    if (reason.trim().length < 5 && !roleCodes.includes('SUPER_ADMIN')) {
      setExportErr('A reason of at least 5 characters is required to export as a non-super admin (C4).');
      return;
    }
    setExporting(true);
    setExportErr(null);
    try {
      const csv = await exportAnalyticsCsv(
        { metric, granularity, date_from: dateFrom || undefined, date_to: dateTo || undefined },
        reason.trim(),
      );
      const blob = new Blob([csv], { type: 'text/csv;charset=utf-8' });
      const url = URL.createObjectURL(blob);
      const a = document.createElement('a');
      a.href = url;
      a.download = `${metric.replace(/[^a-z0-9.]/gi, '_')}.csv`;
      document.body.appendChild(a);
      a.click();
      a.remove();
      URL.revokeObjectURL(url);
      pushToast('success', 'CSV exported and recorded in the audit trail.');
      setShowExport(false);
      setReason('');
    } catch (e) {
      setExportErr(friendlyError(e));
    } finally {
      setExporting(false);
    }
  }

  if (metrics.length === 0) {
    return (
      <>
        <PageHeader title="Analytics" subtitle="Explore platform trends with the backend analytics engine." />
        <Card style={{ padding: 16 }}>
          <ErrorState
            title="No metrics for this account"
            message="Your roles are not in the analytics scope (C6). SUPER_ADMIN/ADMIN see the full registry; VERIFICATION_OFFICER sees the verification set."
          />
        </Card>
      </>
    );
  }

  const total = points.reduce((sum, p) => sum + p.value, 0);
  const average = points.length ? total / points.length : 0;
  const maxValue = points.length ? Math.max(...points.map((p) => p.value), 0) : 0;
  const latest = points[points.length - 1]?.value ?? 0;
  const previous = points.length > 1 ? points[points.length - 2].value : null;

  return (
    <>
      <PageHeader title="Analytics" subtitle="Explore platform trends with the backend analytics engine." />
      <div className="sw-toolbar">
        <Select value={metric} onChange={(e) => setMetric(e.target.value)} aria-label="Metric" style={{ maxWidth: 300 }}>
          {metrics.map((m) => (
            <option key={m.value} value={m.value}>{m.label}</option>
          ))}
        </Select>
        <Select value={granularity} onChange={(e) => setGranularity(e.target.value)} aria-label="Granularity" style={{ maxWidth: 150 }}>
          {GRANULARITY.map((g) => (
            <option key={g} value={g}>{g}</option>
          ))}
        </Select>
        <Input type="date" value={dateFrom} onChange={(e) => setDateFrom(e.target.value)} aria-label="From date" style={{ maxWidth: 170 }} />
        <Input type="date" value={dateTo} onChange={(e) => setDateTo(e.target.value)} aria-label="To date" style={{ maxWidth: 170 }} />
        <Button variant="secondary" onClick={reload}>Refresh</Button>
        <Button variant="secondary" onClick={() => { setExportErr(null); setReason(''); setShowExport(true); }}>
          Export CSV
        </Button>
      </div>
      {loading ? <LoadingState /> : null}
      {error ? <ErrorState message={error} onRetry={reload} /> : null}
      {!loading && !error ? (
        <>
          {points.length === 0 ? (
            <Card style={{ padding: 16 }}>
              <p style={{ color: 'var(--sw-text-muted)' }}>
                No data for this metric and window yet. Widen the dates or pick another granularity.
              </p>
            </Card>
          ) : (
            <>
              <div className="sw-chart-kpis">
                <div className="sw-chart-kpi">
                  <span className="sw-chart-kpi-label">Latest</span>
                  <strong>{fmt(latest)}</strong>
                  {deltaLabel(previous, latest) ? <em className="sw-chart-kpi-delta">{deltaLabel(previous, latest)}</em> : null}
                </div>
                <div className="sw-chart-kpi">
                  <span className="sw-chart-kpi-label">Average</span>
                  <strong>{fmt(average)}</strong>
                </div>
                <div className="sw-chart-kpi">
                  <span className="sw-chart-kpi-label">Peak</span>
                  <strong>{fmt(maxValue)}</strong>
                </div>
                <div className="sw-chart-kpi">
                  <span className="sw-chart-kpi-label">Points</span>
                  <strong>{points.length}</strong>
                </div>
              </div>
              <div className="sw-chart-grid">
                <Card style={{ padding: 20 }}>
                  <h3 className="sw-chart-title">{metrics.find((m) => m.value === metric)?.label} — trend</h3>
                  <AreaChart points={points} />
                </Card>
                {dimensions && Object.keys(dimensions).length > 1 ? (
                  <Card style={{ padding: 20 }}>
                    <h3 className="sw-chart-title">Latest breakdown</h3>
                    <DonutChart entries={Object.entries(dimensions).map(([label, value]) => ({ label, value }))} />
                  </Card>
                ) : null}
              </div>
            </>
          )}
        </>
      ) : null}

      {showExport ? (
        <Modal
          open
          onClose={() => setShowExport(false)}
          title="Export analytics (CSV)"
          footer={
            <>
              <Button variant="ghost" onClick={() => setShowExport(false)} disabled={exporting}>Cancel</Button>
              <Button loading={exporting} onClick={doExport}>Export</Button>
            </>
          }
        >
          {exportErr ? <p className="sw-err" role="alert" style={{ marginBottom: 12 }}>{exportErr}</p> : null}
          <p style={{ fontSize: 13, color: 'var(--sw-text-2)', marginBottom: 10 }}>
            Exports <strong>{metrics.find((m) => m.value === metric)?.label}</strong> at {granularity} granularity
            {dateFrom || dateTo ? ` for ${dateFrom || 'start'} → ${dateTo || 'today'}` : ''}.
            The export is appended to the audit trail.
          </p>
          <Field label="Reason" hint="Required for non-super admins (C4); recorded with the export.">
            <Input value={reason} onChange={(e) => setReason(e.target.value)} placeholder="e.g. monthly board report" />
          </Field>
        </Modal>
      ) : null}
    </>
  );
}

/** Dependency-free SVG area chart with gridlines, gradient fill and hover tooltips. */
function AreaChart({ points }: { points: Point[] }) {
  const [hover, setHover] = useState<number | null>(null);

  const W = 560;
  const H = 240;
  const PAD_L = 40;
  const PAD_R = 12;
  const PAD_T = 16;
  const PAD_B = 26;

  const values = points.map((p) => p.value);
  const max = niceCeil(Math.max(...values, 1));
  const innerW = W - PAD_L - PAD_R;
  const innerH = H - PAD_T - PAD_B;

  const x = (i: number) => PAD_L + (points.length === 1 ? innerW / 2 : (i / (points.length - 1)) * innerW);
  const y = (v: number) => PAD_T + innerH - (v / max) * innerH;

  const line = points.map((p, i) => `${i === 0 ? 'M' : 'L'}${x(i).toFixed(1)},${y(p.value).toFixed(1)}`).join(' ');
  const area = `${line} L${x(points.length - 1).toFixed(1)},${(PAD_T + innerH).toFixed(1)} L${x(0).toFixed(1)},${(PAD_T + innerH).toFixed(1)} Z`;

  const gridSteps = [0, 0.25, 0.5, 0.75, 1];
  // Never crowd the x axis: at most 6 readable ticks.
  const tickEvery = Math.ceil(points.length / 6);
  const xTicks = points.map((p, i) => ({ i, p })).filter((t) => t.i % tickEvery === 0 || t.i === points.length - 1);

  const active = hover !== null ? points[hover] : null;

  return (
    <svg viewBox={`0 0 ${W} ${H}`} role="img" aria-label="Analytics trend chart"
      className="sw-area-chart"
      onMouseLeave={() => setHover(null)}>
      <defs>
        <linearGradient id="sw-area-fill" x1="0" y1="0" x2="0" y2="1">
          <stop offset="0%" stopColor={AREA_FROM} stopOpacity="0.32" />
          <stop offset="100%" stopColor={AREA_TO} stopOpacity="0.03" />
        </linearGradient>
      </defs>

      {gridSteps.map((g) => {
        const gy = PAD_T + innerH - g * innerH;
        const label = fmt(max * g);
        return (
          <g key={g}>
            <line x1={PAD_L} y1={gy} x2={W - PAD_R} y2={gy} stroke="var(--sw-border, #e4e7ec)" strokeWidth="1" strokeDasharray="4 4" />
            <text x={PAD_L - 8} y={gy + 4} textAnchor="end" fontSize="10" fill="var(--sw-text-muted, #98a2b3)">{label}</text>
          </g>
        );
      })}

      {xTicks.map(({ i, p }) => (
        <text key={i} x={x(i)} y={H - 8} textAnchor="middle" fontSize="10" fill="var(--sw-text-muted, #98a2b3)">{p.date}</text>
      ))}

      <path d={area} fill="url(#sw-area-fill)" />
      <path d={line} fill="none" stroke={AREA_FROM} strokeWidth="2.5" strokeLinejoin="round" strokeLinecap="round" />

      {points.map((p, i) => (
        <g key={i} onMouseEnter={() => setHover(i)} style={{ cursor: 'pointer' }}>
          <title>{`${p.date}: ${p.value}`}</title>
          <circle cx={x(i)} cy={y(p.value)} r={hover === i ? 6 : 4} fill="var(--sw-surface, #ffffff)" stroke={AREA_FROM} strokeWidth="2.5" />
        </g>
      ))}

      {active ? (
        <g transform={`translate(${Math.min(x(hover!), W - 110)}, ${Math.max(y(active.value) - 46, 4)})`}>
          <rect width="104" height="36" rx="8" fill="#0B1F3D" />
          <text x="8" y="15" fontSize="10" fill="#FDECEF">{active.date}</text>
          <text x="8" y="29" fontSize="12" fontWeight="700" fill="#FFFFFF">{fmt(active.value)}</text>
        </g>
      ) : null}
    </svg>
  );
}

function DonutChart({ entries }: { entries: { label: string; value: number }[] }) {
  const total = entries.reduce((sum, e) => sum + (e.value || 0), 0);
  if (total <= 0) return <p style={{ color: 'var(--sw-text-muted)' }}>No breakdown values to plot.</p>;

  const size = 180;
  const stroke = 26;
  const r = (size - stroke) / 2;
  const c = 2 * Math.PI * r;
  let acc = 0;

  return (
    <div style={{ display: 'flex', gap: 24, alignItems: 'center', flexWrap: 'wrap' }}>
      <svg width={size} height={size} viewBox={`0 0 ${size} ${size}`} role="img" aria-label="Breakdown donut chart">
        <g transform={`rotate(-90 ${size / 2} ${size / 2})`}>
          {entries.map((e, i) => {
            const frac = e.value / total;
            const dash = frac * c;
            const offset = -acc * c;
            acc += frac;
            return (
              <circle
                key={i}
                cx={size / 2}
                cy={size / 2}
                r={r}
                fill="none"
                stroke={CHART_COLORS[i % CHART_COLORS.length]}
                strokeWidth={stroke}
                strokeDasharray={`${dash} ${c - dash}`}
                strokeDashoffset={offset}
              >
                <title>{`${e.label}: ${fmt(e.value)} (${(frac * 100).toFixed(0)}%)`}</title>
              </circle>
            );
          })}
        </g>
        <text x={size / 2} y={size / 2 - 4} textAnchor="middle" fontSize="20" fontWeight="700" fill="var(--sw-text, #172033)">{fmt(total)}</text>
        <text x={size / 2} y={size / 2 + 16} textAnchor="middle" fontSize="10" fill="var(--sw-text-muted, #98a2b3)">total</text>
      </svg>
      <ul className="sw-donut-legend">
        {entries.map((e, i) => (
          <li key={i}>
            <span className="sw-donut-swatch" style={{ background: CHART_COLORS[i % CHART_COLORS.length] }} />
            <span className="sw-donut-label">{e.label || '—'}</span>
            <strong>{fmt(e.value)}</strong>
            <em>{((e.value / total) * 100).toFixed(0)}%</em>
          </li>
        ))}
      </ul>
    </div>
  );
}