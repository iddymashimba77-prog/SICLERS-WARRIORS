import { Navigate, Route, Routes } from 'react-router-dom';
import { useAuth } from './lib/auth/AuthContext';
import { AdminShell } from './components/layout/AdminShell';
import { LoadingState } from './components/ui';
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

export function AppRoutes() {
  return (
    <Routes>
      <Route path="/" element={<Navigate to="/admin" replace />} />
      <Route path="/admin/login" element={<LoginPage />} />
      <Route path="/admin" element={<RequireAuth />}>
        <Route index element={<DashboardPage />} />
        <Route path="users" element={<UsersPage />} />
        <Route path="roles" element={<RolesPermissionsPage />} />
        <Route path="verification/doctors" element={<DoctorsVerificationPage />} />
        <Route path="verification/organizations" element={<OrganizationsVerificationPage />} />
        <Route path="verification/blood" element={<BloodVerificationPage />} />
        <Route path="verification/campaigns" element={<CampaignsVerificationPage />} />
        <Route path="content/news" element={<NewsPage />} />
        <Route path="content/ticker" element={<TickerPage />} />
        <Route path="content/education" element={<EducationContentPage />} />
        <Route path="donations" element={<DonationsPage />} />
        <Route path="finance" element={<FinancePage />} />
        <Route path="community" element={<ModerationPage />} />
        <Route path="notifications" element={<NotificationsPage />} />
        <Route path="analytics" element={<AnalyticsPage />} />
        <Route path="audit-logs" element={<AuditLogsPage />} />
        <Route path="security-events" element={<SecurityEventsPage />} />
        <Route path="settings" element={<SettingsPage />} />
        <Route path="branding" element={<BrandingPage />} />
        <Route path="features" element={<GapPage feature="Feature Flags" />} />
        <Route path="admin-accounts" element={<GapPage feature="Admin Accounts" />} />
        <Route path="*" element={<NotFoundPage />} />
      </Route>
      <Route path="*" element={<NotFoundPage />} />
    </Routes>
  );
}