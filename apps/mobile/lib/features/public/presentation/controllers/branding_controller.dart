import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;

import '../../../../core/constants/app_config.dart';

/// Public brand payload from `GET /api/branding/`.
///
/// The server is the single source of truth for the logo: when an admin
/// uploads artwork via the admin console the same URL starts serving new bytes
/// on the next launch — no client build involved.
class BrandingInfo {
  const BrandingInfo({
    required this.hasLogo,
    required this.logoUrl,
    required this.logoAlt,
    this.logoVersion = '',
  });

  const BrandingInfo.none()
      : hasLogo = false,
        logoUrl = '',
        logoAlt = '',
        logoVersion = '';

  factory BrandingInfo.fromJson(Map<String, dynamic> json) {
    return BrandingInfo(
      hasLogo: json['has_logo'] == true,
      logoUrl: (json['logo_url'] as String?) ?? '',
      logoAlt: (json['logo_alt'] as String?) ?? '',
      logoVersion: (json['logo_version'] as String?) ?? '',
    );
  }

  final bool hasLogo;
  final String logoUrl;
  final String logoAlt;

  /// Stamp the server sets whenever the artwork changes; appended to the logo
  /// URL as a query param so the network image cache is busted on replacement
  /// (the URL itself never changes otherwise).
  final String logoVersion;
}

/// Fetches and holds the live admin branding (once per app launch).
///
/// Failures are silent: [info] stays `BrandingInfo.none()` and every logo
/// surface falls back to the bundled placeholder, mirroring the admin web
/// behaviour.
class BrandingController extends ChangeNotifier {
  BrandingController({http.Client? client})
      : _client = client ?? http.Client();

  final http.Client _client;

  static const _timeout = Duration(seconds: 10);

  BrandingInfo _info = const BrandingInfo.none();
  BrandingInfo get info => _info;
  bool get hasLogo => _info.hasLogo;

  /// Absolute URL for the live logo, resolving server-relative paths
  /// (`/api/branding/logo/`) against the API origin. The logo version stamps
  /// the URL so a replaced artwork is fetched fresh instead of serving cached
  /// bytes.
  String get resolvedLogoUrl {
    final raw = _info.logoUrl;
    if (raw.isEmpty) return '';
    final versioned = _info.logoVersion.isNotEmpty
        ? '${raw.contains('?') ? '&' : '?'}v=${Uri.encodeQueryComponent(_info.logoVersion)}'
        : '';
    if (raw.startsWith('http://') || raw.startsWith('https://')) {
      return '$raw$versioned';
    }
    final base = Uri.parse(AppConfig.apiBaseUrl);
    final origin = Uri(scheme: base.scheme, host: base.host, port: base.port);
    return origin.resolve('$raw$versioned').toString();
  }

  Future<void> load() async {
    try {
      final res = await _client
          .get(Uri.parse('${AppConfig.apiBaseUrl}/branding/'))
          .timeout(_timeout);
      if (res.statusCode >= 400) return;
      final decoded = jsonDecode(res.body);
      if (decoded is! Map<String, dynamic>) return;
      final data = decoded['data'];
      if (data is! Map<String, dynamic>) return;
      _info = BrandingInfo.fromJson(data);
      notifyListeners();
    } catch (_) {
      // Offline / unavailable: keep the bundled logo fallback.
    }
  }

  @override
  void dispose() {
    _client.close();
    super.dispose();
  }
}

/// Inherited access to the app [BrandingController].
class BrandingScope extends InheritedNotifier<BrandingController> {
  const BrandingScope({
    super.key,
    required BrandingController controller,
    required super.child,
  }) : super(notifier: controller);

  static BrandingController of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<BrandingScope>();
    assert(scope != null, 'No BrandingScope found in widget tree.');
    return scope!.notifier!;
  }

  static BrandingController? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<BrandingScope>()?.notifier;

  static BrandingController? read(BuildContext context) =>
      context.getInheritedWidgetOfExactType<BrandingScope>()?.notifier;
}