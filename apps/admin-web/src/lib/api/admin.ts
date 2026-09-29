/// Admin control-plane endpoints — every call goes through `client`; the
/// backend permissions remain authoritative (the frontend only renders what the
/// server grants; a 403 surfaces as a readable message, never a hack).
import { client, fetchList, ApiError, BASE } from './client';
import type {
  AdminUserRow,
  AdminRoleRow,
  AdminPermissionRow,
  AdminDoctorRow,
  AdminFacilityRow,
  AdminBloodRequestRow,
  AdminCampaignRow,
  AdminEducationItemRow,
  AdminCommunityReportRow,
  AdminDonationRow,
  AdminFinancialSummary,
  AdminAuditLogRow,
  AdminSecurityEventRow,
  AdminNewsRow,
  AdminTickerRow,
  AdminDashboard,
  AdminAnalyticsResponse,
  BrandingInfo,
} from './types';
import { loadSession } from '../auth/session';

const AUTH = { authenticated: true } as const;

function query(params: Record<string, string | number | boolean | undefined | null>): string {
  const sp = new URLSearchParams();
  for (const [k, v] of Object.entries(params)) {
    if (v !== undefined && v !== null && v !== '') sp.set(k, String(v));
  }
  const s = sp.toString();
  return s ? `?${s}` : '';
}

// --------------------------------------------------------- users & roles

export async function listUsers(opts: { status?: string; query?: string; page?: number } = {}) {
  const payload = await client.request<{ results?: AdminUserRow[] }>(
    `/admin/users/${query({ status: opts.status, q: opts.query, page: opts.page })}`,
    AUTH,
  );
  if (payload && Array.isArray((payload as { results?: unknown }).results)) {
    return { rows: (payload as { results: AdminUserRow[] }).results ?? [] };
  }
  return { rows: (Array.isArray(payload) ? payload : []) as AdminUserRow[] };
}

export async function setUserActive(uid: string, active: boolean, reason: string): Promise<void> {
  await client.request(`/admin/users/${uid}/${active ? 'activate' : 'deactivate'}/`, {
    ...AUTH,
    method: 'POST',
    body: { reason },
  });
}

export async function getUserRoles(uid: string): Promise<string[]> {
  const payload = await client.request<{ roles?: string[] }>(`/admin/users/${uid}/roles/`, AUTH);
  return Array.isArray(payload?.roles) ? (payload.roles as string[]) : [];
}

export async function changeUserRole(uid: string, roleCode: string, grant: boolean, reason: string): Promise<void> {
  await client.request(`/admin/users/${uid}/roles/`, {
    ...AUTH,
    method: grant ? 'POST' : 'DELETE',
    body: { role_code: roleCode, reason },
  });
}

export async function listRoles(): Promise<AdminRoleRow[]> {
  return fetchList<AdminRoleRow>('/admin/roles/', AUTH);
}

export async function listRolePermissions(roleCode: string): Promise<AdminPermissionRow[]> {
  return fetchList<AdminPermissionRow>(`/admin/roles/${roleCode}/permissions/`, AUTH);
}

export async function setRolePermissions(roleCode: string, permissionCodes: string[]): Promise<void> {
  await client.request(`/admin/roles/${roleCode}/permissions/`, {
    ...AUTH,
    method: 'PUT',
    body: { permission_codes: permissionCodes },
  });
}

// -------------------------------------------------  verification / orgs

export async function listDoctorQueue(): Promise<AdminDoctorRow[]> {
  return fetchList<AdminDoctorRow>('/admin/doctors/verification-queue/', AUTH);
}

export interface ReviewDecision {
  reason: string;
}

export async function decideDoctor(uid: string, approve: boolean, reason: string): Promise<void> {
  await client.request(`/admin/doctors/${uid}/verify/`, {
    ...AUTH,
    method: 'POST',
    body: { approve, reason },
  });
}

