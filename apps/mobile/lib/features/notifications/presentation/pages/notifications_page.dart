import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_strings.dart';
import '../../../../shared/widgets/state_views.dart';
import '../../../auth/data/token_store.dart';
import '../../../auth/presentation/controllers/auth_controller.dart';
import '../../../auth/presentation/widgets/session_scope.dart';
import '../../../blood_donation/presentation/pages/blood_donation_page.dart';
import '../../../chat/presentation/pages/conversation_list_page.dart';
import '../../../community/presentation/pages/community_page.dart';
import '../../../donations/presentation/pages/donations_page.dart';
import '../../../education/presentation/pages/education_page.dart';
import '../../../emergency/presentation/pages/emergency_page.dart';
import '../../../health/presentation/pages/health_dashboard_page.dart';
import '../../../medication/presentation/pages/medication_page.dart';
import '../../data/notifications_repository.dart';
import '../../../../shared/widgets/signed_out_gate.dart';

/// Inbox display order for the notification center (approved §23 grouping).
const List<String> _inboxOrder = [
  'EMERGENCY',
  'BLOOD',
  'MEDICATION_REMINDER',
  'PAYMENT',
  'COMMUNITY',
  'CONSENT',
  'APPOINTMENT',
  'SYSTEM',
];

/// Human label per category (approved §23 / mobile-ui-ux-design).
const Map<String, String> _categoryLabels = {
  'MEDICATION_REMINDER': 'Medication reminders',
  'APPOINTMENT': 'Appointments & clinics',
  'BLOOD': 'Blood network & donors',
  'EMERGENCY': 'Emergency alerts',
  'PAYMENT': 'Payments & campaign updates',
  'COMMUNITY': 'Community activity',
  'CONSENT': 'Consent & data access',
  'SYSTEM': 'Security & system alerts',
};

/// User-facing preference groups (approve §23.6 grouping).
const List<MapEntry<String, List<String>>> _preferenceSections = [
  MapEntry('Medical & Safety', ['MEDICATION_REMINDER', 'APPOINTMENT', 'EMERGENCY']),
  MapEntry('Blood & Donations', ['BLOOD', 'PAYMENT']),
  MapEntry('Community & Academy', ['COMMUNITY']),
  MapEntry('Account & Platform', ['CONSENT', 'SYSTEM']),
];

/// Approved in-app deep-link allowlist for notification routes.
///
/// Unknown or unapproved routes are deliberately ignored so a compromised
/// payload can never navigate the user somewhere unsafe.
String? _resolveRoute(String? route) {
  const allowlist = <String, String>{
    'medication': MedicationPage.routeName,
    'blood': BloodDonationPage.routeName,
    'community': CommunityPage.routeName,
    'education': EducationPage.routeName,
    'messages': ConversationListPage.routeName,
    'donations': DonationsPage.routeName,
    'emergency': EmergencyPage.routeName,
    'health': HealthDashboardPage.routeName,
  };
  return route == null ? null : allowlist[route];
}

/// Notifications inbox + preferences (approved FR-NOT-001..006).
///
/// Recipient-scoped: the server only ever returns the caller's rows. Emergency
/// notifications are never suppressible; the preferences tab reflects that by
/// showing the category state without offering an unsafe override.
class NotificationsPage extends StatelessWidget {
  const NotificationsPage({
    super.key,
    this.authController,
    this.notificationsRepository,
  });

  static const String routeName = '/notifications';

  final AuthController? authController;
  final NotificationsRepository? notificationsRepository;

  @override
  Widget build(BuildContext context) {
    final token = (authController ?? SessionScope.controllerOf(context))
        .accessToken;
    if (token == null) {
      return const SignedOutGate();
    }
    return NotificationsHomeView(
      accessToken: token,
      repository: notificationsRepository ??
          NotificationsRepository(tokenStore: EphemeralTokenStore()),
    );
  }
}

class NotificationsHomeView extends StatelessWidget {
  const NotificationsHomeView({
    super.key,
    required this.accessToken,
    required this.repository,
  });

