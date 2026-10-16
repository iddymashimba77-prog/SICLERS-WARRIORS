import 'package:flutter/material.dart';

import '../../../../core/l10n/app_localizations.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../auth/data/token_store.dart';
import '../../../auth/presentation/widgets/session_scope.dart';
import '../../data/admin_models.dart';
import '../../data/admin_repository.dart';
import '../widgets/admin_widgets.dart';

/// Audit log oversight (ADMIN-3) — GET /api/admin/audit-logs/ with the
/// approved 4.16 filters (action_code, resource_type, result, actor.
/// Payloads are never exposed; this client only reads the log columns.
class AdminAuditLogsPage extends StatelessWidget {
  const AdminAuditLogsPage({super.key, this.repository, this.accessToken});

  static const String routeName = '/admin/audit-logs';

  final AdminRepository? repository;
  final String? accessToken;

  @override
  Widget build(BuildContext context) {
    final session = SessionScope.controllerOf(context);
    final token = accessToken ?? session.accessToken;
    if (token == null) return Center(child: Text(tr('admin.notSignedIn')));
    return _AuditView(
      accessToken: token,
      repository: repository ?? AdminRepository(tokenStore: EphemeralTokenStore()),
    );
  }
}

class _AuditView extends StatefulWidget {
  const _AuditView({required this.accessToken, required this.repository});

  final String accessToken;
  final AdminRepository repository;

  @override
  State<_AuditView> createState() => _AuditViewState();
}

class _AuditViewState extends State<_AuditView> {
  final GlobalKey<AdminAsyncListState<AdminAuditLog>> _listKey =
      GlobalKey<AdminAsyncListState<AdminAuditLog>>();
  final TextEditingController _actionCode = TextEditingController();
  final TextEditingController _actor = TextEditingController();
  String _result = '';

  Future<List<AdminAuditLog>> _load() => widget.repository.listAuditLogs(
        access: widget.accessToken,
        actionCode: _actionCode.text.trim(),
        actor: _actor.text.trim(),
        result: _result.isEmpty ? null : _result,
      );

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        AdminSectionHeader(
          title: tr('admin.nav.auditLogs'),
          subtitle: tr('admin.auditSubtitle'),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _actionCode,
                      decoration: InputDecoration(
                        prefixIcon: const Icon(Icons.tag, size: 20),
                        hintText: tr('admin.actionCodeHint'),
                        isDense: true,
                      ),
                      onSubmitted: (_) => _listKey.currentState?.reload(),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: TextField(
                      controller: _actor,
                      decoration: InputDecoration(
                        prefixIcon: const Icon(Icons.person_outline, size: 20),
                        hintText: tr('admin.actorEmailHint'),
                        isDense: true,
                      ),
                      onSubmitted: (_) => _listKey.currentState?.reload(),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              Align(
                alignment: Alignment.centerLeft,
                child: Wrap(
                  spacing: 8,
                  children: [
                    for (final filter in [
                      ('', tr('admin.allResults')),
                      ('SUCCESS', tr('admin.success')),
                      ('FAILURE', tr('admin.failure')),
                      ('DENIED', tr('admin.denied')),
                    ])
                      ChoiceChip(
                        label: Text(filter.$2),
                        selected: _result == filter.$1,
                        onSelected: (_) {
                          setState(() => _result = filter.$1);
                          _listKey.currentState?.reload();
                        },
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        AdminAsyncList<AdminAuditLog>(
          key: _listKey,
          load: _load,
          emptyTitle: tr('admin.noLogEntries'),
          emptyMessage: tr('admin.noAuditMatch'),
          emptyIcon: Icons.history_outlined,
          itemBuilder: (context, log) => Card(
            margin: EdgeInsets.zero,
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.lg,
                vertical: AppSpacing.xs,
              ),
              leading: const CircleAvatar(
                child: Icon(Icons.receipt_long_outlined, size: 18),
              ),
              title: Text(
                log.actionCode,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              subtitle: Text(
                '${log.actorEmail.isEmpty ? tr('admin.system') : log.actorEmail} · '
                '${log.resourceType.isEmpty ? '—' : log.resourceType}'
                '${log.resourceId.isEmpty ? '' : ' #${log.resourceId}'}',
              ),
              trailing: AdminStatusChip(status: log.result),
              onTap: () => _detail(context, log),
            ),
          ),
        ),
      ],
    );
  }

  void _detail(BuildContext context, AdminAuditLog log) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(log.actionCode),
        content: SizedBox(
          width: 480,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _kv(tr('admin.actor'),
                  log.actorEmail.isEmpty ? tr('admin.system') : log.actorEmail),
              _kv(tr('admin.result'), log.result),
              if (log.resourceType.isNotEmpty)
                _kv(tr('admin.resource'), log.resourceType),
              if (log.resourceId.isNotEmpty)
                _kv(tr('admin.resourceId'), log.resourceId),
              if (log.ipAddress.isNotEmpty) _kv(tr('admin.ip'), log.ipAddress),
              if (log.requestId.isNotEmpty)
                _kv(tr('admin.requestId'), log.requestId),
              if (log.createdAt != null)
                _kv(tr('admin.timestamp'), log.createdAt!),
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