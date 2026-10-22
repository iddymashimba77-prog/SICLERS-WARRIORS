/// Permission-gated navigation, mirroring the mobile portal's
/// `adminSectionsFor`. The sidebar only renders what the session holds; the
/// backend re-enforces every call regardless.
import type { MeUser } from './auth/session';

export interface NavLink {
  label: string;
  segment: string; // relative route segment under /admin
  perm?: string; // permission code (any-of ORs handled via cond)
}

export interface NavSection {
  title: string;
  links: NavLink[];
}

export function navSectionsFor(user: MeUser, isSuper: boolean): NavSection[] {
  const perms = user?.permission_codes ?? [];
  const has = (code: string) => perms.includes(code);

  const sections: NavSection[] = [];

  const overview: NavLink[] = [];
  if (has('analytics.view')) overview.push({ label: 'Dashboard', segment: '' });
  if (has('admin.users.manage'))
    overview.push({ label: 'Users', segment: 'users', perm: 'admin.users.manage' });
  if (overview.length) sections.push({ title: 'Overview', links: overview });

  const governance: NavLink[] = [];
  if (has('admin.roles.manage') || has('admin.permissions.manage'))
    governance.push({ label: 'Roles & Permissions', segment: 'roles' });
  if (has('admin.audit.read')) governance.push({ label: 'Security Events', segment: 'security-events' });
  if (has('audit_logs.view')) governance.push({ label: 'Audit Logs', segment: 'audit-logs' });
  if (governance.length) sections.push({ title: 'Governance', links: governance });

  const verification: NavLink[] = [];
  if (has('doctors.verify')) verification.push({ label: 'Verification', segment: 'verification/doctors' });
  if (has('facilities.verify'))
    verification.push({ label: 'Organizations', segment: 'verification/organizations' });
  if (has('blood_requests.verify'))
    verification.push({ label: 'Blood Requests', segment: 'verification/blood' });
  if (has('campaigns.verify')) verification.push({ label: 'Campaigns', segment: 'verification/campaigns' });
  if (verification.length) sections.push({ title: 'Verification', links: verification });

  const content: NavLink[] = [];
  if (has('content.news.manage')) content.push({ label: 'News', segment: 'content/news' });
  if (has('content.ticker.manage')) content.push({ label: 'Announcements', segment: 'content/ticker' });
  if (has('education.review')) content.push({ label: 'Education', segment: 'content/education' });
  if (content.length) sections.push({ title: 'Content', links: content });

  const finance: NavLink[] = [];
  if (has('donations.view')) {
    finance.push({ label: 'Donations', segment: 'donations' });
    finance.push({ label: 'Financial Summary', segment: 'finance' });
  }
  if (finance.length) sections.push({ title: 'Finance', links: finance });

  const community: NavLink[] = [];
  if (has('community.moderate')) community.push({ label: 'Moderation', segment: 'community' });
  if (has('notifications.broadcast'))
    community.push({ label: 'Notifications', segment: 'notifications' });
  if (community.length) sections.push({ title: 'Community & Comms', links: community });

  const insights: NavLink[] = [];
  if (has('analytics.view')) insights.push({ label: 'Analytics', segment: 'analytics' });
  if (insights.length) sections.push({ title: 'Insights', links: insights });

  const platform: NavLink[] = [];
  if (has('admin.branding.manage') || isSuper) {
    platform.push({ label: 'Branding', segment: 'branding', perm: 'admin.branding.manage' });
  }
  if (isSuper) {
    platform.push({ label: 'Settings', segment: 'settings' });
    platform.push({ label: 'Feature Flags', segment: 'features' });
    platform.push({ label: 'Admin Accounts', segment: 'admin-accounts' });
  }
  if (platform.length) sections.push({ title: 'Platform', links: platform });

  return sections;
}