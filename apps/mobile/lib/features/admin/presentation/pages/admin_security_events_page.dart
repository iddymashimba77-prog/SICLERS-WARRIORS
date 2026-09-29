import 'package:flutter/material.dart';

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
    if (token == null) return const Center(child: Text('Not signed in.'));
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
          title: 'Security Events',
          subtitle: 'Recorded authentication and security telemetry.',
          trailing: Wrap(
            spacing: 8,
            children: [
              for (final filter in [
                ('', 'All'),
                ('SUCCESS', 'Success'),
                ('FAILURE', 'Failed'),
                ('CHALLENGED', 'Challenged'),
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
          emptyTitle: 'No security events',
          emptyMessage: 'No recorded events match this filter.',
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
                '${event.userEmail.isEmpty ? 'anonymous' : event.userEmail} · '
                '${event.ipAddress.isEmpty ? 'no ip' : event.ipAddress}',
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
              _kv('Status', event.status),
              _kv('User', event.userEmail.isEmpty ? 'anonymous' : event.userEmail),
              if (event.ipAddress.isNotEmpty) _kv('IP', event.ipAddress),
              if (event.userAgent.isNotEmpty) _kv('Agent', event.userAgent),
              if (event.createdAt != null) _kv('Timestamp', event.createdAt!),
              if (event.detail.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.sm),
                Text('Details:', style: Theme.of(context).textTheme.bodySmall),
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
            child: const Text('Close'),
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