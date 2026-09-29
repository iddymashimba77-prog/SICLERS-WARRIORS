/// Approved Stage 4.8 API client for `/api/blood/*`.
///
/// Mirrors the approved database-design rows (`blood_donors`, `blood_requests`,
/// `blood_matches`, `blood_donation_events`) and the endpoint matrix §12/§20.
///
/// Privacy (BR-005/BR-006): public donor payloads **never** carry contact
/// details or PHI. Verification, matching and permission checks are enforced
/// server-side; this client never asserts authority, it only renders it.
library;

import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../core/constants/app_config.dart';
import '../../auth/data/token_store.dart';
import '../../auth/domain/auth_types.dart';

/// Recipient blood groups accepted by the matching surface (authoritative
/// vocabulary from the approved database design).
const List<String> bloodGroups = [
  'A+',
  'A-',
  'B+',
  'B-',
  'AB+',
  'AB-',
  'O+',
  'O-',
];

const List<String> bloodUrgencies = ['NORMAL', 'URGENT', 'CRITICAL'];

/// Non-contact donor projection (BR-006).
class PublicDonor {
  const PublicDonor({
    required this.id,
    required this.bloodGroup,
    required this.region,
    required this.city,
    required this.isAvailable,
    required this.isVerified,
    required this.donationCount,
    this.lastDonationDate,
  });

  factory PublicDonor.fromJson(Map<String, dynamic> json) => PublicDonor(
        id: (json['id'] as num?)?.toInt() ?? 0,
        bloodGroup: (json['blood_group'] as String?) ?? '',
        region: (json['region'] as String?) ?? '',
        city: (json['city'] as String?) ?? '',
        isAvailable: (json['is_available'] as bool?) ?? false,
        isVerified: (json['is_verified'] as bool?) ?? false,
        donationCount: (json['donation_count'] as num?)?.toInt() ?? 0,
        lastDonationDate: json['last_donation_date'] as String?,
      );

  final int id;
  final String bloodGroup;
  final String region;
  final String city;
  final bool isAvailable;
  final bool isVerified;
  final int donationCount;
  final String? lastDonationDate;
}

/// Donor's own profile (blood_donors.self_manage, BLD).
class BloodDonorProfile {
  const BloodDonorProfile({
    required this.id,
    required this.bloodGroup,
    required this.region,
    required this.city,
    required this.isAvailable,
    required this.isVerified,
    required this.donationCount,
    this.lastDonationDate,
  });

  factory BloodDonorProfile.fromJson(Map<String, dynamic> json) =>
      BloodDonorProfile(
        id: (json['id'] as num?)?.toInt() ?? 0,
        bloodGroup: (json['blood_group'] as String?) ?? '',
        region: (json['region'] as String?) ?? '',
        city: (json['city'] as String?) ?? '',
        isAvailable: (json['is_available'] as bool?) ?? false,
        isVerified: (json['is_verified'] as bool?) ?? false,
        donationCount: (json['donation_count'] as num?)?.toInt() ?? 0,
        lastDonationDate: json['last_donation_date'] as String?,
      );

  final int id;
  final String bloodGroup;
  final String region;
  final String city;
  final bool isAvailable;
  final bool isVerified;
  final int donationCount;
  final String? lastDonationDate;

  BloodDonorProfile copyWith({bool? isAvailable}) => BloodDonorProfile(
        id: id,
        bloodGroup: bloodGroup,
        region: region,
        city: city,
        isAvailable: isAvailable ?? this.isAvailable,
        isVerified: isVerified,
        donationCount: donationCount,
        lastDonationDate: lastDonationDate,
      );

  Map<String, dynamic> toJson() => {
        'blood_group': bloodGroup,
        'region': region,
        'city': city,
        'is_available': isAvailable,
      };
}

/// A verified, donor-facing blood request (C8) or the owner's full row.
class BloodRequest {
  const BloodRequest({
    required this.uid,
    required this.bloodGroupNeeded,
    required this.units,
    required this.urgency,
    required this.status,
    required this.reason,
    required this.location,
    required this.facilityName,
    required this.facilityUid,
    this.createdAt,
  });

  factory BloodRequest.fromJson(Map<String, dynamic> json) {
    final facility = json['facility'] as Map<String, dynamic>?;
    return BloodRequest(
      uid: (json['uid'] as String?) ?? '',
      bloodGroupNeeded: (json['blood_group_needed'] as String?) ?? '',
      units: (json['units'] as num?)?.toInt() ?? 1,
      urgency: (json['urgency'] as String?) ?? 'NORMAL',
      status: (json['status'] as String?) ?? '',
      reason: (json['reason'] as String?) ?? '',
      location: (json['location'] as String?) ?? '',
      facilityName: (facility?['name'] as String?) ?? '',
      facilityUid: (facility?['uid'] as String?) ?? '',
      createdAt: json['created_at'] as String?,
    );
  }

