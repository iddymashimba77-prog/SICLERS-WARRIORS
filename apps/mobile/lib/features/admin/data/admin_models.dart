/// Typed projections for the ADMIN-3 data layer.
///
/// Field names and shapes mirror the backend admin serializers exactly
/// (`backend/accounts/admin_serializers.py`, `donations/serializers.py`,
/// `facilities/serializers.py`, `education/serializers.py`,
/// `community/serializers.py`, `audit/serializers.py`). Parsing is defensive:
/// backend values are never trusted to be non-null.
library;

/// Money/amounts arrive as Decimals (strings) or numbers.
double _toDouble(dynamic value) {
  if (value is num) return value.toDouble();
  return double.tryParse('$value') ?? 0;
}

int _toInt(dynamic value) {
  if (value is num) return value.toInt();
  return int.tryParse('$value') ?? 0;
}

String _str(dynamic value) => value == null ? '' : '$value';

class AdminUser {
  const AdminUser({
    required this.uid,
    required this.email,
    required this.accountStatus,
    this.phone = '',
    this.fullName = '',
    this.roleCodes = const [],
    this.mfaEnabled = false,
    this.createdAt,
  });

  factory AdminUser.fromJson(Map<String, dynamic> json) => AdminUser(
        uid: _str(json['uid']),
        email: _str(json['email']),
        phone: _str(json['phone']),
        fullName: _str(json['full_name']),
        accountStatus: _str(json['account_status']),
        roleCodes: [...?(json['role_codes'] as List?)?.cast<String>()],
        mfaEnabled: json['mfa_enabled'] == true,
        createdAt: json['created_at'] as String?,
      );

  final String uid;
  final String email;
  final String phone;
  final String fullName;
  final String accountStatus;
  final List<String> roleCodes;
  final bool mfaEnabled;
  final String? createdAt;

  bool get isActive => accountStatus == 'ACTIVE';
}

class AdminRole {
  const AdminRole({
    required this.code,
    required this.name,
    this.isSystem = false,
    this.permissionCount = 0,
    this.memberCount = 0,
  });

  factory AdminRole.fromJson(Map<String, dynamic> json) => AdminRole(
        code: _str(json['code']),
        name: _str(json['name']),
        isSystem: json['is_system'] == true,
        permissionCount: _toInt(json['permission_count']),
        memberCount: _toInt(json['member_count']),
      );

  final String code;
  final String name;
  final bool isSystem;
  final int permissionCount;
  final int memberCount;
}

class AdminDoctor {
  const AdminDoctor({
    required this.uid,
    required this.email,
    required this.verificationStatus,
    this.fullName = '',
    this.specialty = '',
    this.licenseNumber = '',
    this.facilityUid = '',
    this.registrationBody = '',
    this.verifiedAt,
    this.rejectionReason = '',
    this.createdAt,
  });

  factory AdminDoctor.fromJson(Map<String, dynamic> json) => AdminDoctor(
        uid: _str(json['uid']),
        email: _str(json['email']),
        fullName: _str(json['display_name']),
        specialty: _str(json['specialty']),
        licenseNumber: _str(json['license_number']),
        registrationBody: _str(json['registration_body']),
        facilityUid: _str(json['facility_uid']),
        verificationStatus: _str(json['verification_status']),
        verifiedAt: json['verified_at'] as String?,
        rejectionReason: _str(json['rejection_reason']),
        createdAt: json['created_at'] as String?,
      );

  final String uid;
  final String email;
  final String fullName;
  final String specialty;
  final String licenseNumber;
  final String registrationBody;
  final String facilityUid;
  final String verificationStatus;
  final String? verifiedAt;
  final String rejectionReason;
  final String? createdAt;
}

class AdminFacility {
  const AdminFacility({
    required this.uid,
    required this.name,
    this.operatorEmail = '',
    this.operatorUid = '',
    this.facilityType = '',
    this.phone = '',
    this.address = '',
    this.city = '',
    this.verificationStatus = '',
    this.isVerified = false,
    this.createdAt,
  });

