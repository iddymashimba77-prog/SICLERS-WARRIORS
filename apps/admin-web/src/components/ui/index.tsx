import { useEffect, useRef, useState, type ButtonHTMLAttributes, type ReactNode, type SelectHTMLAttributes, type InputHTMLAttributes, type TextareaHTMLAttributes } from 'react';

const cx = (...parts: Array<string | false | null | undefined>) => parts.filter(Boolean).join(' ');

/* --------------------------------------------------------------- Spinner */

export function Spinner({ size = 20, label }: { size?: number; label?: string }) {
  return (
    <svg
      className="sw-spin"
      width={size}
      height={size}
      viewBox="0 0 24 24"
      fill="none"
      role="status"
      aria-label={label ?? 'Loading'}
    >
      <circle cx="12" cy="12" r="10" stroke="currentColor" strokeWidth="3" opacity="0.2" />
      <path d="M22 12a10 10 0 0 0-10-10" stroke="currentColor" strokeWidth="3" strokeLinecap="round" />
    </svg>
  );
}

/* --------------------------------------------------------------- Button */

type Variant = 'primary' | 'secondary' | 'ghost' | 'danger' | 'soft' | 'navy';

interface ButtonProps extends ButtonHTMLAttributes<HTMLButtonElement> {
  variant?: Variant;
  loading?: boolean;
}

const variantClass: Record<Variant, string> = {
  primary: 'sw-btn-primary',
  navy: 'sw-btn-navy',
  secondary: 'sw-btn-secondary',
  danger: 'sw-btn-danger',
  soft: 'sw-btn-soft',
  ghost: 'sw-btn-ghost',
};

export function Button({ variant = 'primary', loading, className, children, disabled, ...rest }: ButtonProps) {
  return (
    <button
      className={cx('sw-btn', variantClass[variant], loading && 'is-loading', className)}
      disabled={disabled || loading}
      {...rest}
    >
      {loading ? <Spinner size={16} /> : null}
      {children}
    </button>
  );
}

/* ---------------------------------------------------------------- Card */

export function Card({ children, className, ...rest }: { children: ReactNode; className?: string } & React.HTMLAttributes<HTMLDivElement>) {
  return (
    <div className={cx('sw-card', className)} {...rest}>
      {children}
    </div>
  );
}

/* ------------------------------------------------------------ StatusChip */

const statusColor = (status: string): string => {
  const s = status.toUpperCase();
  if (/SUCCESS|ACTIVE|VERIFIED|RESOLVED|PUBLISHED|COMPLETED|APPROV/.test(s)) return 'var(--sw-success)';
  if (/FAIL|REJECTED|SUSPENDED|BLOCKED|DENIED|DECLINED|CLOSED/.test(s)) return 'var(--sw-error)';
  if (/PENDING|IN_REVIEW|OPEN|DRAFT|REQUESTED|UNVERIFIED|INITIAT|ARCHIVED/.test(s)) return 'var(--sw-warning)';
  return 'var(--sw-blue)';
};

export function StatusChip({ status }: { status: string }) {
  const color = statusColor(status);
  return (
    <span
      className="sw-chip"
      style={{ color, background: `${color}1f` }}
      role="status"
      aria-label={status || 'No status'}
    >
      {status === 'ARCHIVED' ? 'ARCHIVED' : status || '—'}
    </span>
  );
}

export function Badge({ children, tone = 'blue' }: { children: ReactNode; tone?: 'blue' | 'red' | 'green' | 'amber' | 'navy' | 'gray' }) {
  const map: Record<string, string> = {
    blue: 'var(--sw-blue)',
    red: 'var(--sw-error)',
    green: 'var(--sw-success)',
    amber: 'var(--sw-warning)',
    navy: 'var(--sw-navy)',
    gray: 'var(--sw-text-2)',
  };
  const color = map[tone];
  return (
    <span className="sw-badge" style={{ color, background: `${color}1a` }}>
      {children}
    </span>
  );
}

/* ---------------------------------------------------------- PageHeader */