  final String uid;
  final String bloodGroupNeeded;
  final int units;
  final String urgency;
  final String status;
  final String reason;
  final String location;
  final String facilityName;
  final String facilityUid;
  final String? createdAt;

  bool get isOpen => const [
        'PENDING_VERIFICATION',
        'ACTIVE',
        'MATCHING',
        'MATCHED',
      ].contains(status);
}

/// A match between a request and a donor (donor is always non-contact).
class BloodMatch {
  const BloodMatch({
    required this.id,
    required this.requestUid,
    required this.donor,
    required this.matchScore,
    required this.matchReason,
    required this.status,
  });

  factory BloodMatch.fromJson(Map<String, dynamic> json) => BloodMatch(
        id: (json['id'] as num?)?.toInt() ?? 0,
        requestUid: (json['request_uid'] as String?) ?? '',
        donor: PublicDonor.fromJson(
          (json['donor'] as Map<String, dynamic>?) ?? const {},
        ),
        matchScore: ((json['match_score'] as num?) ?? 0).toDouble(),
        matchReason: (json['match_reason'] as String?) ?? '',
        status: (json['status'] as String?) ?? '',
      );

  final int id;
  final String requestUid;
  final PublicDonor donor;
  final double matchScore;
  final String matchReason;
  final String status;

  bool get awaitingResponse =>
      status == 'SUGGESTED' || status == 'NOTIFIED';
}

/// Client for the approved blood-network endpoints.
class BloodRepository {
  BloodRepository({required this.tokenStore, http.Client? client})
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

  Future<List<BloodRequest>> listRequests({required String access}) async {
    final res = await _client
        .get(_uri(['blood', 'requests']), headers: _headers(access))
        .timeout(_timeout);
    return _listPayload(res)
        .map((e) => BloodRequest.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<BloodRequest> getRequest({
    required String access,
    required String uid,
  }) async {
    final res = await _client
        .get(_uri(['blood', 'requests', uid]), headers: _headers(access))
        .timeout(_timeout);
    return BloodRequest.fromJson(_body(res));
  }

  Future<BloodRequest> createRequest({
    required String access,
    required String bloodGroupNeeded,
    required int units,
    required String urgency,
    String reason = '',
    String location = '',
    String? facilityUid,
    String? idempotencyKey,
  }) async {
    final key = idempotencyKey ??
        'blood-${DateTime.now().microsecondsSinceEpoch}';
    final res = await _client
        .post(
          _uri(['blood', 'requests']),
          headers: {..._headers(access), 'Idempotency-Key': key},
          body: jsonEncode({
            'blood_group_needed': bloodGroupNeeded,
            'units': units,
            'urgency': urgency,
            'reason': reason,
            'location': location,
            if (facilityUid != null && facilityUid.isNotEmpty)
              'facility_uid': facilityUid,
            'idempotency_key': key,
          }),
        )
        .timeout(_timeout);
    return BloodRequest.fromJson(_body(res));
  }

  Future<BloodRequest> cancelRequest({
    required String access,
    required String uid,
    String reason = '',
  }) async {
    final res = await _client
        .post(
          _uri(['blood', 'requests', uid, 'cancel']),
          headers: _headers(access),
          body: jsonEncode({'reason': reason}),
        )
        .timeout(_timeout);
    return BloodRequest.fromJson(_body(res));
  }

  Future<List<BloodMatch>> listMatches({
    required String access,
    required String requestUid,
  }) async {
    final res = await _client
        .get(
          _uri(['blood', 'requests', requestUid, 'matches']),
          headers: _headers(access),
        )
        .timeout(_timeout);
    return _listPayload(res)
        .map((e) => BloodMatch.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<BloodMatch> respondToMatch({
    required String access,
    required int matchId,
    required bool accept,
  }) async {
    final res = await _client
        .post(
          _uri(['blood', 'matches', '$matchId', 'respond']),
          headers: _headers(access),
          body: jsonEncode({'action': accept ? 'ACCEPT' : 'DECLINE'}),
        )
        .timeout(_timeout);
    return BloodMatch.fromJson(_body(res));
  }

  /// GET own donor profile; returns `null` when the profile does not exist yet.
  Future<BloodDonorProfile?> getDonorProfile({
    required String access,
  }) async {
    final res = await _client
        .get(_uri(['blood', 'donors', 'me']), headers: _headers(access))
        .timeout(_timeout);
    if (res.statusCode == 404) return null;
    return BloodDonorProfile.fromJson(_body(res));
  }

  Future<BloodDonorProfile> saveDonorProfile({
    required String access,
    required String bloodGroup,
    required String region,
    required String city,
    required bool isAvailable,
  }) async {
    final res = await _client
        .patch(
          _uri(['blood', 'donors', 'me']),
          headers: _headers(access),
          body: jsonEncode({
            'blood_group': bloodGroup,
            'region': region,
            'city': city,
            'is_available': isAvailable,
          }),
        )
        .timeout(_timeout);
    return BloodDonorProfile.fromJson(_body(res));
  }
}
