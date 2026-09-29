import { Link } from 'react-router-dom';
import { Button } from '../components/ui';

export function DeniedPage() {
  return (
    <div className="sw-empty" style={{ minHeight: '100vh', display: 'grid', placeItems: 'center', border: 'none' }}>
      <div style={{ maxWidth: 440 }}>
        <div className="sw-empty-ico">!</div>
        <h2>Access denied</h2>
        <p>
          Your account does not have administrative permission for the Admin Panel.
          If you believe this is a mistake, contact your administrator.
        </p>
        <Button variant="secondary" onClick={() => window.location.assign('/admin/login')}>
          Back to sign in
        </Button>
      </div>
    </div>
  );
}

export function NotFoundPage() {
  return (
    <div className="sw-empty" style={{ minHeight: '100vh', display: 'grid', placeItems: 'center', border: 'none' }}>
      <div style={{ maxWidth: 440 }}>
        <div className="sw-empty-ico">◌</div>
        <h2>Page not found</h2>
        <p>The page you are looking for does not exist in this application.</p>
        <Link to="/admin">
          <Button variant="secondary">Go to dashboard</Button>
        </Link>
      </div>
    </div>
  );
}