  factory AdminFacility.fromJson(Map<String, dynamic> json) => AdminFacility(
        uid: _str(json['uid']),
        name: _str(json['name']),
        operatorEmail: _str(json['operator_email']),
        operatorUid: _str(json['operator_uid']),
        facilityType: _str(json['facility_type']),
        phone: _str(json['phone']),
        address: _str(json['address']),
        city: _str(json['city']),
        verificationStatus: _str(json['verification_status']),
        isVerified: json['is_verified'] == true,
        createdAt: json['created_at'] as String?,
      );

  final String uid;
  final String name;
  final String operatorEmail;
  final String operatorUid;
  final String facilityType;
  final String phone;
  final String address;
  final String city;
  final String verificationStatus;
  final bool isVerified;
  final String? createdAt;
}

class AdminBloodRequest {
  const AdminBloodRequest({
    required this.uid,
    required this.bloodGroupNeeded,
    required this.urgency,
    required this.status,
    this.units = 0,
    this.facilityName = '',
    this.location = '',
    this.reason = '',
    this.creatorEmail = '',
    this.rejectionReason = '',
    this.createdAt,
  });

  factory AdminBloodRequest.fromJson(Map<String, dynamic> json) {
    final facility = json['facility'] as Map<String, dynamic>?;
    return AdminBloodRequest(
      uid: _str(json['uid']),
      bloodGroupNeeded: _str(json['blood_group_needed']),
      units: _toInt(json['units']),
      urgency: _str(json['urgency']),
      facilityName: _str(facility?['name']),
      location: _str(json['location']),
      reason: _str(json['reason']),
      status: _str(json['status']),
      creatorEmail: _str(json['creator_email']),
      rejectionReason: _str(json['rejection_reason']),
      createdAt: json['created_at'] as String?,
    );
  }

  final String uid;
  final String bloodGroupNeeded;
  final int units;
  final String urgency;
  final String facilityName;
  final String location;
  final String reason;
  final String status;
  final String creatorEmail;
  final String rejectionReason;
  final String? createdAt;
}

class AdminCampaign {
  const AdminCampaign({
    required this.uid,
    required this.title,
    required this.status,
    this.goalAmount = 0,
    this.raisedAmount = 0,
    this.currency = 'TZS',
    this.progress = 0,
    this.ownerName = '',
    this.description = '',
    this.rejectionReason = '',
    this.createdAt,
  });

  factory AdminCampaign.fromJson(Map<String, dynamic> json) {
    final owner = json['owner'] as Map<String, dynamic>?;
    return AdminCampaign(
      uid: _str(json['uid']),
      title: _str(json['title']),
      description: _str(json['description']),
      goalAmount: _toDouble(json['goal_amount']),
      raisedAmount: _toDouble(json['raised_amount']),
      currency: _str(json['currency']),
      status: _str(json['status']),
      progress: _toDouble(json['progress']),
      ownerName: _str(owner?['display_name']),
      rejectionReason: _str(json['rejection_reason']),
      createdAt: json['created_at'] as String?,
    );
  }

  final String uid;
  final String title;
  final String description;
  final double goalAmount;
  final double raisedAmount;
  final String currency;
  final String status;
  final double progress;
  final String ownerName;
  final String rejectionReason;
  final String? createdAt;
}

class AdminContent {
  const AdminContent({
    required this.uid,
    required this.title,
    required this.status,
    this.body = '',
    this.categoryName = '',
    this.authorName = '',
    this.rejectionReason = '',
    this.publishedAt,
    this.createdAt,
  });

  factory AdminContent.fromJson(Map<String, dynamic> json) {
    final category = json['category'] as Map<String, dynamic>?;
    final author = json['author'] as Map<String, dynamic>?;
    return AdminContent(
      uid: _str(json['uid']),
      title: _str(json['title']),
      body: _str(json['body']),
      categoryName: _str(category?['name']),
      authorName: _str(author?['display_name']),
      status: _str(json['status']),
      rejectionReason: _str(json['rejection_reason']),
      publishedAt: json['published_at'] as String?,
      createdAt: json['created_at'] as String?,
    );
  }

  final String uid;
  final String title;
  final String body;
  final String categoryName;
  final String authorName;
  final String status;
  final String rejectionReason;
  final String? publishedAt;
  final String? createdAt;
}

