/// Admin control-plane endpoints — every call goes through `client`; the
/// backend permissions remain authoritative (the frontend only renders what the
/// server grants; a 403 surfaces as a readable message, never a hack).
import { client, fetchList, ApiError } from './client';
import type {
  AdminUserRow,
  AdminRoleRow,
  AdminPermissionRow,
  AdminDoctorRow,
  AdminDoctorDecisionRow,
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

/**
 * Full permission catalog (`GET /admin/permissions/`). The role detail
 * endpoint only returns *granted* codes, so without the catalog an operator
 * could never see — let alone grant — a permission a role does not yet hold.
 */
export async function listPermissionCatalog(): Promise<AdminPermissionRow[]> {
  return fetchList<AdminPermissionRow>('/admin/permissions/?page_size=100', AUTH);
}

/** Granted permission codes for one role (the endpoint returns a bare object, not a list). */
export async function listRolePermissions(roleCode: string): Promise<string[]> {
  const payload = await client.request<{ permissions?: string[] }>(
    `/admin/roles/${roleCode}/permissions/`,
    AUTH,
  );
  return Array.isArray(payload?.permissions) ? payload.permissions : [];
}

/**
 * Grant or revoke ONE role↔permission edge. The backend accepts only
 * `POST {permission_code, grant, reason}` (PUT is a 405), so a save applies
 * the diff as a sequence of single-edge posts.
 */
export async function setRolePermission(
  roleCode: string,
  permissionCode: string,
  grant: boolean,
  reason: string,
): Promise<void> {
  await client.request(`/admin/roles/${roleCode}/permissions/`, {
    ...AUTH,
    method: 'POST',
    body: { permission_code: permissionCode, grant, reason },
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

export async function reinstateDoctor(uid: string, reason: string): Promise<void> {
  await client.request(`/admin/doctors/${uid}/reinstate/`, {
    ...AUTH,
    method: 'POST',
    body: { reason },
  });
}

export async function listDoctorDecisions(decision?: string): Promise<AdminDoctorDecisionRow[]> {
  // Plain (unpaginated) list of the newest 200 decisions across the registry.
  return fetchList<AdminDoctorDecisionRow>(
    `/admin/doctors/verification-history/${query({ decision })}`,
    AUTH,
  );
}

export async function listFacilities(opts: { status?: string; query?: string; facilityType?: string } = {}): Promise<AdminFacilityRow[]> {
  // Backend reads `q` + `facility_type` and only accepts status `verified|pending`.
  return fetchList<AdminFacilityRow>(
    `/admin/facilities/${query({
      status: opts.status,
      q: opts.query,
      facility_type: opts.facilityType,
    })}`,
    AUTH,
  );
}

export async function verifyFacility(uid: string, approve: boolean, reason: string): Promise<void> {
  // Registered WITHOUT a trailing slash on the backend (documented asymmetry).
  await client.request(`/admin/facilities/${uid}/verify`, {
    ...AUTH,
    method: 'POST',
    body: { approve, reason },
  });
}

const DOC_TYPE_LABELS: Record<string, string> = {
  CERTIFICATE: 'Certificate',
  NATIONAL_ID: 'National ID',
  FACILITY_REGISTRATION: 'Facility registration',
  LICENSE: 'License',
  OTHER: 'Document',
};

/** Human label for a verification `doc_type` (falls back to the raw code). */
export function verificationDocLabel(docType: string): string {
  return DOC_TYPE_LABELS[docType] ?? docType;
}

/**
 * Open one submitted verification document in a new tab. The file is protected
 * (`GET /admin/verification-documents/{id}/`, `doctors.verify`/`facilities.verify`)
 * and every open is audited server-side, so it is fetched as an authenticated
 * blob rather than linked directly. The blob URL is revoked once the tab has
 * had time to load it.
 */
export async function openVerificationDocument(id: number): Promise<void> {
  const blob = await client.blob(`/admin/verification-documents/${id}/`);
  const url = URL.createObjectURL(blob);
  window.open(url, '_blank', 'noopener,noreferrer');
  window.setTimeout(() => URL.revokeObjectURL(url), 60000);
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

/** Attach or replace an article handout (PDF/PPTX/DOCX/image). */
export async function uploadEducationDocument(uid: string, file: File): Promise<AdminEducationItemRow> {
  const form = new FormData();
  form.append('document', file);
  return client.request<AdminEducationItemRow>(`/admin/education/content/${uid}/document/`, {
    ...AUTH,
    method: 'POST',
    form,
    // A large deck can outlast the default 20s budget on a slow clinic link.
    timeout: 90000,
  });
}

export async function removeEducationDocument(uid: string): Promise<AdminEducationItemRow> {
  return client.request<AdminEducationItemRow>(`/admin/education/content/${uid}/document/`, {
    ...AUTH,
    method: 'DELETE',
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

export type ReportStatus = 'RESOLVED' | 'DISMISSED';
export type ReportAction = 'NONE' | 'HIDE' | 'REMOVE';

/**
 * Resolve a report. The backend requires `status` (RESOLVED|DISMISSED),
 * accepts only `action` ∈ {NONE,HIDE,REMOVE} and demands `review_notes`
 * whenever content is hidden/removed.
 */
export async function resolveCommunityReport(
  id: number,
  status: ReportStatus,
  action: ReportAction,
  reviewNotes: string,
): Promise<void> {
  await client.request(`/admin/community/reports/${id}/resolve/`, {
    ...AUTH,
    method: 'POST',
    body: { status, action, review_notes: reviewNotes },
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
  /** Backend vocabulary: ALL | ROLE | USERS. */
  audience: 'ALL' | 'ROLE' | 'USERS';
  title: string;
  /** Message body — the serializer field is `body`, not `message`. */
  body: string;
  /** Required when audience === 'ROLE'. */
  role_code?: string;
  /** Required when audience === 'USERS' (max 500 recipients). */
  user_uid?: string[];
}

export async function broadcastNotification(payload: BroadcastPayload): Promise<void> {
  await client.request('/admin/notifications/broadcast/', { ...AUTH, method: 'POST', body: payload });
}

// -------------------------------------------------- audit & security

export interface AuditLogQuery {
  [key: string]: string | number | boolean | undefined | null;
  action_code?: string;
  actor?: string;
  resource_type?: string;
  result?: string;
  date_from?: string;
  date_to?: string;
  page?: number;
}

export async function listAuditLogs(opts: AuditLogQuery = {}): Promise<AdminAuditLogRow[]> {
  return fetchList<AdminAuditLogRow>(`/admin/audit-logs/${query(opts)}`, AUTH);
}

/** `GET /admin/audit-logs/export/?reason=` — CSV text (audited, `audit_logs.export`). */
export async function exportAuditLogs(reason: string): Promise<string> {
  return client.request<string>(`/admin/audit-logs/export/${query({ reason })}`, {
    ...AUTH,
    response: 'text',
  });
}

export interface SecurityEventQuery {
  [key: string]: string | number | boolean | undefined | null;
  status?: string;
  event_type?: string;
  user?: string;
  ip?: string;
  date_from?: string;
  date_to?: string;
}

export async function listSecurityEvents(opts: SecurityEventQuery = {}): Promise<AdminSecurityEventRow[]> {
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

/** `GET /admin/analytics/?…&export=csv&reason=` — CSV text, audited server-side. */
export async function exportAnalyticsCsv(
  params: { metric: string; granularity?: string; date_from?: string; date_to?: string },
  reason: string,
): Promise<string> {
  return client.request<string>(`/admin/analytics/${query({ ...params, export: 'csv', reason })}`, {
    ...AUTH,
    response: 'text',
  });
}

// --------------------------------------------------------- content CMS

export async function listNews(
  opts: { status?: string; category?: string; query?: string; pinned?: boolean; includeDeleted?: boolean } = {},
): Promise<AdminNewsRow[]> {
  return fetchList<AdminNewsRow>(
    `/admin/content/news/${query({ ...opts, include_deleted: opts.includeDeleted })}`,
    AUTH,
  );
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

/**
 * Soft delete. The backend archives + unpins the article and keeps the row, so
 * this is reversible via {@link restoreNews} and never destroys content.
 */
export async function deleteNews(uid: string): Promise<void> {
  await client.request(`/admin/content/news/${uid}/`, { ...AUTH, method: 'DELETE' });
}

/** Undo a soft delete; the article returns as a DRAFT for re-review. */
export async function restoreNews(uid: string): Promise<void> {
  await client.request(`/admin/content/news/${uid}/restore/`, { ...AUTH, method: 'POST' });
}

/** Pin/unpin a published article to control its position in the public list. */
export async function setNewsPinned(uid: string, pinned: boolean): Promise<void> {
  const path = pinned ? 'pin' : 'unpin';
  await client.request(`/admin/content/news/${uid}/${path}/`, {
    ...AUTH,
    method: 'POST',
    body: pinned ? { pinned: true } : {},
  });
}

export async function uploadNewsCover(uid: string, file: File, alt = ''): Promise<void> {
  const form = new FormData();
  form.append('image', file);
  if (alt) form.append('alt', alt);
  try {
    await client.request(`/admin/content/news/${uid}/cover/`, { ...AUTH, method: 'POST', form, timeout: 60000 });
  } catch (e) {
    if (e instanceof ApiError && (e.status === 415 || e.status === 400)) {
      throw new ApiError(
        e.status === 415
          ? 'This image type is not supported. Please use PNG, JPEG or WebP.'
          : e.message,
        e.status,
        'UNSUPPORTED_TYPE',
        e.details,
      );
    }
    throw e;
  }
}

export async function listTicker(opts: { active?: boolean } = {}): Promise<AdminTickerRow[]> {
  // Backend filter param is `is_active` (true/false), not `active`.
  return fetchList<AdminTickerRow>(`/admin/content/ticker/${query({ is_active: opts.active })}`, AUTH);
}

export interface TickerDraft {
  message: string;
  announcement_type: string;
  link_url?: string;
  is_active?: boolean;
  priority?: number;
  start_at?: string | null;
  end_at?: string | null;
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

export async function uploadTickerImage(uid: string, file: File, alt = ''): Promise<AdminTickerRow> {
  const form = new FormData();
  form.append('image', file);
  if (alt) form.append('alt', alt);
  return client.request<AdminTickerRow>(`/admin/content/ticker/${uid}/image/`, {
    ...AUTH,
    method: 'POST',
    form,
    timeout: 60000,
  });
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
  const form = new FormData();
  form.append('image', file);
  if (alt) form.append('alt', alt);
  let info: BrandingInfo;
  try {
    info = await client.request<BrandingInfo>('/admin/branding/logo/', {
      ...AUTH,
      method: 'POST',
      form,
      timeout: 60000,
    });
  } catch (e) {
    if (e instanceof ApiError && e.status === 400) {
      throw new ApiError(
        e.message || 'This image is not supported. Use a JPEG, PNG or WebP up to 5 MB.',
        400,
        'INVALID_LOGO',
        e.details,
      );
    }
    throw e;
  }
  return info ?? { logo_url: '/api/branding/logo/', logo_alt: alt, has_logo: true };
}

export async function deleteBrandingLogo(): Promise<void> {
  await client.request('/admin/branding/logo/', { ...AUTH, method: 'DELETE' });
}