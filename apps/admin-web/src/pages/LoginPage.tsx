import { useState, type FormEvent } from 'react';
import { useNavigate } from 'react-router-dom';
import { useAuth } from '../lib/auth/AuthContext';
import { useBranding } from '../lib/BrandingContext';
import { Button, Field, Input } from '../components/ui';

export function LoginPage() {
  const { login } = useAuth();
  const { logoUrl, info } = useBranding();
  const navigate = useNavigate();
  const [identifier, setIdentifier] = useState('');
  const [password, setPassword] = useState('');
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(false);

  async function onSubmit(e: FormEvent) {
    e.preventDefault();
    if (!identifier.trim() || !password) {
      setError('Please enter your email or phone and password.');
      return;
    }
    setError(null);
    setLoading(true);
    try {
      await login(identifier.trim(), password);
      navigate('/admin', { replace: true });
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Sign in failed. Please try again.');
    } finally {
      setLoading(false);
    }
  }

  return (
    <div className="sw-login-wrap">
      <div className="sw-login-left">
        <h1>The Sickler's Warriors operations console.</h1>
        <p>
          Sign in with your existing account. Only administrators and approved
          staff are permitted; ordinary patient accounts are not granted access.
        </p>
      </div>
      <div className="sw-login-card">
        <img src={logoUrl} alt={info?.logo_alt || 'Sickler\'s Warriors logo'} className="sw-brand-img" style={{ width: 72, height: 72 }} />
        <h2>Admin Panel</h2>
        <p className="sw-sub">Sign in to continue</p>
        <form onSubmit={onSubmit} style={{ width: '100%' }} noValidate>
          <Field label="Email or phone" required>
            <Input
              autoFocus
              type="text"
              autoComplete="username"
              value={identifier}
              onChange={(e) => setIdentifier(e.target.value)}
              placeholder="you@example.com"
              aria-label="Email or phone"
            />
          </Field>
          <Field label="Password" required>
            <Input
              type="password"
              autoComplete="current-password"
              value={password}
              onChange={(e) => setPassword(e.target.value)}
              placeholder="••••••••"
              aria-label="Password"
            />
          </Field>
          {error ? (
            <p className="sw-err" role="alert" style={{ marginBottom: 12 }}>
              {error}
            </p>
          ) : null}
          <Button type="submit" loading={loading} style={{ width: '100%' }}>
            Sign in
          </Button>
        </form>
      </div>
    </div>
  );
}