export function PageHeader({ title, subtitle, actions }: { title: string; subtitle?: string; actions?: ReactNode }) {
  return (
    <div className="sw-pagehead">
      <div>
        <h1>{title}</h1>
        {subtitle ? <p>{subtitle}</p> : null}
      </div>
      {actions ? <div className="sw-pagehead-actions">{actions}</div> : null}
    </div>
  );
}

/* ---------------------------------------------------------------- Modal */

export function Modal({ open, onClose, title, children, footer, width = 560 }: { open: boolean; onClose: () => void; title: string; children: ReactNode; footer?: ReactNode; width?: number }) {
  const ref = useRef<HTMLDivElement>(null);
  useEffect(() => {
    if (!open) return;
    const onKey = (e: KeyboardEvent) => {
      if (e.key === 'Escape') onClose();
    };
    document.addEventListener('keydown', onKey);
    return () => document.removeEventListener('keydown', onKey);
  }, [open, onClose]);

  if (!open) return null;
  return (
    <div className="sw-modal-backdrop" onMouseDown={(e) => e.target === e.currentTarget && onClose()}>
      <div
        ref={ref}
        className="sw-modal"
        style={{ maxWidth: width }}
        role="dialog"
        aria-modal="true"
        aria-label={title}
      >
        <div className="sw-modal-head">
          <h3>{title}</h3>
          <button type="button" className="sw-iconbtn" onClick={onClose} aria-label="Close dialog">
            ×
          </button>
        </div>
        <div className="sw-modal-body">{children}</div>
        {footer ? <div className="sw-modal-foot">{footer}</div> : null}
      </div>
    </div>
  );
}

export function ConfirmDialog({ open, title, message, confirmLabel = 'Confirm', destructive, loading, onCancel, onConfirm }: { open: boolean; title: string; message: string; confirmLabel?: string; destructive?: boolean; loading?: boolean; onCancel: () => void; onConfirm: () => void }) {
  return (
    <Modal
      open={open}
      onClose={onCancel}
      title={title}
      footer={
        <>
          <Button variant="ghost" onClick={onCancel} disabled={loading}>
            Cancel
          </Button>
          <Button variant={destructive ? 'danger' : 'primary'} onClick={onConfirm} loading={loading}>
            {confirmLabel}
          </Button>
        </>
      }
    >
      <p className="sw-modal-msg">{message}</p>
    </Modal>
  );
}

/* ------------------------------------------------------------ Forms */

export function Field({ label, hint, error, required, children }: { label: string; hint?: string; error?: string; required?: boolean; children: ReactNode }) {
  return (
    <div className="sw-field">
      <label className="sw-label">
        {label}
        {required ? <span className="sw-req"> *</span> : null}
      </label>
      {children}
      {hint && !error ? <p className="sw-hint">{hint}</p> : null}
      {error ? (
        <p className="sw-err" role="alert">
          {error}
        </p>
      ) : null}
    </div>
  );
}

export function Input({ invalid, ...rest }: InputHTMLAttributes<HTMLInputElement> & { invalid?: boolean }) {
  return <input className={cx('sw-input', invalid && 'is-invalid')} {...rest} />;
}

export function TextArea({ invalid, ...rest }: TextareaHTMLAttributes<HTMLTextAreaElement> & { invalid?: boolean }) {
  return <textarea className={cx('sw-input', invalid && 'is-invalid')} {...rest} />;
}

export function Select({ invalid, ...rest }: SelectHTMLAttributes<HTMLSelectElement> & { invalid?: boolean }) {
  return <select className={cx('sw-input', invalid && 'is-invalid')} {...rest} />;
}

export function Toggle({ checked, onChange, label, disabled }: { checked: boolean; onChange: (v: boolean) => void; label: string; disabled?: boolean }) {
  return (
    <label className={cx('sw-toggle', disabled && 'is-disabled')}>
      <input type="checkbox" checked={checked} onChange={(e) => onChange(e.target.checked)} disabled={disabled} aria-label={label} />
      <span className="sw-toggle-track" aria-hidden="true">
        <span className="sw-toggle-thumb" />
      </span>
      <span className="sw-toggle-label">{label}</span>
    </label>
  );
}