class AdminReport {
  const AdminReport({
    required this.id,
    required this.targetType,
    required this.reason,
    required this.status,
    this.targetId = '',
    this.targetPreview = '',
    this.targetExists = true,
    this.reporterName = '',
    this.reviewNotes = '',
    this.createdAt,
  });

  factory AdminReport.fromJson(Map<String, dynamic> json) {
    final reporter = json['reporter'] as Map<String, dynamic>?;
    return AdminReport(
      id: _toInt(json['id']),
      targetType: _str(json['target_type']),
      targetId: _str(json['target_id']),
      reason: _str(json['reason']),
      status: _str(json['status']),
      targetPreview: _str(json['target_preview']),
      targetExists: json['target_exists'] != false,
      reporterName: _str(reporter?['display_name']),
      reviewNotes: _str(json['review_notes']),
      createdAt: json['created_at'] as String?,
    );
  }

  final int id;
  final String targetType;
  final String targetId;
  final String reason;
  final String status;
  final String targetPreview;
  final bool targetExists;
  final String reporterName;
  final String reviewNotes;
  final String? createdAt;
}

class AdminDonation {
  const AdminDonation({
    required this.uid,
    required this.amount,
    required this.currency,
    required this.status,
    this.displayStatus = '',
    this.campaignTitle = '',
    this.donorName = '',
    this.isRefunded = false,
    this.createdAt,
  });

  factory AdminDonation.fromJson(Map<String, dynamic> json) {
    final campaign = json['campaign'] as Map<String, dynamic>?;
    return AdminDonation(
      uid: _str(json['uid']),
      amount: _toDouble(json['amount']),
      currency: _str(json['currency']),
      status: _str(json['status']),
      displayStatus: _str(json['display_status']),
      campaignTitle: _str(campaign?['title']),
      donorName: _str(json['donor_display']),
      isRefunded: json['is_refunded'] == true,
      createdAt: json['created_at'] as String?,
    );
  }

  final String uid;
  final double amount;
  final String currency;
  final String status;
  final String displayStatus;
  final String campaignTitle;
  final String donorName;
  final bool isRefunded;
  final String? createdAt;

  bool get isConfirmed => status == 'COMPLETED';
}

class AdminFinancialSummary {
  const AdminFinancialSummary({
    this.confirmedDonationsTotal = 0,
    this.confirmedDonationsCount = 0,
    this.refundedTotal = 0,
    this.pendingDonationsCount = 0,
    this.activeCampaignsCount = 0,
    this.closedCampaignsCount = 0,
    this.verifiedCampaignsCount = 0,
    this.lastUpdated,
  });

  factory AdminFinancialSummary.fromJson(Map<String, dynamic> json) =>
      AdminFinancialSummary(
        confirmedDonationsTotal: _toDouble(json['confirmed_donations_total']),
        confirmedDonationsCount: _toInt(json['confirmed_donations_count']),
        refundedTotal: _toDouble(json['refunded_total']),
        pendingDonationsCount: _toInt(json['pending_donations_count']),
        activeCampaignsCount: _toInt(json['active_campaigns_count']),
        closedCampaignsCount: _toInt(json['closed_campaigns_count']),
        verifiedCampaignsCount: _toInt(json['verified_campaigns_count']),
        lastUpdated: json['last_updated'] as String?,
      );

  final double confirmedDonationsTotal;
  final int confirmedDonationsCount;
  final double refundedTotal;
  final int pendingDonationsCount;
  final int activeCampaignsCount;
  final int closedCampaignsCount;
  final int verifiedCampaignsCount;
  final String? lastUpdated;
}

class AdminAuditLog {
  const AdminAuditLog({
    required this.id,
    required this.actionCode,
    required this.result,
    this.actorEmail = '',
    this.resourceType = '',
    this.resourceId = '',
    this.ipAddress = '',
    this.requestId = '',
    this.createdAt,
  });

  factory AdminAuditLog.fromJson(Map<String, dynamic> json) {
    return AdminAuditLog(
      id: _toInt(json['id']),
      actorEmail: _str(json['actor_email']),
      actionCode: _str(json['action_code']),
      resourceType: _str(json['resource_type']),
      resourceId: _str(json['resource_id']),
      result: _str(json['result']),
      ipAddress: _str(json['ip_address']),
      requestId: _str(json['request_id']),
      createdAt: json['created_at'] as String?,
    );
  }

