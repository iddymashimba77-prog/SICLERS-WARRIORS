import 'package:flutter/material.dart';

import '../../../../core/l10n/app_localizations.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../auth/data/token_store.dart';
import '../../../auth/presentation/widgets/session_scope.dart';
import '../../data/admin_models.dart';
import '../../data/admin_repository.dart';
import '../widgets/admin_widgets.dart';

/// Admin user management (ADMIN-3) — GET /api/admin/users/ + status/roles
/// actions. Every mutation requires a reason (server-audited) and the write is
/// re-validated server-side by `admin.users.manage`.
class AdminUsersPage extends StatelessWidget {
  const AdminUsersPage({super.key, this.repository, this.accessToken});

  static const String routeName = '/admin/users';

  final AdminRepository? repository;
  final String? accessToken;

  @override
  Widget build(BuildContext context) {
    final session = SessionScope.controllerOf(context);
    final token = accessToken ?? session.accessToken;
    if (token == null) {
      return Center(
        child: Text(AppLocalizations.of(context).tr('admin.notSignedIn')),
      );
    }
    return _UsersView(
      accessToken: token,
      repository: repository ?? AdminRepository(tokenStore: EphemeralTokenStore()),
    );
  }
}

class _UsersView extends StatefulWidget {
  const _UsersView({required this.accessToken, required this.repository});

  final String accessToken;
  final AdminRepository repository;

  @override
  State<_UsersView> createState() => _UsersViewState();
}

class _UsersViewState extends State<_UsersView> {
  final GlobalKey<AdminAsyncListState<AdminUser>> _listKey =
      GlobalKey<AdminAsyncListState<AdminUser>>();
  String _status = '';
  final TextEditingController _search = TextEditingController();

  Future<List<AdminUser>> _load() => widget.repository.listUsers(
        access: widget.accessToken,
        status: _status.isEmpty ? null : _status,
        query: _search.text.trim(),
      );

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context);
    return ListView(
      children: [
        AdminSectionHeader(
          title: s.tr('admin.nav.users'),
          subtitle: s.tr('admin.usersSubtitle'),
          trailing: _FilterButtons(
            current: _status,
            onChanged: (value) {
              setState(() => _status = value);
              _listKey.currentState?.reload();
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
          child: TextField(
            controller: _search,
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search),
              hintText: s.tr('admin.searchUsers'),
              isDense: true,
            ),
            onSubmitted: (_) => _listKey.currentState?.reload(),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        AdminAsyncList<AdminUser>(
          key: _listKey,
          load: _load,
          emptyIcon: Icons.groups_outlined,
          emptyTitle: s.tr('admin.noUsersMatch'),
          emptyMessage: s.tr('admin.adjustFilter'),
          itemBuilder: (context, user) => _UserCard(
            user: user,
            repository: widget.repository,
            accessToken: widget.accessToken,
            onChanged: () => _listKey.currentState?.reload(),
          ),
        ),
      ],
    );
  }
}

class _FilterButtons extends StatelessWidget {
  const _FilterButtons({required this.current, required this.onChanged});

  final String current;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context);
    return Wrap(
      spacing: 8,
      children: [
        for (final filter in [
          ('', s.tr('admin.filter.all')),
          ('PENDING_VERIFICATION', s.tr('admin.filter.pending')),
          ('ACTIVE', s.tr('admin.filter.active')),
          ('SUSPENDED', s.tr('admin.filter.suspended')),
          ('DEACTIVATED', s.tr('admin.filter.deactivated')),
        ])
          ChoiceChip(
            label: Text(filter.$2),
            selected: current == filter.$1,
            onSelected: (_) => onChanged(filter.$1),
          ),
      ],
    );
  }
}

class _UserCard extends StatelessWidget {
  const _UserCard({
    required this.user,
    required this.repository,
    required this.accessToken,
    required this.onChanged,
  });

