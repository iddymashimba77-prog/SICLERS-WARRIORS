/**
 * Sickler's Warriors — Admin Web design tokens.
 * Approved brand tokens (Stage 3 admin-web design). Dark Blue is the primary
 * surface/brand color; Red is RESERVED for danger/emergency status only and
 * must never be used as a primary product surface.
 */
export const colors = {
  primary: '#0D47A1',
  primaryDark: '#002171',
  secondary: '#1976D2',
  background: '#FFFFFF',
  surface: '#FFFFFF',
  emergency: '#C62828',
  textPrimary: '#0D1B2A',
  textOnPrimary: '#FFFFFF',
} as const;

export const spacing = { xs: 4, sm: 8, md: 16, lg: 24, xl: 32 } as const;
