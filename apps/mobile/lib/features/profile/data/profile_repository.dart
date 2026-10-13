import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

import '../../../core/constants/app_config.dart';
import '../../auth/data/token_store.dart';
import '../../auth/domain/auth_types.dart';

/// Detects an image type from its magic bytes.
///
/// The picker reports a type that is sometimes empty or wrong (HEIC on some
/// Android devices, `application/octet-stream` from a share intent), and the
/// server only accepts JPEG/PNG/WebP. Sniffing the header lets us convert the
/// name/extension we send to match what the bytes actually are, instead of
/// uploading a mislabelled part the server rejects.
String _sniffImageType(List<int> bytes) {
  final data = Uint8List.fromList(bytes);
  bool startsWith(List<int> signature, [int offset = 0]) {
    if (data.length < offset + signature.length) return false;
    for (var i = 0; i < signature.length; i++) {
      if (data[offset + i] != signature[i]) return false;
    }
    return true;
  }

  if (startsWith(<int>[0xFF, 0xD8, 0xFF])) return 'image/jpeg';
  if (startsWith(<int>[0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])) {
    return 'image/png';
  }
  if (startsWith(<int>[0x52, 0x49, 0x46, 0x46]) &&
      startsWith(<int>[0x57, 0x45, 0x42, 0x50], 8)) {
    return 'image/webp';
  }
  return '';
}

/// The approved patient medical-identity fields
/// (`backend/patients/models.py` / database-design.md row 162).
class PatientProfile {
  const PatientProfile({
    this.dateOfBirth,
    this.gender,
    this.genotype,
    this.diagnosisDate,
    this.primaryDiagnosis,
    this.emergencyContactName,
    this.emergencyContactPhone,
    this.emergencyContactRelation,
    this.addressRegion,
    this.addressCity,
    this.facilityUid,
    this.facilityName,
    this.facilityRegion,
    this.facilityCity,
    this.notes = '',
  });

  factory PatientProfile.fromJson(Map<String, dynamic> json) => PatientProfile(
        dateOfBirth: json['date_of_birth'] as String?,
        gender: json['gender'] as String?,
        genotype: json['genotype'] as String?,
        diagnosisDate: json['diagnosis_date'] as String?,
        primaryDiagnosis: json['primary_diagnosis'] as String?,
        emergencyContactName: json['emergency_contact_name'] as String?,
        emergencyContactPhone: json['emergency_contact_phone'] as String?,
        emergencyContactRelation: json['emergency_contact_relation'] as String?,
        addressRegion: json['address_region'] as String?,
        addressCity: json['address_city'] as String?,
        facilityUid: _facilityUidFrom(json),
        facilityName: (json['facility_detail'] as Map<String, dynamic>?)?['name']
            as String?,
        facilityRegion: (json['facility_detail'] as Map<String, dynamic>?)?['region']
            as String?,
        facilityCity: (json['facility_detail'] as Map<String, dynamic>?)?['city']
            as String?,
        notes: (json['notes'] as String?) ?? '',
      );

  final String? dateOfBirth;
  final String? gender;
  final String? genotype;
  final String? diagnosisDate;
  final String? primaryDiagnosis;
  final String? emergencyContactName;
  final String? emergencyContactPhone;
  final String? emergencyContactRelation;
  final String? addressRegion;
  final String? addressCity;
  final String? facilityUid;
  final String? facilityName;
  final String? facilityRegion;
  final String? facilityCity;
  final String notes;

  Map<String, dynamic> toJson() => {
        if (dateOfBirth != null) 'date_of_birth': dateOfBirth,
        if (gender != null) 'gender': gender,
        if (genotype != null) 'genotype': genotype,
        if (diagnosisDate != null) 'diagnosis_date': diagnosisDate,
        if (primaryDiagnosis != null) 'primary_diagnosis': primaryDiagnosis,
        if (emergencyContactName != null)
          'emergency_contact_name': emergencyContactName,
        if (emergencyContactPhone != null)
          'emergency_contact_phone': emergencyContactPhone,
        if (emergencyContactRelation != null)
          'emergency_contact_relation': emergencyContactRelation,
        if (addressRegion != null) 'address_region': addressRegion,
        if (addressCity != null) 'address_city': addressCity,
        if (facilityUid != null) 'facility_uid': facilityUid,
        if (notes.isNotEmpty) 'notes': notes,
      };

