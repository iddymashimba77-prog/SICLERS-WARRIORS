import { createContext, useContext, useEffect, useState, type ReactNode } from 'react';
import { fetchBrandingInfo } from './api/admin';
import type { BrandingInfo } from './api/types';

/// Builds the platform's brand logo URL. The backend serves the uploaded logo
/// as plain bytes at `/api/branding/logo/` (through the same Vite proxy the
/// panel already uses); until an admin uploads one we fall back to the
/// bundled asset so the panel always shows a brand mark.
export function resolveLogoUrl(hasLogo: boolean | undefined, defaultAsset = '/sicklers_warriors_logo.png'): string {
  return hasLogo ? '/api/branding/logo/' : defaultAsset;
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

  return (
    <BrandingContext.Provider
      value={{
        info,
        logoUrl: resolveLogoUrl(info?.has_logo),
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