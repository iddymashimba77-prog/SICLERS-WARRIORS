/// Centralized API client for the Admin Panel.
///
/// Talks to the existing Django/DRF backend via the same contract every stage
/// uses (see exactly `admin_repository.dart` on the mobile side):
///   - success envelope `{"data": ...}` (or the raw object for some public
///     endpoints),
///   - errors `{"error": {code, message, details}}`,
///   - `401` -> refresh-once then retry once, else sign out.
/// No request is a raw `fetch`; all endpoints go through this layer.
import { clearSession, loadSession, notifyAuthChanged, updateTokens } from '../auth/session';

export class ApiError extends Error {
  readonly status: number;
  readonly code: string;
  readonly details: Record<string, unknown>;
  constructor(message: string, status: number, code = 'API_ERROR', details: Record<string, unknown> = {}) {
    super(message);
    this.name = 'ApiError';
    this.status = status;
    this.code = code;
    this.details = details;
  }
}

const BASE = (import.meta.env.VITE_API_BASE as string | undefined) ?? '/api';

export { BASE };

const TIMEOUT_MS = 20000;

interface RequestOptions {
  method?: 'GET' | 'POST' | 'PATCH' | 'PUT' | 'DELETE';
  body?: unknown;
  /** multipart/form-data payload. Mutually exclusive with `body`. */
  form?: FormData;
  headers?: Record<string, string>;
  authenticated?: boolean;
  timeout?: number;
  /**
   * `text` returns the raw body (used by the CSV export endpoints, whose
   * `text/csv` payload is not an JSON envelope). Status errors are still
   * decoded as `ApiError`.
   */
  response?: 'json' | 'text';
}

function extractError(body: string, status: number): ApiError {
  try {
    const map = JSON.parse(body) as { error?: { code?: string; message?: string | string[]; details?: Record<string, unknown> } };
    const err = map.error ?? {};
    const code = err.code ?? 'API_ERROR';
    if (code === 'TOKEN_EXPIRED' || status === 401) {
      return new ApiError('Session expired. Please sign in again.', 401, 'TOKEN_EXPIRED');
    }
    const raw = err.message;
    let message: string;
    if (Array.isArray(raw) && raw.length > 0) {
      message = raw.map((s) => String(s).trim()).filter(Boolean).join(' ');
    } else if (typeof raw === 'string' && raw.trim()) {
      message = raw.trim();
    } else {
      message = `Request failed (${status}). Please try again.`;
    }
    return new ApiError(message, status, code, err.details ?? {});
  } catch {
    const message =
      status >= 500 ? 'Server error. Please try again shortly.' : `Request failed (${status}).`;
    return new ApiError(message, status, 'API_ERROR');
  }
}

function unwrap(body: string, status: number): unknown {
  if (status >= 400) throw extractError(body, status);
  const parsed = JSON.parse(body) as unknown;
  if (parsed && typeof parsed === 'object' && 'data' in (parsed as object)) {
    return (parsed as { data: unknown }).data;
  }
  return parsed;
}

async function doFetch(path: string, opts: RequestOptions, access: string | null): Promise<unknown> {
  // Retry transient connection-level failures (dead keep-alive sockets,
  // momentary restarts) that would otherwise surface as a scary "Network
  // error". Bounded and silent; the dev server answers in ms normally.
  const MAX_ATTEMPTS = 3;
  const RETRY_MS = 700;
  let lastError: ApiError = new ApiError('Network error. Please check your connection.', 0, 'NETWORK');
  for (let attempt = 0; attempt < MAX_ATTEMPTS; attempt++) {
    if (attempt > 0) await new Promise((r) => setTimeout(r, RETRY_MS * attempt));
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), opts.timeout ?? TIMEOUT_MS);
    const headers: Record<string, string> = {
      Accept: 'application/json',
      // A FormData body must NOT carry an explicit Content-Type: the browser
      // has to append the multipart boundary itself.
      ...(opts.body !== undefined ? { 'Content-Type': 'application/json' } : {}),
      ...(access ? { Authorization: `Bearer ${access}` } : {}),
      ...opts.headers,
    };
    try {
      const res = await fetch(`${BASE}${path}`, {
        method: opts.method ?? 'GET',
        headers,
        body:
          opts.form !== undefined
            ? opts.form
            : opts.body === undefined
              ? undefined
              : JSON.stringify(opts.body),
        signal: controller.signal,
      });
      const text = await res.text();
      if (opts.response === 'text') {
        if (res.status >= 400) throw extractError(text, res.status);
        return text as unknown;
      }
      return unwrap(text, res.status);
    } catch (e) {
      // HTTP errors (400/401/403/500 …) are real answers from the server —
      // surface them as-is. Retrying them, or flattening them into a generic
      // "network error", hides validation and permission failures behind a
      // misleading offline message (and made the 401-refresh path unreachable).
      if (e instanceof ApiError) throw e;
      if (e instanceof DOMException && e.name === 'AbortError') {
        throw new ApiError('Request timed out. Please try again.', 0, 'TIMEOUT');
      }
      if (e instanceof SyntaxError) {
        throw new ApiError('The server returned an unreadable response.', 0, 'BAD_RESPONSE');
      }
      lastError = new ApiError('Network error. Please check your connection.', 0, 'NETWORK');
      // Only genuine connection-level failures (dead keep-alive sockets,
      // momentary restarts) are re-attempted.
    } finally {
      clearTimeout(timer);
    }
  }
  const serverUp = await probeServer();
  if (serverUp) {
    throw new ApiError(
      'The admin server is reachable, but this request was blocked locally (offline mode, ad-blocker or VPN). Please retry after refreshing the page.',
      0,
      'NETWORK',
    );
  }
  throw lastError;
}

