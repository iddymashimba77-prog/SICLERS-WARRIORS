import { useNavigate } from 'react-router-dom';
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
  const navigate = useNavigate();
  return (
    <div className="sw-empty" style={{ minHeight: '100vh', display: 'grid', placeItems: 'center', border: 'none' }}>
      <div style={{ maxWidth: 440 }}>
        <div className="sw-empty-ico">◌</div>
        <h2>Page not found</h2>
        <p>The page you are looking for does not exist in this application.</p>
        <Button variant="secondary" onClick={() => navigate('/admin')}>
          Go to dashboard
        </Button>
      </div>
    </div>
  );
}