  PatientProfile copyWith({
    String? dateOfBirth,
    String? gender,
    String? genotype,
    String? diagnosisDate,
    String? primaryDiagnosis,
    String? emergencyContactName,
    String? emergencyContactPhone,
    String? emergencyContactRelation,
    String? addressRegion,
    String? addressCity,
    String? facilityUid,
    String? facilityName,
    String? facilityRegion,
    String? facilityCity,
    String? notes,
  }) {
    return PatientProfile(
      dateOfBirth: dateOfBirth ?? this.dateOfBirth,
      gender: gender ?? this.gender,
      genotype: genotype ?? this.genotype,
      diagnosisDate: diagnosisDate ?? this.diagnosisDate,
      primaryDiagnosis: primaryDiagnosis ?? this.primaryDiagnosis,
      emergencyContactName: emergencyContactName ?? this.emergencyContactName,
      emergencyContactPhone: emergencyContactPhone ?? this.emergencyContactPhone,
      emergencyContactRelation:
          emergencyContactRelation ?? this.emergencyContactRelation,
      addressRegion: addressRegion ?? this.addressRegion,
      addressCity: addressCity ?? this.addressCity,
      facilityUid: facilityUid ?? this.facilityUid,
      facilityName: facilityName ?? this.facilityName,
      facilityRegion: facilityRegion ?? this.facilityRegion,
      facilityCity: facilityCity ?? this.facilityCity,
      notes: notes ?? this.notes,
    );
  }
}

String? _facilityUidFrom(Map<String, dynamic> json) {
  final detail = json['facility_detail'] as Map<String, dynamic>?;
  return detail?['uid'] as String?;
}

/// A facility in the public directory (`GET /facilities`, verified only).
class FacilityOption {
  const FacilityOption({
    required this.uid,
    required this.name,
    required this.facilityType,
    this.region = '',
    this.city = '',
  });

  factory FacilityOption.fromJson(Map<String, dynamic> json) => FacilityOption(
        uid: json['uid'] as String,
        name: (json['name'] as String?) ?? '',
        facilityType: (json['facility_type'] as String?) ?? 'OTHER',
        region: (json['region'] as String?) ?? '',
        city: (json['city'] as String?) ?? '',
      );

  final String uid;
  final String name;
  final String facilityType;
  final String region;
  final String city;

  String get label => [name, [region, city].where((p) => p.isNotEmpty).join(', ')]
      .where((p) => p.isNotEmpty)
      .join(' — ');
}

/// Client for `GET/PATCH /patients/me` (approved Stage 4.5 endpoint).
///
/// Ownership is enforced server-side; this client only ever talks about
/// the authenticated user's own row (owner scope, role-perm §8).
class ProfileRepository {
  ProfileRepository({required this.tokenStore, http.Client? client})
      : _client = client ?? http.Client();

  final TokenStore tokenStore;
  final http.Client _client;

  static const _timeout = Duration(seconds: 15);

  Uri _uri() => Uri.parse('${AppConfig.apiBaseUrl}/patients/me/');

  Map<String, String> _headers(String access) => {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        'Authorization': 'Bearer $access',
      };

