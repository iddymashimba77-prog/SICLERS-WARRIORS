import { createContext, useCallback, useContext, useEffect, useMemo, useState, type ReactNode } from 'react';
import { login as apiLogin, fetchMe, logout as apiLogout, clearSession } from '../api/auth';
import { isAdminPrincipal } from '../api/client';
import { loadSession, onAuthChanged, saveSession, type MeUser } from './session';

export type AuthStatus = 'loading' | 'signedOut' | 'signedIn' | 'denied';

interface AuthState {
  status: AuthStatus;
  user: MeUser | null;
  isReady: boolean;
  login: (emailOrPhone: string, password: string) => Promise<void>;
  logout: () => Promise<void>;
  hasPerm: (code: string) => boolean;
  hasAnyPerm: (codes: string[]) => boolean;
  isSuper: boolean;
  canAccess: boolean;
}

const AuthContext = createContext<AuthState | null>(null);

export function AuthProvider({ children }: { children: ReactNode }) {
  const [status, setStatus] = useState<AuthStatus>('loading');
  const [user, setUser] = useState<MeUser | null>(null);

  useEffect(() => {
    let cancelled = false;
    async function bootstrap() {
      const session = loadSession();
      if (!session) {
        if (!cancelled) setStatus('signedOut');
        return;
      }
      try {
        const me = await fetchMe();
        if (cancelled) return;
        const sessionAfter = loadSession();
        if (sessionAfter) saveSession({ ...sessionAfter, user: me });
        if (!isAdminPrincipal(me.role_codes ?? [], me.permission_codes ?? [])) {
          clearSession();
          setUser(null);
          setStatus('denied');
          return;
        }
        setUser(me);
        setStatus('signedIn');
      } catch {
        if (!cancelled) {
          clearSession();
          setStatus('signedOut');
        }
      }
    }
    void bootstrap();
    const unsubscribe = onAuthChanged(() => {
      const s = loadSession();
      if (!s) setStatus('signedOut');
    });
    return () => {
      cancelled = true;
      unsubscribe();
    };
  }, []);

  const login = useCallback(async (emailOrPhone: string, password: string) => {
    const me = await apiLogin(emailOrPhone, password);
    if (!isAdminPrincipal(me.role_codes ?? [], me.permission_codes ?? [])) {
      clearSession();
      throw new Error('This account does not have administrative access to the panel.');
    }
    setUser(me);
    setStatus('signedIn');
  }, []);

  const logout = useCallback(async () => {
    setStatus('loading');
    await apiLogout();
    setUser(null);
    setStatus('signedOut');
  }, []);

  const value = useMemo<AuthState>(() => {
    const perms = user?.permission_codes ?? [];
    const roles = user?.role_codes ?? [];
    return {
      status,
      user,
      isReady: status === 'signedOut' || status === 'signedIn' || status === 'denied',
      login,
      logout,
      hasPerm: (code) => perms.includes(code) || roles.includes('SUPER_ADMIN'),
      hasAnyPerm: (codes) => codes.some((c) => perms.includes(c)) || roles.includes('SUPER_ADMIN'),
      isSuper: !!roles.includes('SUPER_ADMIN'),
      canAccess: status === 'signedIn',
    };
  }, [status, user, login, logout]);

  return <AuthContext.Provider value={value}>{children}</AuthContext.Provider>;
}

export function useAuth(): AuthState {
  const ctx = useContext(AuthContext);
  if (!ctx) throw new Error('useAuth must be used inside AuthProvider');
  return ctx;
}

export function friendlyError(e: unknown): string {
  if (e instanceof Error) return e.message || 'Something went wrong. Please try again.';
  return 'Something went wrong. Please try again.';
}