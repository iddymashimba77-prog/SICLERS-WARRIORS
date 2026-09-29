import 'dart:async';

import 'package:http/http.dart' as http;

import '../../auth/data/auth_repository.dart';
import '../../auth/data/token_store.dart';
import '../../blood_donation/data/blood_repository.dart';
import '../../education/data/education_repository.dart';
import '../../emergency/data/emergency_repository.dart';
import '../../health/data/health_repository.dart';
import '../../notifications/data/notifications_repository.dart';

/// Aggregated snapshot rendered by the patient Home dashboard (FRONTEND-2).
///
/// Section slots are individually optional: a failing side call never downs
/// the whole dashboard. [dashboard] (health/medication/pain snapshot) is the
/// only required payload; the rest degrades to honest empty states.
class HomeDashboardData {
  const HomeDashboardData({
    required this.dashboard,
    this.identity,
    this.unreadCount,
    this.articles = const [],
    this.activeEmergencies = const [],
    this.openBloodRequests = const [],
    this.offline = false,
  });

  /// Primary payload from `GET /patients/me/dashboard`.
  final HealthDashboard? dashboard;

  /// Safe identity subset from `GET /auth/me` (name, email, roles).
  final AuthSessionOutcome? identity;

  /// Unread in-app notifications for the header badge.
  final int? unreadCount;

  /// Published education content for the "Learn & grow" slot.
  final List<EducationalContent> articles;

  /// Caller's emergency requests still in progress (red alert).
  final List<EmergencyRequest> activeEmergencies;

  /// Caller's blood requests still open (amber alert).
  final List<BloodRequest> openBloodRequests;

  /// True when a transport/time-out failure was observed; the UI shows an
  /// honest offline banner instead of fabricating data.
  final bool offline;
}

/// Orchestrates every read the Home dashboard needs, one round-trip set.
///
/// Reuses the approved feature repositories — no duplicate API clients — and
/// fires the light side reads in parallel behind the primary dashboard call.
class HomeDashboardLoader {
  HomeDashboardLoader({http.Client? client, TokenStore? tokenStore})
      : _client = client,
        _tokenStore = tokenStore ?? EphemeralTokenStore() {
    _health = HealthRepository(tokenStore: _tokenStore, client: _client);
    _auth = AuthRepository(tokenStore: _tokenStore, client: _client);
    _notifications =
        NotificationsRepository(tokenStore: _tokenStore, client: _client);
    _education = EducationRepository(tokenStore: _tokenStore, client: _client);
    _emergency = EmergencyRepository(tokenStore: _tokenStore, client: _client);
    _blood = BloodRepository(tokenStore: _tokenStore, client: _client);
  }

  final http.Client? _client;
  final TokenStore _tokenStore;

  late final HealthRepository _health;
  late final AuthRepository _auth;
  late final NotificationsRepository _notifications;
  late final EducationRepository _education;
  late final EmergencyRepository _emergency;
  late final BloodRepository _blood;

  /// The shared health client; the check-in flow reuses it to record symptoms.
  HealthRepository get healthRepository => _health;

  Future<HomeDashboardData> load({required String access}) async {
    final results = await Future.wait<Object>([
      _safe(() => _health.fetchDashboard(access: access)),
      _safe(() => _auth.me(access: access)),
      _safe(() => _notifications.unreadCount(access: access)),
      _safe(() => _education.listContent(access: access, pageSize: 3)),
      _safe(() => _emergency.listRequests(access: access)),
      _safe(() => _blood.listRequests(access: access)),
    ]);

    final dash = results[0] as _LoadResult<HealthDashboard>;
    final identity = results[1] as _LoadResult<AuthSessionOutcome>;
    final unread = results[2] as _LoadResult<int>;
    final articles = results[3] as _LoadResult<List<EducationalContent>>;
    final emergencies = results[4] as _LoadResult<List<EmergencyRequest>>;
    final bloodRequests = results[5] as _LoadResult<List<BloodRequest>>;

    final failed = [
      dash,
      identity,
      unread,
      articles,
      emergencies,
      bloodRequests,
    ].where((r) => r.isError).toList();

    return HomeDashboardData(
      dashboard: dash.value,
      identity: identity.value,
      unreadCount: unread.value,
      articles: articles.value ?? const [],
      activeEmergencies: (emergencies.value ?? const [])
          .where((e) => e.isActive)
          .toList(),
      openBloodRequests: (bloodRequests.value ?? const [])
          .where((b) => b.isOpen)
          .toList(),
      offline: failed.any((r) => _isOfflineError(r.error!)),
    );
  }
}

Future<_LoadResult<T>> _safe<T>(Future<T> Function() run) async {
  try {
    return _LoadResult.value(await run());
  } catch (e) {
    return _LoadResult.error(e);
  }
}

bool _isOfflineError(Object error) =>
    error is TimeoutException || error is http.ClientException;

class _LoadResult<T> {
  const _LoadResult.value(this.value) : error = null;
  const _LoadResult.error(this.error) : value = null;

  final T? value;
  final Object? error;

  bool get isError => error != null;
}