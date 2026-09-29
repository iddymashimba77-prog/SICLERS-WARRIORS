import 'package:flutter/material.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../../auth/data/token_store.dart';
import '../../../auth/presentation/widgets/session_scope.dart';
import '../../data/admin_models.dart';
import '../../data/admin_repository.dart';
import '../widgets/admin_widgets.dart';

/// Roles & permissions matrix (ADMIN-3) — GET /api/admin/roles/ + per-role
/// permission codes. Reads are gated by `admin.roles.manage`; grant/revoke
/// writes are surfaced only to sessions holding `admin.permissions.manage`
/// (SUPER_ADMIN) — always re-enforced server-side.
class AdminRolesPage extends StatelessWidget {
  const AdminRolesPage({super.key, this.repository, this.accessToken});

  static const String routeName = '/admin/roles';

  final AdminRepository? repository;
  final String? accessToken;

  @override
  Widget build(BuildContext context) {
    final session = SessionScope.controllerOf(context);
    final token = accessToken ?? session.accessToken;
    if (token == null) return const Center(child: Text('Not signed in.'));
    return _RolesView(
      accessToken: token,
      canWrite: session.permissions
          .contains('admin.permissions.manage'),
      repository: repository ?? AdminRepository(tokenStore: EphemeralTokenStore()),
    );
  }
}

class _RolesView extends StatefulWidget {
  const _RolesView({
    required this.accessToken,
    required this.canWrite,
    required this.repository,
  });

  final String accessToken;
  final bool canWrite;
  final AdminRepository repository;

  @override
  State<_RolesView> createState() => _RolesViewState();
}

class _RolesViewState extends State<_RolesView> {
  final GlobalKey<AdminAsyncListState<AdminRole>> _listKey =
      GlobalKey<AdminAsyncListState<AdminRole>>();

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        AdminSectionHeader(
          title: 'Roles & Permissions',
          subtitle: widget.canWrite
              ? 'Grant and revoke permission codes (admin.permissions.manage).'
              : 'Read-only matrix — only SUPER_ADMIN can modify grants.',
        ),
        RepaintBoundary(
          child: AdminAsyncList<AdminRole>(
            key: _listKey,
            load: () => widget.repository.listRoles(access: widget.accessToken),
            emptyIcon: Icons.security_outlined,
            emptyTitle: 'No roles',
            emptyMessage: 'The roles registry is empty.',
            itemBuilder: (context, role) => _RoleCard(
              role: role,
              canWrite: widget.canWrite,
              repository: widget.repository,
              accessToken: widget.accessToken,
              onChanged: () => _listKey.currentState?.reload(),
            ),
          ),
        ),
      ],
    );
  }
}

class _RoleCard extends StatelessWidget {
  const _RoleCard({
    required this.role,
    required this.canWrite,
    required this.repository,
    required this.accessToken,
    required this.onChanged,
  });

  final AdminRole role;
  final bool canWrite;
  final AdminRepository repository;
  final String accessToken;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.sm,
        ),
        leading: CircleAvatar(
          backgroundColor: theme.colorScheme.primaryContainer,
          child: Text(role.code.isEmpty ? '?' : role.code.substring(0, 1)),
        ),
        title: Text('${role.code} — ${role.name}'),
        subtitle: Text(
          '${role.permissionCount} permission(s) · ${role.memberCount} member(s)'
          '${role.isSystem ? ' · system role' : ''}',
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => _openPermissions(context),
      ),
    );
  }

  Future<void> _openPermissions(BuildContext context) async {
    List<String> codes;
    try {
      codes = await repository.listRolePermissions(
        access: accessToken,
        roleCode: role.code,
      );
    } on Exception {
      if (context.mounted) {
        showAdminMessage(context, 'Could not load permissions.');
      }
      return;
    }
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => _PermissionsDialog(
        role: role,
        codes: codes,
        canWrite: canWrite,
        repository: repository,
        accessToken: accessToken,
        onChanged: onChanged,
      ),
    );
  }
}

class _PermissionsDialog extends StatefulWidget {
  const _PermissionsDialog({
    required this.role,
    required this.codes,
    required this.canWrite,
    required this.repository,
    required this.accessToken,
    required this.onChanged,
  });

  final AdminRole role;
  final List<String> codes;
  final bool canWrite;
  final AdminRepository repository;
  final String accessToken;
  final VoidCallback onChanged;

  @override
  State<_PermissionsDialog> createState() => _PermissionsDialogState();
}

class _PermissionsDialogState extends State<_PermissionsDialog> {
  late List<String> _codes = [...widget.codes];
  final TextEditingController _code = TextEditingController();
  bool _busy = false;

  static const _knownCodes = [
    'admin.users.manage',
    'doctors.verify',
    'facilities.verify',
    'blood_requests.verify',
    'campaigns.verify',
    'education.review',
    'community.moderate',
    'notifications.broadcast',
    'audit_logs.view',
    'audit_logs.export',
    'admin.audit.read',
    'admin.roles.manage',
    'analytics.view',
  ];

  Future<void> _toggle(String code, {required bool grant}) async {
    final reason = await promptReason(
      context: context,
      title: '${grant ? 'Grant' : 'Revoke'} $code',
      hint: 'Reason for the change (min 5 characters)',
    );
    if (reason == null || !mounted) return;
    setState(() => _busy = true);
    try {
      final updated = await widget.repository.setRolePermission(
        access: widget.accessToken,
        roleCode: widget.role.code,
        permissionCode: code,
        grant: grant,
        reason: reason,
      );
      if (!mounted) return;
      setState(() {
        _codes = updated;
        _busy = false;
      });
      widget.onChanged();
    } on Exception {
      if (!mounted) return;
      setState(() => _busy = false);
      showAdminMessage(
          context, grant ? 'Could not grant the permission.' : 'Could not revoke the permission.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: Text('Permissions · ${widget.role.code}'),
      content: SizedBox(
        width: 460,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final code in _codes)
                  InputChip(
                    label: Text(code, style: const TextStyle(fontSize: 12)),
                    onDeleted: widget.canWrite
                        ? () => _toggle(code, grant: false)
                        : null,
                    deleteIconColor: theme.colorScheme.error,
                  ),
                if (_codes.isEmpty)
                  const Text('No permission codes granted.'),
              ],
            ),
            if (widget.canWrite) ...[
              const SizedBox(height: AppSpacing.md),
              TextField(
                controller: _code,
                decoration: const InputDecoration(
                  labelText: 'Permission code',
                  hintText: 'e.g. education.review',
                  isDense: true,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final known in _knownCodes)
                    ActionChip(
                      label: Text(known, style: const TextStyle(fontSize: 11)),
                      visualDensity: VisualDensity.compact,
                      onPressed: () =>
                          setState(() => _code.text = known),
                    ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              if (_busy) const LinearProgressIndicator(),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
        if (widget.canWrite)
          FilledButton.icon(
            onPressed: _busy
                ? null
                : () {
                    final code = _code.text.trim();
                    if (code.isEmpty) return;
                    if (_codes.contains(code)) {
                      showAdminMessage(context, 'Code already granted.');
                      return;
                    }
                    _toggle(code, grant: true);
                  },
            icon: const Icon(Icons.add_circle_outline, size: 18),
            label: const Text('Grant'),
          ),
      ],
    );
  }
}