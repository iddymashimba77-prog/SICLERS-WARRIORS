import { createContext, useContext, useEffect, useState, type ReactNode, type SyntheticEvent } from 'react';
import { fetchBrandingInfo } from './api/admin';
import { BASE } from './api/client';
import type { BrandingInfo } from './api/types';

/// Builds the platform's brand logo URL. The backend serves the uploaded logo
/// as plain bytes at `/api/branding/logo/`; until an admin uploads one we fall
/// back to the bundled asset so the panel always shows a brand mark.
///
/// The endpoint lives on the API origin, so the URL must be built on the same
/// `BASE` every other request uses — a relative `/api/...` path would resolve
/// against the admin static-site origin (which has no such route) and 404,
/// leaving phones (where the brand text is hidden) with no visible logo.
///
/// The logo endpoint returns the same URL whether the bytes changed or not
/// (server sends `Cache-Control: max-age=3600`), so the browser would keep
/// showing the *old* artwork after a replacement. Every uploaded logo carries
/// a `logo_version` (the row's updated-at stamp) — we append it as a query param
/// so a new upload becomes a brand-new URL the browser must fetch.
export function resolveLogoUrl(
  hasLogo: boolean | undefined,
  version?: string,
  defaultAsset = '/sicklers_warriors_logo.png',
  ts?: number,
  base = BASE,
): string {
  if (!hasLogo) return defaultAsset;
  const params = new URLSearchParams();
  if (version) params.set('v', version);
  if (ts) params.set('ts', ts.toString());
  const qs = params.toString();
  return qs ? `${base}/branding/logo/?${qs}` : `${base}/branding/logo/`;
}

/// Falls back to the bundled logo when the live endpoint cannot be reached
/// (API restart, cold start, offline), so a brand mark always renders.
export function logoFallback(defaultAsset = '/sicklers_warriors_logo.png') {
  return (event: SyntheticEvent<HTMLImageElement>) => {
    const img = event.currentTarget;
    if (img.dataset.fallback === '1') return;
    img.dataset.fallback = '1';
    img.src = defaultAsset;
  };
}

/// Keeps the browser tab's favicon in sync with the live brand mark.
export function syncFavicon(logoUrl: string, defaultAsset = '/sicklers_warriors_logo.png'): void {
  const href = logoUrl || defaultAsset;
  let link = document.querySelector<HTMLLinkElement>('link[rel="icon"]');
  if (!link) {
    link = document.createElement('link');
    link.rel = 'icon';
    document.head.appendChild(link);
  }
  link.href = href;
}

interface BrandingContextValue {
  info: BrandingInfo | null;
  logoUrl: string;
  refresh: () => Promise<void>;
}

const BrandingContext = createContext<BrandingContextValue>({
  info: null,
  logoUrl: '/sicklers_warriors_logo.png',
  refresh: async () => {},
});

export function BrandingProvider({ children }: { children: ReactNode }) {
  const [info, setInfo] = useState<BrandingInfo | null>(null);
  const [bust, setBust] = useState<number>(0);

  const refresh = async () => {
    try {
      const next = await fetchBrandingInfo();
      setInfo(next);
      setBust(Date.now());
    } catch {
      setInfo(null);
    }
  };

  useEffect(() => {
    void refresh();
  }, []);

  const logoUrl = resolveLogoUrl(info?.has_logo, info?.logo_version, '/sicklers_warriors_logo.png', bust || Date.now());

  useEffect(() => {
    syncFavicon(logoUrl);
  }, [logoUrl]);

  return (
    <BrandingContext.Provider
      value={{
        info,
        logoUrl,
        refresh,
      }}
    >
      {children}
    </BrandingContext.Provider>
  );
}

export function useBranding(): BrandingContextValue {
  return useContext(BrandingContext);
}
