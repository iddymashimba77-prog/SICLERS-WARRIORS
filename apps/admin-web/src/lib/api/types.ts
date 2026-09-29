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

export interface AdminDoctorRow {
  uid: string;
  email: string;
  display_name: string;
  specialty: string;
  license_number: string;
  registration_body: string;
  facility_uid?: string;
  verification_status: string;
  verified_at?: string;
  rejection_reason?: string;
  created_at?: string;
  submitted_at?: string;
}

export interface AdminFacilityRow {
  uid: string;
  name: string;
  operator_email: string;
  operator_uid?: string;
  facility_type: string;
  phone?: string;
  address?: string;
  city?: string;
  verification_status: string;
  is_verified?: boolean;
  created_at?: string;
  submitted_at?: string;
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
}

export interface AdminCommunityReportRow {
  id: number;
  reporter?: string;
  target_type?: string;
  target_id?: string;
  reason?: string;
  status: string;
  detailed_reason?: string;
  created_at?: string;
}

export interface AdminDonationRow {
  uid: string;
  donor_email?: string;
  amount: number;
  currency: string;
  status: string;
  provider?: string;
  campaign_title?: string;
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
  actor?: { email?: string; display_name?: string } | null;
  action: string;
  resource_type?: string;
  resource_id?: string;
  reason?: string;
  result?: string;
  ip_address?: string;
  created_at?: string;
  details?: unknown;
}

export interface AdminSecurityEventRow {
  id: number;
  event_type: string;
  status: string;
  actor?: { email?: string } | null;
  ip_address?: string;
  reason?: string;
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
  status: string;
  author?: { display_name?: string } | null;
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
  created_at?: string;
}

export interface AdminDashboard {
  generated_at: string;
  role_kernel: string;
  kpis: Record<string, number>;
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
  updated_by?: { id: number; full_name: string } | null;
}

export interface Me extends MeUser {}