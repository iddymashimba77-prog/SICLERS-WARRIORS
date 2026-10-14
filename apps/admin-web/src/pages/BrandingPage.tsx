import { useCallback, useEffect, useRef, useState } from 'react';
import {
  Button,
  Card,
  ErrorState,
  Field,
  Input,
  LoadingState,
  PageHeader,
  pushToast,
} from '../components/ui';
import { useBranding } from '../lib/BrandingContext';
import {
  deleteBrandingLogo,
  fetchAdminBranding,
  updateBrandingAlt,
  uploadBrandingLogo,
} from '../lib/api/admin';
import type { BrandingInfo } from '../lib/api/types';

const ACCEPTED = ['image/jpeg', 'image/png', 'image/webp'];

export function BrandingPage() {
  const { logoUrl, refresh } = useBranding();
  const [info, setInfo] = useState<BrandingInfo | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const [alt, setAlt] = useState('');
  const [file, setFile] = useState<File | null>(null);
  const [preview, setPreview] = useState<string | null>(null);
  const [saving, setSaving] = useState(false);
  const fileRef = useRef<HTMLInputElement>(null);

  useEffect(() => {
    let alive = true;
    fetchAdminBranding()
      .then((b) => {
        if (!alive) return;
        setInfo(b);
        setAlt(b.logo_alt);
      })
      .catch(() => {
        if (alive) setError('Could not load the current branding. Please try again.');
      })
      .finally(() => {
        if (alive) setLoading(false);
      });
    return () => {
      alive = false;
    };
  }, []);

  const pickFile = useCallback((next: File | null) => {
    setFile(next);
    if (next) {
      const reader = new FileReader();
      reader.onload = () => setPreview(String(reader.result));
      reader.readAsDataURL(next);
    } else {
      setPreview(null);
    }
  }, []);

  async function saveLogo() {
    if (!file) return;
    if (!ACCEPTED.includes(file.type) || file.size > 5 * 1024 * 1024) {
      pushToast('error', 'Unsupported image. Use a JPEG, PNG or WebP up to 5 MB.');
      return;
    }
    setSaving(true);
    try {
      const updated = await uploadBrandingLogo(file, alt);
      setInfo(updated);
      setAlt(updated.logo_alt ?? alt);
      setFile(null);
      setPreview(null);
      if (fileRef.current) fileRef.current.value = '';
      await refresh();
      pushToast('success', 'Logo updated. The new logo is now served across the platform.');
    } catch (err) {
      pushToast('error', err instanceof Error ? err.message : 'Could not upload the logo.');
    } finally {
      setSaving(false);
    }
  }

  async function saveAlt() {
    setSaving(true);
    try {
      const updated = await updateBrandingAlt(alt);
      setInfo(updated);
      pushToast('success', 'Alt text saved.');
    } catch (err) {
      pushToast('error', err instanceof Error ? err.message : 'Could not save the alt text.');
    } finally {
      setSaving(false);
    }
  }

  async function removeLogo() {
    if (!info?.has_logo) return;
    setSaving(true);
    try {
      await deleteBrandingLogo();
      setInfo((prev) => (prev ? { ...prev, has_logo: false, logo_alt: prev.logo_alt } : prev));
      await refresh();
      pushToast('info', 'Logo removed. The built-in default is shown again.');
    } catch (err) {
      pushToast('error', err instanceof Error ? err.message : 'Could not remove the logo.');
    } finally {
      setSaving(false);
    }
  }

  if (loading) return <LoadingState label="Loading branding…" />;
  if (error) return <ErrorState title="Branding unavailable" message={error} />;

  return (
    <>
      <PageHeader
        title="Branding"
        subtitle="Upload the platform logo. It is served from the backend and used across the app."
      />

      <div className="sw-grid sw-grid-2">
        <Card style={{ padding: 16 }}>
          <h3 style={{ marginBottom: 6 }}>Current logo</h3>
          <p style={{ fontSize: 13, color: 'var(--sw-text-2)' }}>
            {info?.has_logo
              ? 'A custom logo is active and served at /api/branding/logo/.'
              : 'No custom logo yet — the built-in default is shown.'}
          </p>
          <div
            style={{
              margin: '16px 0',
              padding: 20,
              background: 'var(--sw-surface-2)',
              border: '1px dashed var(--sw-border)',
              borderRadius: 'var(--sw-radius-md)',
              display: 'grid',
              placeItems: 'center',
              minHeight: 160,
            }}
          >
            <img
              src={logoUrl}
              alt={info?.logo_alt || 'Platform logo'}
              style={{ maxWidth: 220, maxHeight: 120, objectFit: 'cover' }}
            />
          </div>
          {info?.has_logo ? (
            <Button
              variant="danger"
              onClick={removeLogo}
              loading={saving}
              disabled={saving}
              type="button"
            >
              Remove custom logo
            </Button>
          ) : null}
        </Card>

        <Card style={{ padding: 16 }}>
          <h3 style={{ marginBottom: 6 }}>Replace logo</h3>
          <p style={{ fontSize: 13, color: 'var(--sw-text-2)', marginBottom: 12 }}>
            JPEG, PNG or WebP up to 5 MB. The image is re-encoded server-side and served
            consistently.
          </p>

          {preview ? (
            <div
              style={{
                marginBottom: 14,
                padding: 16,
                background: 'var(--sw-surface-2)',
                border: '1px dashed var(--sw-border)',
                borderRadius: 'var(--sw-radius-md)',
                display: 'grid',
                placeItems: 'center',
              }}
            >
              <img src={preview} alt="New logo preview" style={{ maxWidth: 220, maxHeight: 120, objectFit: 'cover' }} />
            </div>
          ) : null}

          <input
            ref={fileRef}
            type="file"
            accept={ACCEPTED.join(',')}
            data-testid="logo-file-input"
            onChange={(e) => pickFile(e.target.files?.[0] ?? null)}
            style={{ marginBottom: 14 }}
          />

          <Field label="Alt text" hint="Describes the logo for accessibility.">
            <Input value={alt} maxLength={160} onChange={(e) => setAlt(e.target.value)} />
          </Field>

          <div className="sw-toolbar" style={{ marginTop: 16 }}>
            <Button type="button" onClick={saveLogo} loading={saving} disabled={saving || !file}>
              {info?.has_logo ? 'Replace logo' : 'Upload logo'}
            </Button>
            <Button type="button" variant="secondary" onClick={saveAlt} loading={saving} disabled={saving}>
              Save alt text
            </Button>
          </div>
        </Card>
      </div>
    </>
  );
}