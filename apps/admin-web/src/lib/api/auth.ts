/// Auth endpoints — the backend remains the sole authority for identity,
/// tokens, role and permission. The panel never fabricates credentials.
import { client } from './client';
import type { Me } from './types';
import type { AdminSession } from '../auth/session';
import { loadSession, saveSession, clearSession } from '../auth/session';

export interface LoginResult {
  access: string;
  refresh: string;
  user: Me;
}

export async function login(emailOrPhone: string, password: string): Promise<User> {
  const res = await client.request<LoginResult>('/auth/login/', {
    method: 'POST',
    authenticated: false,
    body: { email_or_phone: emailOrPhone, password },
  });
  const session: AdminSession = { access: res.access, refresh: res.refresh, user: res.user };
  saveSession(session);
  return res.user;
}

export interface User extends Me {}

export async function fetchMe(): Promise<User> {
  const me = await client.request<Me>('/auth/me/', { authenticated: true });
  return me;
}

export async function logout(): Promise<void> {
  const session = loadSession();
  if (session) {
    try {
      await client.request('/auth/logout/', {
        method: 'POST',
        authenticated: true,
        body: { refresh: session.refresh },
      });
    } catch {
      // Logout still clears local state even if the server is unreachable.
    }
  }
  clearSession();
}

export { clearSession };