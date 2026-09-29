/// Approved Stage 4.12 API client for `/api/campaigns`, `/api/donations` and
/// `/api/payments`.
///
/// Mirrors the approved database-design rows (`campaigns`,
/// `payment_transactions`, `refunds`) and endpoint matrix §13 (DON-001..008).
///
/// Deny by default: campaign detail is only visible when public (ACTIVE/CLOSED)
/// or owned; donation history is donor-only unless the caller holds
/// `donations.view`; receipts exist only once a donation is COMPLETED.
/// Creation is rate-limited (10/hour/user, per-campaign burst 2/min) and
/// idempotent via the `Idempotency-Key` header (BR-008).
library;

import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../core/constants/app_config.dart';
import '../../auth/data/token_store.dart';
import '../../auth/domain/auth_types.dart';

double _toDouble(dynamic value) {
  if (value is num) return value.toDouble();
  return double.tryParse('$value') ?? 0;
}

const List<String> donationProviders = [
  'M_PESA',
  'AIRTEL',
  'TIGO',
  'CLICKPESA',
  'SELCOM',
];

/// Public verified-campaign projection (FR-CAM-003, DON-001).
class Campaign {
  const Campaign({
    required this.uid,
    required this.title,
    required this.currency,
    required this.status,
    required this.progress,
    this.description = '',
    this.goalAmount = 0,
    this.raisedAmount = 0,
    this.ownerName = '',
    this.createdAt,
  });