  final String accessToken;
  final NotificationsRepository repository;

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text(AppStrings.notifications),
          bottom: const TabBar(
            tabs: [
              Tab(text: AppStrings.inbox),
              Tab(text: AppStrings.preferences),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _InboxTab(accessToken: accessToken, repository: repository),
            _PreferencesTab(accessToken: accessToken, repository: repository),
          ],
        ),
      ),
    );
  }
}

class _InboxTab extends StatefulWidget {
  const _InboxTab({required this.accessToken, required this.repository});

  final String accessToken;
  final NotificationsRepository repository;

  @override
  State<_InboxTab> createState() => _InboxTabState();
}

class _InboxTabState extends State<_InboxTab> {
  List<AppNotification>? _items;
  int? _unreadTotal;
  Object? _error;
  bool _loading = true;
  bool _markingAll = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final items = await widget.repository.list(access: widget.accessToken);
      int unread;
      try {
        unread =
            await widget.repository.unreadCount(access: widget.accessToken);
      } catch (_) {
        unread = items.where((n) => n.isUnread).length;
      }
      if (!mounted) return;
      setState(() {
        _items = items;
        _unreadTotal = unread;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  Future<void> _onTap(AppNotification notification) async {
    try {
      if (notification.isUnread) {
        await widget.repository.markRead(
          access: widget.accessToken,
          id: notification.id,
        );
      }
      final route = _resolveRoute(notification.route);
      if (route != null && mounted) {
        Navigator.pushNamed(context, route);
      } else if (mounted) {
        // Refresh read state even when there is no deep link.
        await _load();
      }
    } catch (_) {
      if (mounted) _showError(AppStrings.notificationsReadFailed);
    }
  }

  Future<void> _readAll() async {
    setState(() => _markingAll = true);
    try {
      await widget.repository.readAll(access: widget.accessToken);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text(AppStrings.notificationsAllRead)),
      );
      await _load();
    } catch (_) {
      _showError(AppStrings.notificationsReadFailed);
    } finally {
      if (mounted) setState(() => _markingAll = false);
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  List<AppNotification> _inGroup(List<AppNotification> items, String type) =>
      items.where((n) => n.type == type).toList();

  @override
  Widget build(BuildContext context) {
    if (_loading) return const LoadingView();
    if (_error != null) {
      return ErrorRetryView(
        message: AppStrings.notificationsLoadFailed,
        onRetry: _load,
      );
    }
    final items = _items ?? const <AppNotification>[];
    final hasUnread = items.any((n) => n.isUnread);
    final groups = [
      for (final type in _inboxOrder)
        if (_inGroup(items, type).isNotEmpty)
          (type: type, items: _inGroup(items, type)),
    ];
    return RefreshIndicator(
      onRefresh: _load,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 8, 4),
            child: Row(
              children: [
                if ((_unreadTotal ?? 0) > 0)
                  Expanded(
                    child: Text(
                      '${AppStrings.unread} · $_unreadTotal',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                  )
                else
                  const Expanded(
                    child: Text(AppStrings.notificationGroupHelp,
                        style: TextStyle(fontSize: 12)),
                  ),
                if (hasUnread)
                  TextButton.icon(
                    onPressed: _markingAll ? null : _readAll,
                    icon: const Icon(Icons.done_all, size: 18),
                    label: const Text(AppStrings.markAllRead),
                  ),
              ],
            ),
          ),
          Expanded(
            child: items.isEmpty
                ? const EmptyStateView(
                    message: AppStrings.noNotifications,
                    icon: Icons.notifications_none,
                  )
                : ListView(
                    children: [
                      for (final group in groups) ...[
                        _SectionHeader(
                          label: _categoryLabels[group.type] ??
                              group.type.replaceAll('_', ' '),
                          count: group.items.length,
                        ),
                        for (final item in group.items)
                          _NotificationTile(
                            notification: item,
                            onTap: () => _onTap(item),
                          ),
                      ],
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.label, required this.count});

  final String label;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label.toUpperCase(),
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
                  ),
            ),
          ),
          Text(
            '$count',
            style: Theme.of(context)
                .textTheme
                .labelSmall
                ?.copyWith(color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }
}

class _NotificationTile extends StatelessWidget {
  const _NotificationTile({
    required this.notification,
    required this.onTap,
  });

  final AppNotification notification;
  final VoidCallback onTap;

  IconData get _icon {
    switch (notification.type) {
      case 'MEDICATION_REMINDER':
        return Icons.medication_outlined;
      case 'APPOINTMENT':
        return Icons.event_outlined;
      case 'BLOOD':
        return Icons.bloodtype_outlined;
      case 'EMERGENCY':
        return Icons.sos;
      case 'PAYMENT':
        return Icons.payments_outlined;
      case 'COMMUNITY':
        return Icons.groups_outlined;
      case 'CONSENT':
        return Icons.verified_user_outlined;
      default:
        return Icons.notifications_outlined;
    }
  }

  /// Red only for CRITICAL (emergency). HIGH uses the blue accent.
  Color get _accent {
    if (notification.isCritical || notification.isEmergency) {
      return AppColors.emergency;
    }
    if (notification.isHighPriority) return AppColors.secondary;
    return AppColors.textSecondary;
  }

  @override
  Widget build(BuildContext context) {
    final unread = notification.isUnread;
    final accent = _accent;
    final trailing = _resolveRoute(notification.route) != null;
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: ListTile(
        onTap: onTap,
        leading: CircleAvatar(
          backgroundColor: accent.withValues(alpha: 0.15),
          child: Icon(_icon, color: accent, size: 20),
        ),
        title: Text(
          notification.title,
          style: TextStyle(
            fontWeight: unread ? FontWeight.w700 : FontWeight.w400,
          ),
        ),
        subtitle: Text(
          notification.body,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (unread)
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: accent,
                  shape: BoxShape.circle,
                ),
              ),
            if (trailing) ...[
              const SizedBox(width: 4),
              Icon(Icons.chevron_right,
                  size: 20, color: AppColors.textSecondary),
            ],
          ],
        ),
      ),
    );
  }
}

