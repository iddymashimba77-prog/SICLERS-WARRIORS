import { useEffect, useState } from 'react';
import { NavLink, Outlet, useLocation, useNavigate, Link, useMatch } from 'react-router-dom';
import { navSectionsFor, type NavSection } from '../../lib/nav';
import { useAuth } from '../../lib/auth/AuthContext';
import { useBranding } from '../../lib/BrandingContext';
import { useTheme } from '../../lib/theme';
import { Button } from '../ui';
import './styles.css';

function Brand({ compact = false }: { compact?: boolean }) {
  const { logoUrl, info } = useBranding();
  return (
    <div className="sw-brand">
      <img
        src={logoUrl}
        alt={info?.logo_alt || "Sickler's Warriors logo"}
        className="sw-brand-img"
      />
      {!compact ? (
        <div className="sw-brand-text">
          <strong>Sickler's Warriors</strong>
          <span>Admin Panel</span>
        </div>
      ) : null}
    </div>
  );
}

function SidebarBody({ sections, pathname, onNavigate }: { sections: NavSection[]; pathname: string; onNavigate?: () => void }) {
  return (
    <nav className="sw-side-nav" aria-label="Admin sections">
      {sections.map((group) => (
        <div className="sw-nav-group" key={group.title}>
          <div className="sw-nav-title">{group.title}</div>
          {group.links.map((link) => {
            const active =
              link.segment === ''
                ? pathname === '/admin' || pathname === '/admin/'
                : pathname.endsWith(`/admin/${link.segment}`) || pathname.startsWith(`/admin/${link.segment}/`);
            return (
              <NavLink
                key={link.segment}
                to={`/admin/${link.segment}`}
                end={link.segment === ''}
                className={({ isActive }) => (isActive || active ? 'sw-nav-link is-active' : 'sw-nav-link')}
                onClick={onNavigate}
              >
                <span className="sw-nav-dot" aria-hidden="true" />
                {link.label}
              </NavLink>
            );
          })}
        </div>
      ))}
      {sections.length === 0 ? (
        <p className="sw-nav-empty">No sections available for this account.</p>
      ) : null}
    </nav>
  );
}

export function AdminShell() {
  const { logout, user, isSuper, hasPerm } = useAuth();
  const { isDark, setMode } = useTheme();
  const location = useLocation();
  const navigate = useNavigate();
  const [drawer, setDrawer] = useState(false);
  const [alertsOpen, setAlertsOpen] = useState(false);
  const [profileOpen, setProfileOpen] = useState(false);

  useEffect(() => {
    setDrawer(false);
  }, [location.pathname]);

  useEffect(() => {
    function close(e: MouseEvent) {
      const t = e.target as HTMLElement;
      if (!t.closest('.sw-top-alerts') && !t.closest('.sw-top-profile')) {
        setAlertsOpen(false);
        setProfileOpen(false);
      }
    }
    document.addEventListener('click', close);
    return () => document.removeEventListener('click', close);
  }, []);

  const sec = useMatch('/admin/:section/*');
  const sections = user ? navSectionsFor(user, isSuper) : [];
  const canBroadcast = hasPerm('notifications.broadcast');

  async function onLogout() {
    await logout();
    navigate('/admin/login', { replace: true });
  }

  return (
    <div className="sw-shell">
      <header className="sw-topbar">
        <button
          type="button"
          className="sw-iconbtn sw-menu-btn"
          aria-label="Open menu"
          onClick={() => setDrawer(true)}
        >
          ☰
        </button>
        <Brand compact />
        <div className="sw-top-title" aria-hidden="true">
          {sec?.params.section ? sec.params.section.replace(/-/g, ' ') : 'Dashboard'}
        </div>
        <div className="sw-top-actions">
          <button
            type="button"
            className="sw-iconbtn"
            aria-label={isDark ? 'Switch to light mode' : 'Switch to dark mode'}
            title={isDark ? 'Light mode' : 'Dark mode'}
            onClick={() => setMode(isDark ? 'light' : 'dark')}
          >
            {isDark ? '☀️' : '🌙'}
          </button>
          <a className="sw-top-link" href="/" target="_blank" rel="noreferrer">
            Public site
          </a>
          <div className="sw-top-alerts sw-drop-wrap">
            <button
              type="button"
              className="sw-iconbtn"
              aria-label="Notifications"
              aria-haspopup="true"
              aria-expanded={alertsOpen}
              onClick={() => {
                setAlertsOpen((v) => !v);
                setProfileOpen(false);
              }}
            >
              🔔
            </button>
            {alertsOpen ? (
              <div className="sw-drop" role="menu">
                {canBroadcast ? (
                  <p className="sw-drop-msg">
                    Messages to users are sent from the <Link to="/admin/notifications">Notifications</Link>{' '}
                    page. No fake alerts are shown.
                  </p>
                ) : (
                  <p className="sw-drop-msg">No alerts available for this account.</p>
                )}
              </div>
            ) : null}
          </div>
          <div className="sw-top-profile sw-drop-wrap">
            <button
              type="button"
              className="sw-user-chip"
              aria-haspopup="true"
              aria-expanded={profileOpen}
              onClick={() => {
                setProfileOpen((v) => !v);
                setAlertsOpen(false);
              }}
            >
              <span className="sw-user-avatar" aria-hidden="true">
                {(user?.full_name || user?.email || 'A').charAt(0).toUpperCase()}
              </span>
              <span className="sw-user-meta">
                <strong>{user?.full_name || user?.email}</strong>
                <small>{user?.role_codes?.join(', ') || 'Admin'}</small>
              </span>
            </button>
            {profileOpen ? (
              <div className="sw-drop" role="menu">
                <div className="sw-drop-id">
                  <strong>{user?.full_name || user?.email}</strong>
                  <span>{user?.email}</span>
                  <span className="sw-chip" style={{ alignSelf: 'flex-start' }}>
                    {user?.account_status || 'ACTIVE'}
                  </span>
                </div>
                <button type="button" role="menuitem" className="sw-drop-item" onClick={onLogout}>
                  Sign out
                </button>
              </div>
            ) : null}
          </div>
        </div>
      </header>

      {drawer ? (
        <div className="sw-drawer-backdrop" onClick={() => setDrawer(false)}>
          <aside className="sw-drawer" onClick={(e) => e.stopPropagation()}>
            <div className="sw-drawer-head">
              <Brand />
              <button type="button" className="sw-iconbtn" aria-label="Close menu" onClick={() => setDrawer(false)}>
                ×
              </button>
            </div>
            <SidebarBody sections={sections} pathname={location.pathname} onNavigate={() => setDrawer(false)} />
            <div className="sw-drawer-foot">
              <Button variant="secondary" onClick={onLogout}>
                Sign out
              </Button>
            </div>
          </aside>
        </div>
      ) : null}

      <aside className="sw-sidebar" aria-label="Admin navigation">
        <Brand />
        <SidebarBody sections={sections} pathname={location.pathname} />
        <div className="sw-sidebar-foot">
          <Button variant="secondary" onClick={onLogout} className="sw-logout-btn">
            Sign out
          </Button>
        </div>
      </aside>

      <main className="sw-main">
        <Outlet />
      </main>
    </div>
  );
}