/* ------------------------------------------------------------- Toast */

interface Toast {
  id: number;
  kind: 'success' | 'error' | 'info';
  message: string;
}

let toastListeners: Array<(t: Toast[]) => void> = [];
let toastSeq = 0;

function notify(toasts: Toast[]) {
  toastListeners.forEach((fn) => fn(toasts));
}

export function pushToast(kind: Toast['kind'], message: string) {
  const id = ++toastSeq;
  notify([{ id, kind, message }]);
  setTimeout(() => {
    notify([]);
  }, 4200);
}

export function ToastProvider({ children }: { children: ReactNode }) {
  const [toasts, setToasts] = useState<Toast[]>([]);
  useEffect(() => {
    toastListeners.push(setToasts);
    return () => {
      toastListeners = toastListeners.filter((fn) => fn !== setToasts);
    };
  }, []);
  return (
    <>
      {children}
      <div className="sw-toasts" aria-live="polite" role="status">
        {toasts.map((t) => (
          <div key={t.id} className={cx('sw-toast', `is-${t.kind}`)}>
            {t.message}
          </div>
        ))}
      </div>
    </>
  );
}

/* ------------------------------------------------------- Data table */

export function DataTable<T>({ columns, rows, rowKey, empty, loading }: { columns: { key: string; label: string; render?: (row: T) => ReactNode }[]; rows: T[]; rowKey: (row: T) => string | number; empty?: ReactNode; loading?: boolean }) {
  if (loading) {
    return <div className="sw-tableskel">Loading…</div>;
  }
  if (rows.length === 0) {
    return <>{empty ?? <EmptyState title="No results" message="Nothing to show for this view." />}</>;
  }
  return (
    <div className="sw-tablewrap">
      <table className="sw-table">
        <thead>
          <tr>
            {columns.map((c) => (
              <th key={c.key} scope="col">
                {c.label}
              </th>
            ))}
          </tr>
        </thead>
        <tbody>
          {rows.map((row) => (
            <tr key={rowKey(row)}>
              {columns.map((c) => (
                <td key={c.key}>{c.render ? c.render(row) : ((row as Record<string, unknown>)[c.key] as ReactNode)}</td>
              ))}
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}

export function EmptyState({ title, message, action }: { title: string; message: string; action?: ReactNode }) {
  return (
    <div className="sw-empty">
      <div className="sw-empty-ico" aria-hidden="true">
        ◌
      </div>
      <h3>{title}</h3>
      <p>{message}</p>
      {action}
    </div>
  );
}

export function ErrorState({ title = 'Something went wrong', message, onRetry }: { title?: string; message: string; onRetry?: () => void }) {
  return (
    <div className="sw-empty" role="alert">
      <div className="sw-empty-ico" aria-hidden="true">
        !
      </div>
      <h3>{title}</h3>
      <p>{message}</p>
      {onRetry ? (
        <Button variant="secondary" onClick={onRetry}>
          Try again
        </Button>
      ) : null}
    </div>
  );
}

export function LoadingState({ label = 'Loading…' }: { label?: string }) {
  return (
    <div className="sw-loading" role="status" aria-label={label}>
      <Spinner size={26} />
      <span>{label}</span>
    </div>
  );
}

/* ---------------------------------------------------------------- KPI */

export function KpiCard({ label, value, icon, tone }: { label: string; value: number | string; icon?: string; tone?: 'navy' | 'blue' | 'red' | 'green' | 'amber' }) {
  return (
    <Card className="sw-kpi">
      <div className="sw-kpi-top">
        <span className="sw-kpi-label">{label}</span>
        {icon ? <span className="sw-kpi-ico" aria-hidden="true">{icon}</span> : null}
      </div>
      <div className={cx('sw-kpi-value', tone ? `is-${tone}` : '')}>{value ?? '—'}</div>
    </Card>
  );
}

export { cx };