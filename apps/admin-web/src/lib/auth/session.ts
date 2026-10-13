/// Session persistence for the Admin Panel.
///
/// The backend is the authority for identity/role/permission (via
/// `/api/auth/login`, `/refresh`, `/me`). The browser only caches the issued
/// access/refresh pair — no credentials, no role claims are authored here.
const KEY = 'sw_admin_session_v1';

export interface MeUser {
  uid: string;
  email: string;
  phone?: string;
  full_name?: string;
  first_name?: string;
  last_name?: string;
  account_status: string;
  role_codes: string[];
  permission_codes: string[];
  mfa_enabled?: boolean;
  is_mfa_enabled?: boolean;
}

export interface AdminSession {
  access: string;
  refresh: string;
  user: MeUser;
}

export function loadSession(): AdminSession | null {
  try {
    const raw = localStorage.getItem(KEY);
    if (!raw) return null;
    const parsed = JSON.parse(raw) as AdminSession;
    if (!parsed?.access || !parsed?.refresh) return null;
    return parsed;
  } catch {
    return null;
  }
}

export function saveSession(session: AdminSession): void {
  localStorage.setItem(KEY, JSON.stringify(session));
}

export function updateAccess(access: string): void {
  const s = loadSession();
  if (!s) return;
  saveSession({ ...s, access });
}

/**
 * Persist a rotated token pair. Refresh tokens rotate on every use
 * (`ROTATE_REFRESH_TOKENS` + `BLACKLIST_AFTER_ROTATION`), so storing only the
 * new access would leave the stored refresh blacklisted and kill the session
 * on the next rotation.
 */
export function updateTokens(access: string, refresh?: string): void {
  const s = loadSession();
  if (!s) return;
  saveSession(refresh ? { ...s, access, refresh } : { ...s, access });
}

export function clearSession(): void {
  localStorage.removeItem(KEY);
}

let listeners = new Set<() => void>();
export function onAuthChanged(fn: () => void): () => void {
  listeners.add(fn);
  return () => listeners.delete(fn);
}
function emit() {
  listeners.forEach((fn) => fn());
}
export function notifyAuthChanged(): void {
  emit();
}