export async function suspendDoctor(uid: string, reason: string): Promise<void> {
  await client.request(`/admin/doctors/${uid}/suspend/`, {
    ...AUTH,
    method: 'POST',
    body: { reason },
  });
}

export async function listFacilities(opts: { status?: string; query?: string; facilityType?: string } = {}): Promise<AdminFacilityRow[]> {
  return fetchList<AdminFacilityRow>(`/admin/facilities/${query(opts)}`, AUTH);
}

export async function verifyFacility(uid: string, approve: boolean, reason: string): Promise<void> {
  // Registered WITHOUT a trailing slash on the backend (documented asymmetry).
  await client.request(`/admin/facilities/${uid}/verify`, {
    ...AUTH,
    method: 'POST',
    body: { approve, reason },
  });
}

export async function listBloodQueue(): Promise<AdminBloodRequestRow[]> {
  return fetchList<AdminBloodRequestRow>('/blood/requests/verification-queue/', AUTH);
}

export async function decideBloodRequest(uid: string, approve: boolean, reason: string): Promise<void> {
  await client.request(`/admin/blood/requests/${uid}/${approve ? 'verify' : 'reject'}/`, {
    ...AUTH,
    method: 'POST',
    body: { reason },
  });
}

export async function listCampaigns(opts: { status?: string } = {}): Promise<AdminCampaignRow[]> {
  return fetchList<AdminCampaignRow>(`/admin/campaigns/${query(opts)}`, AUTH);
}

export async function listCampaignQueue(): Promise<AdminCampaignRow[]> {
  return fetchList<AdminCampaignRow>('/admin/campaigns/verification-queue/', AUTH);
}

export async function decideCampaign(uid: string, approve: boolean, reason: string): Promise<void> {
  await client.request(`/admin/campaigns/${uid}/verify/`, {
    ...AUTH,
    method: 'POST',
    body: { approve, reason },
  });
}

export async function setCampaignStatus(uid: string, status: 'pause' | 'close', reason: string): Promise<void> {
  await client.request(`/admin/campaigns/${uid}/${status}/`, { ...AUTH, method: 'POST', body: { reason } });
}

// --------------------------------------------------------- education

export interface EducationCategoryOption {
  code: string;
  name: string;
}

export async function listEducationCategories(): Promise<EducationCategoryOption[]> {
  return fetchList<EducationCategoryOption>('/education/categories/', { authenticated: false });
}

export async function listEducationContent(opts: { status?: string } = {}): Promise<AdminEducationItemRow[]> {
  return fetchList<AdminEducationItemRow>(`/admin/education/content/${query(opts)}`, AUTH);
}

export async function reviewEducationContent(uid: string, approve: boolean, reason: string): Promise<void> {
  await client.request(`/admin/education/content/${uid}/review/`, {
    ...AUTH,
    method: 'POST',
    body: { decision: approve ? 'approve' : 'reject', reason },
  });
}

export interface EducationDraft {
  title: string;
  body: string;
  category: string;
  cover_url?: string;
}

export async function createEducation(draft: EducationDraft): Promise<AdminEducationItemRow> {
  return client.request<AdminEducationItemRow>('/admin/education/content/', {
    ...AUTH,
    method: 'POST',
    body: draft,
  });
}

export async function updateEducation(uid: string, patch: Partial<EducationDraft>): Promise<AdminEducationItemRow> {
  return client.request<AdminEducationItemRow>(`/admin/education/content/${uid}/`, {
    ...AUTH,
    method: 'PATCH',
    body: patch,
  });
}

export async function publishEducation(uid: string): Promise<void> {
  await client.request(`/admin/education/content/${uid}/publish/`, { ...AUTH, method: 'POST' });
}

export async function deleteEducation(uid: string): Promise<void> {
  await client.request(`/admin/education/content/${uid}/`, { ...AUTH, method: 'DELETE' });
}

