/// Sickler's Warriors — Admin Web design tokens (approved brand system).
///
/// Color hierarchy (approved, final — supersedes the Stage-3 "red reserved"
/// note): Red is the primary Sickler's Warriors brand accent; Navy carries
/// structure/headings/navigation; Blue is secondary/informational; White is
/// content; Light gray is the page background; Green/Amber signal status;
/// Red also marks destructive/critical actions. The panel stays professional —
/// red is used as the accent, not as the entire surface.
export const colors = {
  primary: '#C81E3A' as const,
  primaryHover: '#B31A33' as const,
  darkRed: '#9F1530' as const,
  lightRed: '#FDECEF' as const,
  navy: '#0B1F3D' as const,
  navySoft: '#12294D' as const,
  blue: '#1B5FAE' as const,
  lightBlue: '#EAF3FB' as const,
  pageBg: '#F5F7FA' as const,
  surface: '#FFFFFF' as const,
  textPrimary: '#172033' as const,
  textSecondary: '#667085' as const,
  textMuted: '#98A2B3' as const,
  textOnDark: '#FFFFFF' as const,
  border: '#E4E7EC' as const,
  success: '#16803C' as const,
  warning: '#B7791F' as const,
  error: '#C81E3A' as const,
} as const;

export const spacing = { xs: 4, sm: 8, md: 16, lg: 24, xl: 32 } as const;

export const radius = { sm: 8, md: 12, lg: 16, pill: 999 } as const;

export const font = {
  family:
    "'Inter', -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, 'Helvetica Neue', Arial, sans-serif",
  h1: '26px/1.2 700',
  h2: '20px/1.3 700',
  h3: '16px/1.4 600',
  body: '14px/1.5 400',
  small: '12px/1.5 400',
  label: '12px/1.4 600',
} as const;

export const shadow = {
  card: '0 1px 2px rgba(11,31,61,0.05), 0 1px 3px rgba(11,31,61,0.08)',
  pop: '0 4px 16px rgba(11,31,61,0.16)',
} as const;

export const z = { base: 0, header: 20, sidebar: 30, modal: 100, toast: 200 } as const;