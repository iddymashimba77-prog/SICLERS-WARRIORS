import type { ReactNode } from 'react';
import { Navigate, Route, Routes, useLocation } from 'react-router-dom';
import { useAuth } from './lib/auth/AuthContext';
import { navSectionsFor } from './lib/nav';
import { AdminShell } from './components/layout/AdminShell';
import { Button, LoadingState } from './components/ui';
import { LoginPage } from './pages/LoginPage';
import { DashboardPage } from './pages/DashboardPage';
import { UsersPage } from './pages/UsersPage';
import { RolesPermissionsPage } from './pages/RolesPermissionsPage';
import { DoctorsVerificationPage } from './pages/DoctorsVerificationPage';
import { OrganizationsVerificationPage } from './pages/OrganizationsVerificationPage';
import { BloodVerificationPage } from './pages/BloodVerificationPage';
import { CampaignsVerificationPage } from './pages/CampaignsVerificationPage';
import { NewsPage } from './pages/NewsPage';
import { TickerPage } from './pages/TickerPage';
import { EducationContentPage } from './pages/EducationContentPage';
import { DonationsPage } from './pages/DonationsPage';
import { FinancePage } from './pages/FinancePage';
import { ModerationPage } from './pages/ModerationPage';
import { NotificationsPage } from './pages/NotificationsPage';
import { AnalyticsPage } from './pages/AnalyticsPage';
import { AuditLogsPage } from './pages/AuditLogsPage';
import { SecurityEventsPage } from './pages/SecurityEventsPage';
import { SettingsPage } from './pages/SettingsPage';
import { BrandingPage } from './pages/BrandingPage';
import { GapPage } from './pages/GapPage';
import { DeniedPage, NotFoundPage } from './pages/StatusPages';

function RequireAuth() {
  const { status, isReady } = useAuth();
  if (!isReady) {
    return (
      <div style={{ minHeight: '100vh', display: 'grid', placeItems: 'center' }}>
        <LoadingState label="Checking session…" />
      </div>
    );
  }
  if (status === 'signedIn') return <AdminShell />;
  if (status === 'denied') return <DeniedPage />;
  return <Navigate to="/admin/login" replace />;
}

/** In-shell "you cannot see this page" state (the full-screen DeniedPage is
 *  reserved for non-admin principals at sign-in). */
function RouteDenied() {
  const location = useLocation();
  return (
    <div className="sw-empty" style={{ border: 'none', minHeight: '60vh' }}>
      <div className="sw-empty-ico">!</div>
      <h2>Access denied</h2>
      <p>
        Your role does not include the permission this page requires
        (<code>{location.pathname}</code>). Ask an administrator to grant it, or
        head back to the dashboard.
      </p>
      <Button variant="secondary" onClick={() => window.location.assign('/admin')}>
        Go to dashboard
      </Button>
    </div>
  );
}

/**
 * Per-route permission gate. Navigation already hides links the session cannot
 * use, but a bookmarked or hand-typed URL must not reach a page whose backend
 * calls would all 403. Backend authorization is unchanged — this is UX only.
 */
function RequirePerm({
  anyOf,
  superOnly,
  children,
}: {
  anyOf?: string[];
  superOnly?: boolean;
  children: ReactNode;
}) {
  const { status, isReady, hasAnyPerm, isSuper } = useAuth();
  if (!isReady) {
    return (
      <div style={{ minHeight: '60vh', display: 'grid', placeItems: 'center' }}>
        <LoadingState label="Checking permissions…" />
      </div>
    );
  }
  if (status !== 'signedIn') return <Navigate to="/admin/login" replace />;
  if (superOnly) return isSuper ? <>{children}</> : <RouteDenied />;
  if (!anyOf || anyOf.length === 0 || hasAnyPerm(anyOf)) return <>{children}</>;
  return <RouteDenied />;
}

/** The dashboard needs `analytics.view`; operators without it land on the
 *  first section their role does allow instead of a dead end. */