// --------------------------------------------------------- community

export async function listCommunityReports(opts: { status?: string } = {}): Promise<AdminCommunityReportRow[]> {
  return fetchList<AdminCommunityReportRow>(`/admin/community/reports/${query(opts)}`, AUTH);
}

export async function resolveCommunityReport(id: number, action: string, reason: string): Promise<void> {
  await client.request(`/admin/community/reports/${id}/resolve/`, {
    ...AUTH,
    method: 'POST',
    body: { action, reason },
  });
}

// -------------------------------------------------- donations & finance

export async function listDonations(): Promise<AdminDonationRow[]> {
  return fetchList<AdminDonationRow>('/admin/donations/', AUTH);
}

export async function refundDonation(uid: string, reason: string): Promise<void> {
  await client.request(`/admin/donations/${uid}/refund/`, { ...AUTH, method: 'POST', body: { reason } });
}

export async function fetchFinancialSummary(): Promise<AdminFinancialSummary> {
  return client.request<AdminFinancialSummary>('/admin/financial/summary/', AUTH);
}

// -------------------------------------------------- notifications

export interface BroadcastPayload {
  audience: string;
  title: string;
  message: string;
}

export async function broadcastNotification(payload: BroadcastPayload): Promise<void> {
  await client.request('/admin/notifications/broadcast/', { ...AUTH, method: 'POST', body: payload });
}

// -------------------------------------------------- audit & security

export async function listAuditLogs(opts: { action?: string; actor?: string; page?: number } = {}): Promise<AdminAuditLogRow[]> {
  return fetchList<AdminAuditLogRow>(`/admin/audit-logs/${query(opts)}`, AUTH);
}

export async function listSecurityEvents(opts: { status?: string } = {}): Promise<AdminSecurityEventRow[]> {
  return fetchList<AdminSecurityEventRow>(`/admin/security-events/${query(opts)}`, AUTH);
}

// ------------------------------------------------------- analytics

export async function fetchDashboard(): Promise<AdminDashboard> {
  return client.request<AdminDashboard>('/admin/dashboard/', AUTH);
}

export async function fetchAnalytics(params: {
  metric: string;
  granularity?: string;
  date_from?: string;
  date_to?: string;
}): Promise<AdminAnalyticsResponse> {
  return client.request<AdminAnalyticsResponse>(`/admin/analytics/${query(params)}`, AUTH);
}

// --------------------------------------------------------- content CMS

export async function listNews(opts: { status?: string; category?: string; query?: string } = {}): Promise<AdminNewsRow[]> {
  return fetchList<AdminNewsRow>(`/admin/content/news/${query(opts)}`, AUTH);
}

export interface NewsDraft {
  title: string;
  category: string;
  body: string;
  excerpt?: string;
  cover_url?: string;
  cover_alt?: string;
  tags?: string[];
}

export async function createNews(draft: NewsDraft): Promise<AdminNewsRow> {
  return client.request<AdminNewsRow>('/admin/content/news/', { ...AUTH, method: 'POST', body: draft });
}

export async function updateNews(uid: string, patch: Partial<NewsDraft>): Promise<AdminNewsRow> {
  return client.request<AdminNewsRow>(`/admin/content/news/${uid}/`, { ...AUTH, method: 'PATCH', body: patch });
}

export type NewsAction = 'publish' | 'unpublish' | 'archive';
export async function setNewsStatus(uid: string, action: NewsAction): Promise<void> {
  await client.request(`/admin/content/news/${uid}/${action}/`, { ...AUTH, method: 'POST' });
}

export async function setNewsFeatured(uid: string, featured: boolean): Promise<void> {
  await client.request(`/admin/content/news/${uid}/feature/`, { ...AUTH, method: 'POST', body: { featured } });
}

export async function deleteNews(uid: string): Promise<void> {
  await client.request(`/admin/content/news/${uid}/`, { ...AUTH, method: 'DELETE' });
}