  factory Campaign.fromJson(Map<String, dynamic> json) {
    final owner = json['owner'] as Map<String, dynamic>?;
    return Campaign(
      uid: (json['uid'] as String?) ?? '',
      title: (json['title'] as String?) ?? '',
      description: (json['description'] as String?) ?? '',
      goalAmount: _toDouble(json['goal_amount']),
      raisedAmount: _toDouble(json['raised_amount']),
      currency: (json['currency'] as String?) ?? 'TZS',
      status: (json['status'] as String?) ?? '',
      progress: _toDouble(json['progress']),
      ownerName: (owner?['display_name'] as String?) ?? '',
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
  final String? createdAt;

  bool get isActive => status == 'ACTIVE';
}

/// Donor donation detail + latest transaction (FR-CAM-004/005, DON-006/007).
class Donation {
  const Donation({
    required this.uid,
    required this.amount,
    required this.currency,
    required this.status,
    required this.displayStatus,
    required this.transactionRef,
    this.campaignUid = '',
    this.campaignTitle = '',
    this.provider = '',
    this.providerRef = '',
    this.redactedRef = '',
    this.attempt = 0,
    this.latestTransactionId,
    this.createdAt,
  });

  factory Donation.fromJson(Map<String, dynamic> json) {
    final campaign = json['campaign'] as Map<String, dynamic>?;
    final txn = json['latest_transaction'] as Map<String, dynamic>?;
    return Donation(
      uid: (json['uid'] as String?) ?? '',
      amount: _toDouble(json['amount']),
      currency: (json['currency'] as String?) ?? 'TZS',
      status: (json['status'] as String?) ?? '',
      displayStatus: (json['display_status'] as String?) ?? '',
      transactionRef: (json['transaction_ref'] as String?) ?? '',
      campaignUid: (campaign?['uid'] as String?) ?? '',
      campaignTitle: (campaign?['title'] as String?) ?? '',
      provider: (txn?['provider'] as String?) ?? '',
      providerRef: (txn?['provider_ref'] as String?) ?? '',
      redactedRef: (txn?['redacted_ref'] as String?) ?? '',
      attempt: (txn?['attempt'] as int?) ?? 0,
      latestTransactionId: txn?['id'],
      createdAt: json['created_at'] as String?,
    );
  }

  final String uid;
  final double amount;
  final String currency;
  final String status;
  final String displayStatus;
  final String transactionRef;
  final String campaignUid;
  final String campaignTitle;
  final String provider;
  final String providerRef;
  final String redactedRef;
  final int attempt;
  final int? latestTransactionId;
  final String? createdAt;

  bool get isInitiated => status == 'PENDING';

  bool get isConfirmed => status == 'COMPLETED';

  bool get canRetry => status == 'PENDING' || status == 'FAILED';
}

/// Donor-only receipt (FR-CAM-006, DON-008).
class DonationReceipt {
  const DonationReceipt({
    required this.receiptNumber,
    required this.donationUid,
    required this.campaignTitle,
    required this.amount,
    required this.currency,
    required this.status,
    required this.transactionRef,
    this.donatedAt,
  });

  factory DonationReceipt.fromJson(Map<String, dynamic> json) =>
      DonationReceipt(
        receiptNumber: (json['receipt_number'] as String?) ?? '',
        donationUid: (json['donation_uid'] as String?) ?? '',
        campaignTitle: (json['campaign_title'] as String?) ?? '',
        amount: _toDouble(json['amount']),
        currency: (json['currency'] as String?) ?? 'TZS',
        status: (json['status'] as String?) ?? '',
        transactionRef: (json['transaction_ref'] as String?) ?? '',
        donatedAt: json['donated_at'] as String?,
      );

  final String receiptNumber;
  final String donationUid;
  final String campaignTitle;
  final double amount;
  final String currency;
  final String status;
  final String transactionRef;
  final String? donatedAt;
}

/// Client for the approved campaigns/donations/payments endpoints.
class DonationsRepository {
  DonationsRepository({required this.tokenStore, http.Client? client})
      : _client = client ?? http.Client();

  final TokenStore tokenStore;
  final http.Client _client;

  static const _timeout = Duration(seconds: 15);

  Uri _uri(List<String> segments) => Uri.parse(
        '${AppConfig.apiBaseUrl}/${segments.join('/')}/',
      );

  Map<String, String> _headers(String access) => {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        'Authorization': 'Bearer $access',
      };

  AuthException _errorFrom(http.Response res, String body) {
    try {
      final map = jsonDecode(body) as Map<String, dynamic>;
      final err = map['error'] as Map<String, dynamic>? ?? const {};
      final details = (err['details'] as Map<String, dynamic>?) ?? const {};
      final fieldErrors = <String, List<String>>{};
      details.forEach((field, msgs) {
        fieldErrors[field] = [for (final m in msgs is List ? msgs : [msgs]) '$m'];
      });
      return AuthException(
        (err['message'] as String?) ?? 'Request failed.',
        code: (err['code'] as String?) ?? 'API_ERROR',
        statusCode: res.statusCode,
        fieldErrors: fieldErrors,
      );
    } catch (_) {
      return AuthException(
        res.statusCode >= 500
            ? 'Server error. Please try again shortly.'
            : 'Request failed (${res.statusCode}).',
        code: 'API_ERROR',
        statusCode: res.statusCode,
      );
    }
  }

  Map<String, dynamic> _body(http.Response res) {
    if (res.statusCode >= 400) throw _errorFrom(res, res.body);
    final map = jsonDecode(res.body) as Map<String, dynamic>;
    return (map['data'] as Map<String, dynamic>?) ?? map;
  }

  List<dynamic> _listPayload(http.Response res) {
    final payload = _body(res);
    final results = payload['results'];
    if (results is List) return results;
    return const [];
  }

  Future<List<Campaign>> listCampaigns({
    required String access,
    String? query,
  }) async {
    final uri = _uri(['campaigns']).replace(
      queryParameters: (query == null || query.isEmpty)
          ? null
          : {'q': query},
    );
    final res = await _client.get(uri, headers: _headers(access)).timeout(_timeout);
    return _listPayload(res)
        .map((e) => Campaign.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<Campaign> getCampaign({
    required String access,
    required String uid,
  }) async {
    final res = await _client
        .get(_uri(['campaigns', uid]), headers: _headers(access))
        .timeout(_timeout);
    return Campaign.fromJson(_body(res));
  }

  Future<Donation> initiateDonation({
    required String access,
    required String campaignUid,
    required double amount,
    required String provider,
    String? idempotencyKey,
  }) async {
    final key = idempotencyKey ?? 'don-${DateTime.now().microsecondsSinceEpoch}';
    final res = await _client
        .post(
          _uri(['donations']),
          headers: {..._headers(access), 'Idempotency-Key': key},
          body: jsonEncode({
            'campaign_uid': campaignUid,
            'amount': amount,
            'currency': 'TZS',
            'provider': provider,
          }),
        )
        .timeout(_timeout);
    return Donation.fromJson(_body(res));
  }

  Future<List<Donation>> listDonations({
    required String access,
    String? campaignUid,
  }) async {
    final uri = _uri(['donations']).replace(
      queryParameters: (campaignUid == null || campaignUid.isEmpty)
          ? null
          : {'campaign_uid': campaignUid},
    );
    final res = await _client.get(uri, headers: _headers(access)).timeout(_timeout);
    return _listPayload(res)
        .map((e) => Donation.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<Donation> getDonation({
    required String access,
    required String uid,
  }) async {
    final res = await _client
        .get(_uri(['donations', uid]), headers: _headers(access))
        .timeout(_timeout);
    return Donation.fromJson(_body(res));
  }

  Future<DonationReceipt> getReceipt({
    required String access,
    required String uid,
  }) async {
    final res = await _client
        .get(_uri(['donations', uid, 'receipt']), headers: _headers(access))
        .timeout(_timeout);
    return DonationReceipt.fromJson(_body(res));
  }

  /// Re-submits the latest transaction for a PENDING/FAILED donation (DON-006).
  /// Returns the refreshed donation by re-fetching it after the retry.
  Future<Donation> retryDonation({
    required String access,
    required String donationUid,
  }) async {
    final donation = await getDonation(access: access, uid: donationUid);
    final txnId = donation.latestTransactionId;
    if (txnId == null || !donation.canRetry) {
      throw AuthException(
        'Payments can only be retried while pending or failed.',
        code: 'INVALID_RETRY',
        statusCode: 400,
      );
    }
    await _client
        .post(
          _uri(['payments', '$txnId', 'retry']),
          headers: _headers(access),
          body: '{}',
        )
        .timeout(_timeout);
    return getDonation(access: access, uid: donationUid);
  }
}