function DashboardRoute() {
  const { status, isReady, user, isSuper, hasPerm } = useAuth();
  if (!isReady || status !== 'signedIn') return null;
  if (hasPerm('analytics.view')) return <DashboardPage />;
  const first = (user ? navSectionsFor(user, isSuper) : [])
    .flatMap((s) => s.links)[0];
  if (first) return <Navigate to={`/admin/${first.segment}`} replace />;
  return <RouteDenied />;
}

export function AppRoutes() {
  return (
    <Routes>
      <Route path="/" element={<Navigate to="/admin" replace />} />
      <Route path="/admin/login" element={<LoginPage />} />
      <Route path="/admin" element={<RequireAuth />}>
        <Route index element={<DashboardRoute />} />
        <Route
          path="users"
          element={<RequirePerm anyOf={['admin.users.manage']}><UsersPage /></RequirePerm>}
        />
        <Route
          path="roles"
          element={
            <RequirePerm anyOf={['admin.roles.manage', 'admin.permissions.manage']}>
              <RolesPermissionsPage />
            </RequirePerm>
          }
        />
        <Route
          path="verification/doctors"
          element={<RequirePerm anyOf={['doctors.verify']}><DoctorsVerificationPage /></RequirePerm>}
        />
        <Route
          path="verification/organizations"
          element={<RequirePerm anyOf={['facilities.verify']}><OrganizationsVerificationPage /></RequirePerm>}
        />
        <Route
          path="verification/blood"
          element={<RequirePerm anyOf={['blood_requests.verify']}><BloodVerificationPage /></RequirePerm>}
        />
        <Route
          path="verification/campaigns"
          element={<RequirePerm anyOf={['campaigns.verify']}><CampaignsVerificationPage /></RequirePerm>}
        />
        <Route
          path="content/news"
          element={<RequirePerm anyOf={['content.news.manage']}><NewsPage /></RequirePerm>}
        />
        <Route
          path="content/ticker"
          element={<RequirePerm anyOf={['content.ticker.manage']}><TickerPage /></RequirePerm>}
        />
        <Route
          path="content/education"
          element={<RequirePerm anyOf={['education.review']}><EducationContentPage /></RequirePerm>}
        />
        <Route
          path="donations"
          element={<RequirePerm anyOf={['donations.view']}><DonationsPage /></RequirePerm>}
        />
        <Route
          path="finance"
          element={<RequirePerm anyOf={['donations.view']}><FinancePage /></RequirePerm>}
        />
        <Route
          path="community"
          element={<RequirePerm anyOf={['community.moderate']}><ModerationPage /></RequirePerm>}
        />
        <Route
          path="notifications"
          element={<RequirePerm anyOf={['notifications.broadcast']}><NotificationsPage /></RequirePerm>}
        />
        <Route
          path="analytics"
          element={<RequirePerm anyOf={['analytics.view']}><AnalyticsPage /></RequirePerm>}
        />
        <Route
          path="audit-logs"
          element={<RequirePerm anyOf={['audit_logs.view']}><AuditLogsPage /></RequirePerm>}
        />
        <Route
          path="security-events"
          element={<RequirePerm anyOf={['admin.audit.read']}><SecurityEventsPage /></RequirePerm>}
        />
        <Route path="settings" element={<RequirePerm superOnly><SettingsPage /></RequirePerm>} />
        <Route
          path="branding"
          element={<RequirePerm anyOf={['admin.branding.manage']}><BrandingPage /></RequirePerm>}
        />
        <Route path="features" element={<RequirePerm superOnly><GapPage feature="Feature Flags" /></RequirePerm>} />
        <Route path="admin-accounts" element={<RequirePerm superOnly><GapPage feature="Admin Accounts" /></RequirePerm>} />
        <Route path="*" element={<NotFoundPage />} />
      </Route>
      <Route path="*" element={<NotFoundPage />} />
    </Routes>
  );
}