export async function uploadNewsCover(uid: string, file: File, alt = ''): Promise<void> {
  const session = loadSession();
  const form = new FormData();
  form.append('image', file);
  if (alt) form.append('alt', alt);
  const res = await fetch(`${BASE}/admin/content/news/${uid}/cover/`, {
    method: 'POST',
    headers: session ? { Authorization: `Bearer ${session.access}` } : undefined,
    body: form,
  });
  if (!res.ok) {
    if (res.status === 415 || res.status === 400) {
      throw new ApiError('This image type is not supported. Please use PNG, JPEG or WebP.', res.status, 'UNSUPPORTED_TYPE', {});
    }
    throw new ApiError('Could not upload the cover image. Please try again.', res.status, 'UPLOAD_FAILED', {});
  }
}

export async function listTicker(opts: { active?: boolean } = {}): Promise<AdminTickerRow[]> {
  return fetchList<AdminTickerRow>(`/admin/content/ticker/${query(opts)}`, AUTH);
}

export interface TickerDraft {
  message: string;
  announcement_type: string;
  link_url?: string;
  is_active?: boolean;
  priority?: number;
  start_at?: string;
  end_at?: string;
}

export async function createTicker(draft: TickerDraft): Promise<AdminTickerRow> {
  return client.request<AdminTickerRow>('/admin/content/ticker/', { ...AUTH, method: 'POST', body: draft });
}

export async function updateTicker(uid: string, patch: Partial<TickerDraft>): Promise<AdminTickerRow> {
  return client.request<AdminTickerRow>(`/admin/content/ticker/${uid}/`, { ...AUTH, method: 'PATCH', body: patch });
}

export async function setTickerActive(uid: string, active: boolean): Promise<void> {
  await client.request(`/admin/content/ticker/${uid}/${active ? 'activate' : 'deactivate'}/`, {
    ...AUTH,
    method: 'POST',
  });
}

export async function deleteTicker(uid: string): Promise<void> {
  await client.request(`/admin/content/ticker/${uid}/`, { ...AUTH, method: 'DELETE' });
}

// ------------------------------------------------------------ branding

export async function fetchBrandingInfo(): Promise<BrandingInfo> {
  return client.request<BrandingInfo>('/branding/');
}

export async function fetchAdminBranding(): Promise<BrandingInfo> {
  return client.request<BrandingInfo>('/admin/branding/', AUTH);
}

export async function updateBrandingAlt(logoAlt: string): Promise<BrandingInfo> {
  return client.request<BrandingInfo>('/admin/branding/', {
    ...AUTH,
    method: 'PATCH',
    body: { logo_alt: logoAlt },
  });
}

export async function uploadBrandingLogo(file: File, alt = ''): Promise<BrandingInfo> {
  const session = loadSession();
  const form = new FormData();
  form.append('image', file);
  if (alt) form.append('alt', alt);
  const res = await fetch(`${BASE}/admin/branding/logo/`, {
    method: 'POST',
    headers: session ? { Authorization: `Bearer ${session.access}` } : undefined,
    body: form,
  });
  if (res.status === 400) {
    throw new ApiError('This image is not supported. Use a JPEG, PNG or WebP up to 5 MB.', res.status, 'INVALID_LOGO', {});
  }
  if (!res.ok) {
    throw new ApiError('Could not upload the logo. Please try again.', res.status, 'UPLOAD_FAILED', {});
  }
  let info: BrandingInfo | null = null;
  try {
    const body = (await res.json()) as { data?: BrandingInfo };
    info = body.data ?? null;
  } catch {
    // envelope parse best-effort
  }
  return info ?? { logo_url: '/api/branding/logo/', logo_alt: alt, has_logo: true };
}

export async function deleteBrandingLogo(): Promise<void> {
  await client.request('/admin/branding/logo/', { ...AUTH, method: 'DELETE' });
}