class _PreferencesTab extends StatefulWidget {
  const _PreferencesTab({required this.accessToken, required this.repository});

  final String accessToken;
  final NotificationsRepository repository;

  @override
  State<_PreferencesTab> createState() => _PreferencesTabState();
}

class _PreferencesTabState extends State<_PreferencesTab> {
  Map<String, bool>? _prefs;
  Object? _error;
  bool _loading = true;
  final Set<String> _saving = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final prefs = await widget.repository.getPreferences(
        access: widget.accessToken,
      );
      if (!mounted) return;
      setState(() {
        _prefs = prefs;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  Future<void> _toggle(String category, bool enabled) async {
    setState(() {
      _saving.add(category);
      _prefs = {...?_prefs, category: enabled};
    });
    try {
      await widget.repository.updatePreference(
        access: widget.accessToken,
        category: category,
        enabled: enabled,
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text(AppStrings.categorySaveFailed)),
      );
      await _load();
    } finally {
      if (mounted) setState(() => _saving.remove(category));
    }
  }

  String _label(String category) =>
      _categoryLabels[category] ??
      category.replaceAll('_', ' ').toLowerCase();

  @override
  Widget build(BuildContext context) {
    if (_loading) return const LoadingView();
    if (_error != null) {
      return ErrorRetryView(
        message: AppStrings.categoriesLoadFailed,
        onRetry: _load,
      );
    }
    final prefs = _prefs ?? const <String, bool>{};
    return ListView(
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Text(AppStrings.notificationGroupHelp,
              style: TextStyle(fontSize: 12)),
        ),
        for (final section in _preferenceSections) ...[
          _SectionHeader(label: section.key, count: section.value.length),
          for (final category in section.value)
            SwitchListTile(
              title: Text(_label(category)),
              subtitle: category == 'EMERGENCY'
                  ? const Text(AppStrings.emergencyLockedHelp)
                  : null,
              value: category == 'EMERGENCY' ? true : (prefs[category] ?? true),
              secondary: Icon(
                category == 'EMERGENCY'
                    ? Icons.lock_outline
                    : Icons.notifications_outlined,
                color: category == 'EMERGENCY'
                    ? AppColors.emergency
                    : AppColors.textSecondary,
              ),
              onChanged: category == 'EMERGENCY'
                  ? null
                  : (_saving.contains(category)
                      ? null
                      : (value) => _toggle(category, value)),
            ),
        ],
      ],
    );
  }
}