  final AdminUser user;
  final AdminRepository repository;
  final String accessToken;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = AppLocalizations.of(context);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        user.fullName.isEmpty ? user.email : user.fullName,
                        style: theme.textTheme.titleMedium,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        user.email,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                AdminStatusChip(status: user.accountStatus),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final role in user.roleCodes)
                  Chip(
                    label: Text(role, style: const TextStyle(fontSize: 11)),
                    visualDensity: VisualDensity.compact,
                  ),
                if (user.mfaEnabled)
                  const Chip(
                    label: Text('MFA', style: TextStyle(fontSize: 11)),
                    visualDensity: VisualDensity.compact,
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton.icon(
                  onPressed: () => _openRoles(context),
                  icon: const Icon(Icons.security_outlined, size: 18),
                  label: Text(s.tr('admin.rolesBtn')),
                ),
                if (user.isActive)
                  TextButton.icon(
                    onPressed: () => _deactivate(context),
                    icon: const Icon(Icons.block_outlined, size: 18),
                    label: Text(s.tr('admin.deactivate')),
                  )
                else
                  TextButton.icon(
                    onPressed: () => _activate(context),
                    icon: const Icon(Icons.check_circle_outline, size: 18),
                    label: Text(s.tr('admin.activate')),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _activate(BuildContext context) async {
    final s = AppLocalizations.of(context);
    final reason = await promptReason(
      context: context,
      title: s
          .tr('admin.activateUser')
          .replaceAll('{user}',
              user.fullName.isEmpty ? user.email : user.fullName),
    );
    if (reason == null) return;
    try {
      await repository.setUserStatus(
        access: accessToken,
        uid: user.uid,
        activate: true,
        reason: reason,
      );
      if (!context.mounted) return;
      onChanged();
      showAdminMessage(context, s.tr('admin.accountActivated'));
    } on Exception {
      if (!context.mounted) return;
      showAdminMessage(context, s.tr('admin.couldNotActivate'));
    }
  }

  Future<void> _deactivate(BuildContext context) async {
    final s = AppLocalizations.of(context);
    final reason = await promptReason(
      context: context,
      title: s
          .tr('admin.deactivateUser')
          .replaceAll('{user}',
              user.fullName.isEmpty ? user.email : user.fullName),
      hint: s.tr('admin.reasonDeactivation'),
    );
    if (reason == null) return;
    try {
      await repository.setUserStatus(
        access: accessToken,
        uid: user.uid,
        activate: false,
        reason: reason,
      );
      if (!context.mounted) return;
      onChanged();
      showAdminMessage(context, s.tr('admin.accountDeactivated'));
    } on Exception {
      if (!context.mounted) return;
      showAdminMessage(context, s.tr('admin.couldNotDeactivate'));
    }
  }

  Future<void> _openRoles(BuildContext context) async {
    final s = AppLocalizations.of(context);
    List<String> roles;
    try {
      roles = await repository.getUserRoles(access: accessToken, uid: user.uid);
    } on Exception {
      if (context.mounted) {
        showAdminMessage(context, s.tr('admin.couldNotLoadRoles'));
      }
      return;
    }
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => _RolesDialog(
        user: user,
        roles: roles,
        repository: repository,
        accessToken: accessToken,
        onChanged: onChanged,
      ),
    );
  }
}

class _RolesDialog extends StatefulWidget {
  const _RolesDialog({
    required this.user,
    required this.roles,
    required this.repository,
    required this.accessToken,
    required this.onChanged,
  });

  final AdminUser user;
  final List<String> roles;
  final AdminRepository repository;
  final String accessToken;
  final VoidCallback onChanged;

  @override
  State<_RolesDialog> createState() => _RolesDialogState();
}

class _RolesDialogState extends State<_RolesDialog> {
  late List<String> _roles = [...widget.roles];
  final TextEditingController _roleCode = TextEditingController();
  bool _busy = false;

  Future<void> _save({required bool grant}) async {
    final s = AppLocalizations.of(context);
    final code = _roleCode.text.trim().toUpperCase();
    if (code.isEmpty) {
      showAdminMessage(context, s.tr('admin.enterRoleCode'));
      return;
    }
    final reason = await promptReason(
      context: context,
      title: (grant ? s.tr('admin.grantX') : s.tr('admin.revokeX'))
          .replaceAll('{code}', code),
      hint: s.tr('admin.reasonChange'),
    );
    if (reason == null || !mounted) return;
    setState(() => _busy = true);
    try {
      final updated = await widget.repository.changeUserRole(
        access: widget.accessToken,
        uid: widget.user.uid,
        roleCode: code,
        grant: grant,
        reason: reason,
      );
      if (!mounted) return;
      setState(() {
        _roles = updated.roleCodes;
        _roleCode.clear();
        _busy = false;
      });
      widget.onChanged();
    } on Exception {
      if (!mounted) return;
      setState(() => _busy = false);
      showAdminMessage(
        context,
        s.tr(grant ? 'admin.couldNotGrantRole' : 'admin.couldNotRevokeRole'),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(s.tr('admin.rolesOf').replaceAll('{email}', widget.user.email)),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final role in _roles)
                  Chip(label: Text(role), visualDensity: VisualDensity.compact),
                if (_roles.isEmpty)
                  Text(s.tr('admin.noRolesAssigned')),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: _roleCode,
              decoration: InputDecoration(
                labelText: s.tr('admin.roleCode'),
                hintText: s.tr('admin.roleCodeHint'),
                isDense: true,
              ),
              textCapitalization: TextCapitalization.characters,
            ),
            const SizedBox(height: AppSpacing.sm),
            if (_busy) const LinearProgressIndicator(),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(s.tr('common.close')),
        ),
        TextButton.icon(
          onPressed: _busy ? null : () => _save(grant: false),
          icon: const Icon(Icons.remove_circle_outline, size: 18),
          label: Text(s.tr('admin.revoke')),
        ),
        FilledButton.icon(
          onPressed: _busy ? null : () => _save(grant: true),
          icon: const Icon(Icons.add_circle_outline, size: 18),
          label: Text(s.tr('admin.grant')),
        ),
      ],
    );
  }
}