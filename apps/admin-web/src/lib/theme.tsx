import { createContext, useCallback, useContext, useEffect, useMemo, useState } from 'react';

/**
 * Sickler's Warriors — Admin Web global appearance.
 *
 * Light / Dark / System with device persistence. The chosen mode is written to
 * `document.documentElement.dataset.theme` ('light' | 'dark'); every UI token
 * in index.css re-resolves under `[data-theme="dark"]`, so cards, tables,
 * modals, toasts and the shell all flip together without per-component code.
 */

export type ThemeMode = 'light' | 'dark' | 'system';

export type ResolvedTheme = Exclude<ThemeMode, 'system'>;

const STORAGE_KEY = 'sw.admin.theme';

const media: MediaQueryList | null =
  typeof window !== 'undefined' ? window.matchMedia('(prefers-color-scheme: dark)') : null;

export function resolveTheme(mode: ThemeMode): ResolvedTheme {
  if (mode === 'system') return media?.matches ? 'dark' : 'light';
  return mode;
}

export function applyTheme(mode: ThemeMode): void {
  if (typeof document === 'undefined') return;
  document.documentElement.dataset.theme = resolveTheme(mode);
}

export function readStoredTheme(): ThemeMode {
  if (typeof localStorage === 'undefined') return 'system';
  const raw = localStorage.getItem(STORAGE_KEY);
  return raw === 'light' || raw === 'dark' || raw === 'system' ? raw : 'system';
}

// Apply before the first paint so the shell never flashes in the wrong theme.
applyTheme(readStoredTheme());

interface ThemeContextValue {
  /** User's stored preference (never auto-resolved). */
  mode: ThemeMode;
  /** What is actually on screen right now ('light' | 'dark'). */
  resolved: ResolvedTheme;
  isDark: boolean;
  setMode: (mode: ThemeMode) => void;
}

const ThemeContext = createContext<ThemeContextValue | null>(null);

export function ThemeProvider({ children }: { children: React.ReactNode }) {
  const [mode, setModeState] = useState<ThemeMode>(readStoredTheme);

  const setMode = useCallback((next: ThemeMode) => {
    setModeState(next);
    try {
      localStorage.setItem(STORAGE_KEY, next);
    } catch {
      // Storage unavailable (private mode / tests): still apply for this session.
    }
    applyTheme(next);
  }, []);

  useEffect(() => {
    applyTheme(mode);
    if (mode !== 'system' || !media) return;
    const onChange = () => applyTheme('system');
    media.addEventListener('change', onChange);
    return () => media.removeEventListener('change', onChange);
  }, [mode]);

  const value = useMemo<ThemeContextValue>(() => {
    const resolved = resolveTheme(mode);
    return { mode, resolved, isDark: resolved === 'dark', setMode };
  }, [mode, setMode]);

  return <ThemeContext.Provider value={value}>{children}</ThemeContext.Provider>;
}

export function useTheme(): ThemeContextValue {
  const ctx = useContext(ThemeContext);
  if (!ctx) throw new Error('useTheme must be used within <ThemeProvider>.');
  return ctx;
}