async function probeServer(): Promise<boolean> {
  try {
    const controller = new AbortController();
    const t = setTimeout(() => controller.abort(), 5000);
    const res = await fetch(`${BASE}/content/ticker/`, {
      method: 'GET',
      headers: { Accept: 'application/json' },
      signal: controller.signal,
    });
    clearTimeout(t);
    return res.ok;
  } catch {
    return false;
  }
}

export class Client {
  async request<T = unknown>(path: string, opts: RequestOptions = {}): Promise<T> {
    const session = loadSession();
    const token = opts.authenticated ? session?.access ?? null : null;
    const needsAuth = opts.authenticated !== false;

    try {
      return (await doFetch(path, opts, needsAuth ? token : null)) as T;
    } catch (e) {
      // One refresh-and-retry on 401/expired, respecting rotation.
      if (needsAuth && e instanceof ApiError && (e.status === 401 || e.code === 'TOKEN_EXPIRED')) {
        const refreshed = await this.refresh();
        if (refreshed) {
          return (await doFetch(path, opts, loadSession()?.access ?? null)) as T;
        }
        clearSession();
        notifyAuthChanged();
        throw new ApiError('Session expired. Please sign in again.', 401, 'TOKEN_EXPIRED');
      }
      throw e;
    }
  }

  private async refresh(): Promise<boolean> {
    const session = loadSession();
    if (!session) return false;
    try {
      const res = await fetch(`${BASE}/auth/refresh/`, {
        method: 'POST',
        headers: { Accept: 'application/json', 'Content-Type': 'application/json' },
        body: JSON.stringify({ refresh: session.refresh }),
      });
      if (!res.ok) return false;
      // The backend renders through `ApiEnvelopeRenderer`, so the rotated pair
      // arrives as `{"data": {access, refresh}}` — never as a bare body.
      const raw = (await res.json()) as { data?: { access?: string; refresh?: string }; access?: string; refresh?: string };
      const pair = (raw && typeof raw === 'object' && raw.data ? raw.data : raw) as { access?: string; refresh?: string };
      if (!pair?.access) return false;
      updateTokens(pair.access, pair.refresh);
      return true;
    } catch {
      return false;
    }
  }

  /**
   * Fetch a binary resource (e.g. a verification document) with the bearer
   * token attached, since a protected file cannot be opened by a plain `<a>`
   * or `window.open`. Refreshes once on 401 like {@link request}.
   */
  async blob(path: string): Promise<Blob> {
    const load = async (): Promise<Blob> => {
      const access = loadSession()?.access ?? null;
      const res = await fetch(`${BASE}${path}`, {
        headers: { ...(access ? { Authorization: `Bearer ${access}` } : {}) },
      });
      if (!res.ok) throw extractError(await res.text(), res.status);
      return res.blob();
    };
    try {
      return await load();
    } catch (e) {
      if (e instanceof ApiError && (e.status === 401 || e.code === 'TOKEN_EXPIRED')) {
        const refreshed = await this.refresh();
        if (refreshed) return load();
        clearSession();
        notifyAuthChanged();
        throw new ApiError('Session expired. Please sign in again.', 401, 'TOKEN_EXPIRED');
      }
      throw e;
    }
  }
}

export const client = new Client();

/** Convenience for the generic list shape `{"data": {"results": [...]}}`. */
export async function fetchList<T>(path: string, options?: RequestOptions): Promise<T[]> {
  const payload = await client.request<{ results?: T[] }>(path, options);
  if (Array.isArray(payload)) return payload as unknown as T[];
  return Array.isArray(payload?.results) ? (payload.results as T[]) : [];
}

/** Union of all admin portal permission codes the panel gates on. */
export const PORTAL_PERMISSIONS: readonly string[] = [
  'admin.users.manage',
  'admin.roles.manage',
  'admin.permissions.manage',
  'admin.branding.manage',
  'admin.audit.read',
  'audit_logs.view',
  'audit_logs.export',
  'analytics.view',
  'analytics.export',
  'content.news.manage',
  'content.ticker.manage',
  'education.review',
  'community.moderate',
  'donations.view',
  'donations.refund',
  'notifications.broadcast',
  'doctors.verify',
  'facilities.verify',
  'blood_requests.verify',
  'campaigns.verify',
];

export const ADMIN_ROLE_HINTS: readonly string[] = [
  'SUPER_ADMIN',
  'ADMIN',
  'VERIFICATION_OFFICER',
  'MODERATOR',
  'CLINICAL_ADMIN',
  'CONTENT_ADMIN',
  'FINANCE_ADMIN',
  'SUPPORT_AGENT',
  'SECURITY_AUDITOR',
];

export function isAdminPrincipal(roleCodes: string[], permissionCodes: string[]): boolean {
  if (roleCodes.some((r) => ADMIN_ROLE_HINTS.includes(r))) return true;
  return permissionCodes.some((p) => PORTAL_PERMISSIONS.includes(p));
}