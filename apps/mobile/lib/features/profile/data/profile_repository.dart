import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../core/constants/app_config.dart';
import '../../auth/data/token_store.dart';
import '../../auth/domain/auth_types.dart';

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
      notes: notes ?? this.notes,
    );
  }
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

  static const _photoUriPath = '/api/auth/me/photo/';

  /// Upload (or replace) the signed-in user's profile picture.
  ///
  /// Multipart POST to `/api/auth/me/photo/`; the server validates and
  /// re-encodes the image and returns the updated user summary whose
  /// `profile_photo_url` becomes the new avatar source.
  Future<String> uploadProfilePhoto({
    required String access,
    required List<int> bytes,
    required String filename,
  }) async {
    final request = http.MultipartRequest(
      'POST',
      Uri.parse('${AppConfig.apiBaseUrl}$_photoUriPath'),
    );
    request.headers['Accept'] = 'application/json';
    request.headers['Authorization'] = 'Bearer $access';
    request.files.add(http.MultipartFile.fromBytes(
      'image',
      bytes,
      filename: filename,
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