  AuthException _errorFrom(http.Response res, String body) {
    try {
      final map = jsonDecode(body) as Map<String, dynamic>;
      final err = map['error'] as Map<String, dynamic>? ?? const {};
      return AuthException(
        (err['message'] as String?) ?? 'Request failed.',
        code: (err['code'] as String?) ?? 'API_ERROR',
        statusCode: res.statusCode,
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

  Future<PatientProfile> fetch({required String access}) async {
    final res = await _client
        .get(_uri(), headers: _headers(access))
        .timeout(_timeout);
    if (res.statusCode >= 400) throw _errorFrom(res, res.body);
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    final payload = data['data'] as Map<String, dynamic>? ?? data;
    return PatientProfile.fromJson(payload);
  }

  Future<PatientProfile> update({
    required String access,
    required PatientProfile profile,
  }) async {
    final res = await _client.patch(
      _uri(),
      headers: _headers(access),
      body: jsonEncode(profile.toJson()),
    ).timeout(_timeout);
    if (res.statusCode >= 400) throw _errorFrom(res, res.body);
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    final payload = data['data'] as Map<String, dynamic>? ?? data;
    return PatientProfile.fromJson(payload);
  }

  /// Fetch the public, verified facility directory.
  ///
  /// The directory is public reference data (`GET /facilities` is AllowAny and
  /// returns verified rows only), so no token is sent and nothing medical is
  /// requested. An empty list is returned when the call fails so the picker can
  /// degrade instead of blocking the whole profile screen.
  Future<List<FacilityOption>> fetchFacilities() async {
    try {
      final res = await _client
          .get(
            Uri.parse('${AppConfig.apiBaseUrl}/facilities/'),
            headers: const {'Accept': 'application/json'},
          )
          .timeout(_timeout);
      if (res.statusCode >= 400) return const [];
      final data = jsonDecode(res.body);
      final rows = data is Map<String, dynamic>
          ? (data['results'] ?? data['data'] ?? const [])
          : data;
      if (rows is! List) return const [];
      return rows
          .whereType<Map<String, dynamic>>()
          .map(FacilityOption.fromJson)
          .where((f) => f.uid.isNotEmpty && f.name.isNotEmpty)
          .toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  /// Path relative to `AppConfig.apiBaseUrl` (which already carries the `/api`
  /// prefix) — hard-coding `/api/…` here produced `/api/api/auth/me/photo/`
  /// and a 404 on every upload attempt.
  static const _photoUriPath = '/auth/me/photo/';

  /// Upload (or replace) the signed-in user's profile picture.
  ///
  /// Multipart POST to `/api/auth/me/photo/`; the server validates and
  /// re-encodes the image and returns the updated user summary whose
  /// `profile_photo_url` becomes the new avatar source.
  /// Matches the server contract in `content/upload_validation.py`
/// (ALLOWED_CONTENT_TYPES); anything else is refused before it is uploaded.
final Set<String> _allowedPhotoTypes = <String>{
  'image/jpeg',
  'image/png',
  'image/webp',
};

final int _maxPhotoBytes = 5 * 1024 * 1024;

String? _photoExtensionForType(String mimeType) {
  switch (mimeType.toLowerCase()) {
    case 'image/jpeg':
      return 'jpg';
    case 'image/png':
      return 'png';
    case 'image/webp':
      return 'webp';
    default:
      return null;
  }
}

Future<String> uploadProfilePhoto({
    required String access,
    required List<int> bytes,
    required String filename,
    String? mimeType,
  }) async {
    // Validate locally so the user gets an immediate, specific message instead
    // of a round-trip rejection, and so we never waste an upload.
    final resolvedType = (mimeType ?? _sniffImageType(bytes)).toLowerCase();
    if (!_allowedPhotoTypes.contains(resolvedType)) {
      throw AuthException(
        'That file is not a supported photo. Choose a JPEG, PNG or WebP image.',
        code: 'UNSUPPORTED_PHOTO_TYPE',
        statusCode: 0,
      );
    }
    if (bytes.isEmpty) {
      throw AuthException(
        'That photo appears to be empty. Choose another image.',
        code: 'EMPTY_PHOTO',
        statusCode: 0,
      );
    }
    if (bytes.length > _maxPhotoBytes) {
      throw AuthException(
        'That photo is larger than 5 MB. Choose a smaller image.',
        code: 'PHOTO_TOO_LARGE',
        statusCode: 0,
      );
    }
    final extension = _photoExtensionForType(resolvedType)!;
    final name = filename.contains('.')
        ? filename.substring(0, filename.lastIndexOf('.'))
        : filename;
    final request = http.MultipartRequest(
      'POST',
      Uri.parse('${AppConfig.apiBaseUrl}$_photoUriPath'),
    );
    request.headers['Accept'] = 'application/json';
    request.headers['Authorization'] = 'Bearer $access';
    // An explicit contentType is required: without it the part is sent as
    // application/octet-stream and the server rejects it as an unsupported
    // image. This was the root cause of "the photo upload just fails".
    request.files.add(http.MultipartFile.fromBytes(
      'image',
      bytes,
      filename: '$name.$extension',
      contentType: MediaType(resolvedType.split('/').first, resolvedType.split('/').last),
    ));
    final streamed = await _client.send(request).timeout(_timeout);
    final res = await http.Response.fromStream(streamed).timeout(_timeout);
    if (res.statusCode >= 400) throw _errorFrom(res, res.body);
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    final payload = data['data'] as Map<String, dynamic>? ?? data;
    final url = payload['profile_photo_url'] as String?;
    if (url == null || url.isEmpty) {
      throw AuthException(
        'Upload succeeded but returned no photo URL.',
        code: 'API_ERROR',
        statusCode: 200,
      );
    }
    return url;
  }
}