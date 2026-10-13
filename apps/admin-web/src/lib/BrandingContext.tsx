import { createContext, useContext, useEffect, useState, type ReactNode } from 'react';
import { fetchBrandingInfo } from './api/admin';
import type { BrandingInfo } from './api/types';

/// Builds the platform's brand logo URL. The backend serves the uploaded logo
/// as plain bytes at `/api/branding/logo/`; until an admin uploads one we fall
/// back to the bundled asset so the panel always shows a brand mark.
///
/// The logo endpoint returns the same URL whether the bytes changed or not
/// (server sends `Cache-Control: max-age=3600`), so the browser would keep
/// showing the *old* artwork after a replacement. Every uploaded logo carries a
/// `logo_version` (the row's updated-at stamp) — we append it as a query param
/// so a new upload becomes a brand-new URL the browser must fetch.
export function resolveLogoUrl(hasLogo: boolean | undefined, version?: string, defaultAsset = '/sicklers_warriors_logo.png'): string {
  if (!hasLogo) return defaultAsset;
  return version ? `/api/branding/logo/?v=${encodeURIComponent(version)}` : '/api/branding/logo/';
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

  const refresh = async () => {
    try {
      const next = await fetchBrandingInfo();
      setInfo(next);
    } catch {
      setInfo(null);
    }
  };

  useEffect(() => {
    void refresh();
  }, []);

  const logoUrl = resolveLogoUrl(info?.has_logo, info?.logo_version);

  // Keep the favicon on the current brand artwork so a changed logo is obvious
  // on the browser tab, not just inside the panel.
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