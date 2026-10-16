import 'package:flutter/material.dart';

import '../../../../core/l10n/app_localizations.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../auth/data/token_store.dart';
import '../../../auth/presentation/widgets/session_scope.dart';
import '../../data/admin_models.dart';
import '../../data/admin_repository.dart';
import '../widgets/admin_widgets.dart';

/// Security telemetry (ADMIN-3) — GET /api/admin/security-events/ with
/// event_type/status filters. Every row is a real recorded security event;
/// there is no fabricated "system health" data here (admin.audit.read).
class AdminSecurityEventsPage extends StatelessWidget {
  const AdminSecurityEventsPage({super.key, this.repository, this.accessToken});

  static const String routeName = '/admin/security-events';

  final AdminRepository? repository;
  final String? accessToken;

  @override
  Widget build(BuildContext context) {
    final session = SessionScope.controllerOf(context);
    final token = accessToken ?? session.accessToken;
    if (token == null) return Center(child: Text(tr('admin.notSignedIn')));
    return _SecurityEventsView(
      accessToken: token,
      repository: repository ?? AdminRepository(tokenStore: EphemeralTokenStore()),
    );
  }
}

class _SecurityEventsView extends StatefulWidget {
  const _SecurityEventsView({required this.accessToken, required this.repository});

  final String accessToken;
  final AdminRepository repository;

  @override
  State<_SecurityEventsView> createState() => _SecurityEventsViewState();
}

class _SecurityEventsViewState extends State<_SecurityEventsView> {
  final GlobalKey<AdminAsyncListState<SecurityEvent>> _listKey =
      GlobalKey<AdminAsyncListState<SecurityEvent>>();
  String _status = '';

  Future<List<SecurityEvent>> _load() => widget.repository.listSecurityEvents(
        access: widget.accessToken,
        status: _status.isEmpty ? null : _status,
      );

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        AdminSectionHeader(
          title: tr('admin.nav.securityEvents'),
          subtitle: tr('admin.securitySubtitle'),
          trailing: Wrap(
            spacing: 8,
            children: [
              for (final filter in [
                ('', tr('admin.filter.all')),
                ('SUCCESS', tr('admin.success')),
                ('FAILURE', tr('admin.failed')),
                ('CHALLENGED', tr('admin.challenged')),
              ])
                ChoiceChip(
                  label: Text(filter.$2),
                  selected: _status == filter.$1,
                  onSelected: (_) {
                    setState(() => _status = filter.$1);
                    _listKey.currentState?.reload();
                  },
                ),
            ],
          ),
        ),
        AdminAsyncList<SecurityEvent>(
          key: _listKey,
          load: _load,
          emptyTitle: tr('admin.noSecurityEvents'),
          emptyMessage: tr('admin.noEventsMatch'),
          emptyIcon: Icons.shield_outlined,
          itemBuilder: (context, event) => Card(
            margin: EdgeInsets.zero,
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.lg,
                vertical: AppSpacing.xs,
              ),
              leading: const CircleAvatar(
                child: Icon(Icons.security_outlined, size: 18),
              ),
              title: Text(
                event.eventType,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              subtitle: Text(
                '${event.userEmail.isEmpty ? tr('admin.anonymous') : event.userEmail} · '
                '${event.ipAddress.isEmpty ? tr('admin.noIp') : event.ipAddress}',
              ),
              trailing: AdminStatusChip(status: event.status),
              onTap: () => _detail(context, event),
            ),
          ),
        ),
      ],
    );
  }

  void _detail(BuildContext context, SecurityEvent event) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(event.eventType),
        content: SizedBox(
          width: 480,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _kv(tr('admin.status'), event.status),
              _kv(tr('admin.user'),
                  event.userEmail.isEmpty ? tr('admin.anonymous') : event.userEmail),
              if (event.ipAddress.isNotEmpty) _kv(tr('admin.ip'), event.ipAddress),
              if (event.userAgent.isNotEmpty)
                _kv(tr('admin.agent'), event.userAgent),
              if (event.createdAt != null)
                _kv(tr('admin.timestamp'), event.createdAt!),
              if (event.detail.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.sm),
                Text('${tr('admin.details')}:',
                    style: Theme.of(context).textTheme.bodySmall),
                const SizedBox(height: 4),
                SelectableText(
                  event.detail.toString(),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(tr('common.close')),
          ),
        ],
      ),
    );
  }

  Widget _kv(String key, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(
              key,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          Expanded(child: SelectableText(value)),
        ],
      ),
    );
  }
}