  final int id;
  final String actorEmail;
  final String actionCode;
  final String resourceType;
  final String resourceId;
  final String result;
  final String ipAddress;
  final String requestId;
  final String? createdAt;
}

class SecurityEvent {
  const SecurityEvent({
    required this.id,
    required this.eventType,
    required this.status,
    this.userEmail = '',
    this.userUid = '',
    this.ipAddress = '',
    this.userAgent = '',
    this.detail = const {},
    this.createdAt,
  });

  factory SecurityEvent.fromJson(Map<String, dynamic> json) {
    final user = json['user'] as Map<String, dynamic>?;
    return SecurityEvent(
      id: _toInt(json['id']),
      userUid: _str(user?['uid']),
      userEmail: _str(user?['email'] ?? json['user_email']),
      eventType: _str(json['event_type']),
      status: _str(json['status']),
      ipAddress: _str(json['ip_address']),
      userAgent: _str(json['user_agent']),
      detail: (json['detail'] as Map<String, dynamic>?) ?? const {},
      createdAt: json['created_at'] as String?,
    );
  }

  final int id;
  final String userUid;
  final String userEmail;
  final String eventType;
  final String status;
  final String ipAddress;
  final String userAgent;
  final Map<String, dynamic> detail;
  final String? createdAt;
}

class AiUsageAction {
  const AiUsageAction({required this.actionCode, required this.count});

  factory AiUsageAction.fromJson(Map<String, dynamic> json) => AiUsageAction(
        actionCode: _str(json['action_code']),
        count: _toInt(json['count']),
      );

  final String actionCode;
  final int count;
}

class AiMonitoring {
  const AiMonitoring({
    this.windowDays = 30,
    this.totalEvents = 0,
    this.successes = 0,
    this.failures = 0,
    this.denied = 0,
    this.safetyBlocks = 0,
    this.providerFailures = 0,
    this.usageDenied = 0,
    this.uniqueUsers = 0,
    this.byAction = const [],
  });

  factory AiMonitoring.fromJson(Map<String, dynamic> json) => AiMonitoring(
        windowDays: _toInt(json['window_days']) == 0 ? 30 : _toInt(json['window_days']),
        totalEvents: _toInt(json['total_events']),
        successes: _toInt(json['successes']),
        failures: _toInt(json['failures']),
        denied: _toInt(json['denied']),
        safetyBlocks: _toInt(json['safety_blocks']),
        providerFailures: _toInt(json['provider_failures']),
        usageDenied: _toInt(json['usage_denied']),
        uniqueUsers: _toInt(json['unique_users']),
        byAction: [
          for (final row in (json['by_action'] as List? ?? const []))
            if (row is Map<String, dynamic>) AiUsageAction.fromJson(row),
        ],
      );

  final int windowDays;
  final int totalEvents;
  final int successes;
  final int failures;
  final int denied;
  final int safetyBlocks;
  final int providerFailures;
  final int usageDenied;
  final int uniqueUsers;
  final List<AiUsageAction> byAction;
}

class AdminDashboard {
  const AdminDashboard({
    this.generatedAt,
    this.roleKernel = '',
    this.kpis = const {},
    this.trends = const {},
  });

  factory AdminDashboard.fromJson(Map<String, dynamic> json) => AdminDashboard(
        generatedAt: json['generated_at'] as String?,
        roleKernel: _str(json['role_kernel']),
        kpis: (json['kpis'] as Map<String, dynamic>?) ?? const {},
        trends: (json['trends'] as Map<String, dynamic>?) ?? const {},
      );

  final String? generatedAt;
  final String roleKernel;
  final Map<String, dynamic> kpis;
  final Map<String, dynamic> trends;

  int intKpi(String key) => _toInt(kpis[key]);

  double doubleKpi(String key) => _toDouble(kpis[key]);

  int trendCurrentInt(String key) {
    final trend = trends[key];
    if (trend is Map<String, dynamic>) return _toInt(trend['current']);
    return 0;
  }

  int trendNewInt(String key) {
    final trend = trends[key];
    if (trend is Map<String, dynamic>) return _toInt(trend['new']);
    return 0;
  }
}

