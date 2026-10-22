/// Typed projections of the backend admin serializers. Field names and shape
/// mirror the backend exactly (same contracts the Flutter admin portal parses).
import type { MeUser } from '../auth/session';

export interface AdminUserRow {
  uid: string;
  email: string;
  phone?: string;
  full_name?: string;
  account_status: string;
  role_codes: string[];
  mfa_enabled?: boolean;
  created_at?: string;
  verification_status?: string;
}

export interface AdminUserDetail extends AdminUserRow {
  is_verified_doctor?: boolean;
  doctor_verification_status?: string;
  facility?: { name?: string; type?: string; status?: string } | null;
  permission_codes?: string[];
}

export interface AdminRoleRow {
  code: string;
  name: string;
  is_system?: boolean;
  permission_count?: number;
  member_count?: number;
  description?: string;
}

export interface AdminPermissionRow {
  code: string;
  name: string;
  description?: string;
}

export interface AdminVerificationDocument {
  /** Handle for `GET /admin/verification-documents/{id}/` (audited stream). */
  id: number;
  doc_type: string;
  status: string;
  file_name?: string;
  uploaded_at?: string;
  reviewed_at?: string | null;
}

export interface AdminDoctorRow {
  uid: string;
  email: string;
  display_name: string;
  specialty: string;
  license_number: string;
  registration_body: string;
  /** Which profession the applicant claims: DOCTOR | PSYCHOLOGIST | SOCIAL_SUPPORT. */
  professional_type: string;
  facility_uid?: string;
  verification_status: string;
  verified_at?: string;
  rejection_reason?: string;
  created_at?: string;
  submitted_at?: string;
  verification_documents?: AdminVerificationDocument[];
}

export interface AdminDoctorDecisionRow {
  uid: string;
  doctor_uid: string;
  license_number: string;
  decision: string;
  from_status: string;
  to_status: string;
  reason: string;
  actor_name: string;
  decided_at: string;
}

export interface AdminFacilityRow {
  uid: string;
  name: string;
  operator_email: string;
  operator_uid?: string;
  facility_type: string;
  region?: string;
  city?: string;
  address?: string;
  registration_number?: string;
  /** `FacilityAdminSerializer` exposes `is_verified` — there is no `verification_status`. */
  is_verified?: boolean;
  verified_at?: string | null;
  created_at?: string;
  /** Submitted-attachment summary (`FacilityAdminSerializer.verification_documents`). */
  verification_documents?: AdminVerificationDocument[];
}

export interface AdminBloodRequestRow {
  uid: string;
  blood_group_needed: string;
  units: number;
  urgency: string;
  location?: string;
  reason?: string;
  status: string;
  creator_email?: string;
  rejection_reason?: string;
  created_at?: string;
  facility?: { name?: string; type?: string; status?: string } | null;
}

export interface AdminCampaignRow {
  uid: string;
  title: string;
  description?: string;
  goal_amount: number;
  raised_amount: number;
  currency: string;
  status: string;
  progress?: number;
  rejection_reason?: string;
  created_at?: string;
  owner?: { display_name?: string; email?: string } | null;
}

export interface AdminEducationItemRow {
  uid: string;
  title: string;
  body?: string;
  cover_url?: string;
  category?: { code?: string; name?: string } | null;
  author?: { display_name?: string } | null;
  status: string;
  created_at?: string;
  document_url?: string | null;
  document_name?: string;
  document_content_type?: string;
  document_size?: number | null;
}

export interface AdminCommunityReportRow {
  id: number;
  /** `AuthorBriefSerializer` — an object, not a bare string. */
  reporter?: { uid?: string; display_name?: string } | null;
  target_type?: string;
  target_id?: string;
  target_preview?: string;
  target_exists?: boolean;
  reason?: string;
  status: string;
  review_notes?: string;
  created_at?: string;
}

export interface AdminDonationRow {
  uid: string;
  /** `AdminDonationSerializer.donor_display` (never a raw email field). */
  donor_display?: string;
  amount: number;
  currency: string;
  status: string;
  provider?: string;
  campaign_title?: string;
  is_refunded?: boolean;
  created_at?: string;
}

export interface AdminFinancialSummary {
  confirmed_donations_total?: number;
  confirmed_donations_count?: number;
  refunded_total?: number;
  pending_donations_count?: number;
  active_campaigns_count?: number;
  closed_campaigns_count?: number;
  verified_campaigns_count?: number;
  last_updated?: string | null;
}

export interface AdminAuditLogRow {
  id: number;
  actor_email?: string;
  action_code: string;
  resource_type?: string;
  resource_id?: string | number;
  result?: string;
  ip_address?: string;
  request_id?: string;
  created_at?: string;
}

export interface AdminSecurityEventRow {
  id: number;
  user_uid?: string;
  user_email?: string;
  event_type: string;
  status: string;
  ip_address?: string;
  user_agent?: string;
  detail?: Record<string, unknown>;
  created_at?: string;
}

export interface AdminNewsRow {
  uid: string;
  title: string;
  category: string;
  category_label?: string;
  excerpt: string;
  body: string;
  cover_url: string;
  cover_alt: string;
  tags: string[];
  featured: boolean;
  /** Editorial override that floats the article to the top of the public list. */
  pinned?: boolean;
  pinned_at?: string | null;
  status: string;
  author?: { display_name?: string } | null;
  /** Soft delete — the row is retained and restorable, never destroyed. */
  deleted_at?: string | null;
  deleted_by_uid?: string | null;
  published_at?: string | null;
  created_at?: string;
}

export interface AdminTickerRow {
  uid: string;
  message: string;
  announcement_type: string;
  announcement_type_label?: string;
  link_url: string;
  is_active: boolean;
  priority: number;
  start_at?: string | null;
  end_at?: string | null;
  image_url?: string | null;
  image_alt?: string;
  created_at?: string;
}

export interface AdminDashboard {
  generated_at: string;
  role_kernel: string;
  kpis: Record<string, number>;
  /** 'live' = computed for this request; 'snapshot' = last aggregation run. */
  kpi_sources?: Record<string, 'live' | 'snapshot'>;
  trends?: Record<string, { measured_at?: string; date?: string; value?: number }[]>;
}

export interface AdminAnalyticsResponse {
  metric?: string;
  granularity?: string;
  results?: { measured_at?: string; period?: string; value?: number; dimensions?: unknown }[];
  count?: number;
}

export interface AdminMfaStatus {
  mfa_enabled: boolean;
}

export interface BrandingInfo {
  logo_url: string;
  logo_alt: string;
  has_logo: boolean;
  updated_at?: string;
  logo_version?: string;
  updated_by?: { id: number; full_name: string } | null;
}

export interface Me extends MeUser {}