class AnalyticsResult {
  const AnalyticsResult({
    required this.metric,
    required this.granularity,
    this.rows = const [],
  });

  factory AnalyticsResult.fromJson(Map<String, dynamic> json) => AnalyticsResult(
        metric: _str(json['metric']),
        granularity: _str(json['granularity']),
        rows: [
          for (final row in (json['results'] as List? ?? const []))
            if (row is Map<String, dynamic>) AnalyticsRow.fromJson(row),
        ],
      );

  final String metric;
  final String granularity;
  final List<AnalyticsRow> rows;
}

class AnalyticsRow {
  const AnalyticsRow({required this.value, this.label = '', this.dimensions = const {}});

  factory AnalyticsRow.fromJson(Map<String, dynamic> json) => AnalyticsRow(
        value: _toDouble(json['value']),
        label: _str(json['period'] ?? json['measured_at'] ?? ''),
        dimensions: (json['dimensions'] as Map<String, dynamic>?) ?? const {},
      );

  final double value;
  final String label;
  final Map<String, dynamic> dimensions;
}

class AdminBroadcastResult {
  const AdminBroadcastResult({this.audience = '', this.recipientCount = 0});

  factory AdminBroadcastResult.fromJson(Map<String, dynamic> json) =>
      AdminBroadcastResult(
        audience: _str(json['audience']),
        recipientCount: _toInt(json['recipient_count']),
      );

  final String audience;
  final int recipientCount;
}
// =================================================== content CMS (news/ticker)

/// News article as seen by the content CMS (`/api/admin/content/news/`).
class AdminNewsArticle {
  const AdminNewsArticle({
    required this.uid,
    required this.title,
    required this.status,
    this.category = '',
    this.categoryLabel = '',
    this.excerpt = '',
    this.body = '',
    this.coverUrl = '',
    this.coverAlt = '',
    this.tags = const [],
    this.featured = false,
    this.authorName = '',
    this.publishedAt,
    this.createdAt,
  });

  factory AdminNewsArticle.fromJson(Map<String, dynamic> json) =>
      AdminNewsArticle(
        uid: _str(json['uid']),
        title: _str(json['title']),
        category: _str(json['category']),
        categoryLabel: _str(json['category_label']),
        excerpt: _str(json['excerpt']),
        body: _str(json['body']),
        coverUrl: _str(json['cover_url']),
        coverAlt: _str(json['cover_alt']),
        tags: [...?(json['tags'] as List?)?.map((t) => '$t')],
        featured: json['featured'] == true,
        status: _str(json['status']),
        authorName: _str((json['author'] as Map<String, dynamic>?)?['display_name']),
        publishedAt: json['published_at'] as String?,
        createdAt: json['created_at'] as String?,
      );

  final String uid;
  final String title;
  final String category;
  final String categoryLabel;
  final String excerpt;
  final String body;
  final String coverUrl;
  final String coverAlt;
  final List<String> tags;
  final bool featured;
  final String status;
  final String authorName;
  final String? publishedAt;
  final String? createdAt;
}

/// Ticker announcement as seen by the content CMS (`/api/admin/content/ticker/`).
class AdminTickerAnnouncement {
  const AdminTickerAnnouncement({
    required this.uid,
    required this.message,
    required this.type,
    this.typeLabel = '',
    this.linkUrl = '',
    this.isActive = false,
    this.priority = 0,
    this.startAt,
    this.endAt,
    this.createdAt,
  });

  factory AdminTickerAnnouncement.fromJson(Map<String, dynamic> json) =>
      AdminTickerAnnouncement(
        uid: _str(json['uid']),
        message: _str(json['message']),
        type: _str(json['announcement_type']),
        typeLabel: _str(json['announcement_type_label']),
        linkUrl: _str(json['link_url']),
        isActive: json['is_active'] == true,
        priority: _toInt(json['priority']),
        startAt: json['start_at'] as String?,
        endAt: json['end_at'] as String?,
        createdAt: json['created_at'] as String?,
      );

  final String uid;
  final String message;
  final String type;
  final String typeLabel;
  final String linkUrl;
  final bool isActive;
  final int priority;
  final String? startAt;
  final String? endAt;
  final String? createdAt;
}
