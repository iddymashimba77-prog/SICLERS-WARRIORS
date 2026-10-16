import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/l10n/app_localizations.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../auth/data/token_store.dart';
import '../../../auth/presentation/widgets/session_scope.dart';
import '../../data/admin_models.dart';
import '../../data/admin_repository.dart';
import '../widgets/admin_widgets.dart';
import '../../../../core/theme/app_shapes.dart';

/// System broadcast (ADMIN-3) — POST /api/admin/notifications/broadcast/
/// creates IN_APP SYSTEM notifications for the chosen audience
/// (notifications.broadcast).
class AdminBroadcastPage extends StatelessWidget {
  const AdminBroadcastPage({super.key, this.repository, this.accessToken});

  static const String routeName = '/admin/broadcast';

  final AdminRepository? repository;
  final String? accessToken;

  @override
  Widget build(BuildContext context) {
    final session = SessionScope.controllerOf(context);
    final token = accessToken ?? session.accessToken;
    if (token == null) return Center(child: Text(tr('admin.notSignedIn')));
    return _BroadcastView(
      accessToken: token,
      repository: repository ?? AdminRepository(tokenStore: EphemeralTokenStore()),
    );
  }
}

class _BroadcastView extends StatefulWidget {
  const _BroadcastView({required this.accessToken, required this.repository});

  final String accessToken;
  final AdminRepository repository;

  @override
  State<_BroadcastView> createState() => _BroadcastViewState();
}

class _BroadcastViewState extends State<_BroadcastView> {
  final _formKey = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _body = TextEditingController();
  final _roleCode = TextEditingController();
  final _userUids = TextEditingController();
  String _audience = 'ALL';
  bool _sending = false;
  AdminBroadcastResult? _result;

  @override
  Widget build(BuildContext context) {
    return Form(
      key: _formKey,
      child: ListView(
        padding: const EdgeInsets.all(AppSpacing.xl),
        children: [
          AdminSectionHeader(
            title: tr('admin.nav.broadcast'),
            subtitle: tr('admin.broadcastSubtitle'),
          ),
          const SizedBox(height: AppSpacing.sm),
          DropdownButtonFormField<String>(
            initialValue: _audience,
            decoration: InputDecoration(labelText: tr('admin.audience')),
            items: [
              DropdownMenuItem(value: 'ALL', child: Text(tr('admin.allUsers'))),
              DropdownMenuItem(value: 'ROLE', child: Text(tr('admin.aRole'))),
              DropdownMenuItem(
                  value: 'USERS', child: Text(tr('admin.specificUsers'))),
            ],
            onChanged: (value) => setState(() => _audience = value ?? 'ALL'),
          ),
          const SizedBox(height: AppSpacing.md),
          TextFormField(
            controller: _title,
            decoration: InputDecoration(labelText: tr('admin.fieldTitle')),
            textInputAction: TextInputAction.next,
            validator: (v) =>
                (v == null || v.trim().isEmpty) ? tr('admin.titleRequired') : null,
          ),
          const SizedBox(height: AppSpacing.md),
          if (_audience == 'ROLE') ...[
            TextFormField(
              controller: _roleCode,
              decoration: InputDecoration(
                labelText: tr('admin.roleCode'),
                hintText: tr('admin.roleCodeExample'),
              ),
              validator: (v) => (v == null || v.trim().isEmpty)
                  ? tr('admin.roleCodeRequired')
                  : null,
            ),
            const SizedBox(height: AppSpacing.md),
          ],
          if (_audience == 'USERS') ...[
            TextFormField(
              controller: _userUids,
              decoration: InputDecoration(
                labelText: tr('admin.userUids'),
                hintText: tr('admin.userUidsHint'),
              ),
              validator: (v) => (v == null || v.trim().isEmpty)
                  ? tr('admin.uidsRequired')
                  : null,
            ),
            const SizedBox(height: AppSpacing.md),
          ],
          TextFormField(
            controller: _body,
            decoration: InputDecoration(labelText: tr('admin.message')),
            maxLines: 6,
            validator: (v) =>
                (v == null || v.trim().isEmpty) ? tr('admin.messageRequired') : null,
          ),
          const SizedBox(height: AppSpacing.lg),
          if (_sending)
            const LinearProgressIndicator()
          else if (_result != null)
            Container(
              margin: const EdgeInsets.only(bottom: AppSpacing.md),
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: AppColors.success.withValues(alpha: 0.1),
                borderRadius: AppShapes.tile,
              ),
              child: Text(
                '${tr('admin.sentTo').replaceAll('{count}', '${_result!.recipientCount}')}'
                '${_result!.audience.isEmpty ? '' : ' (${_result!.audience})'}.',
                style: const TextStyle(color: AppColors.success),
              ),
            ),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.icon(
              onPressed: _sending ? null : _send,
              icon: const Icon(Icons.send_outlined, size: 18),
              label: Text(tr('admin.sendBroadcast')),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _send() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _sending = true;
      _result = null;
    });
    try {
      final result = await widget.repository.broadcast(
        access: widget.accessToken,
        audience: _audience,
        title: _title.text.trim(),
        body: _body.text.trim(),
        roleCode: _audience == 'ROLE' ? _roleCode.text.trim() : null,
        userUids: _audience == 'USERS'
            ? _userUids.text
                .split(',')
                .map((s) => s.trim())
                .where((s) => s.isNotEmpty)
                .toList()
            : null,
      );
      if (!mounted) return;
      setState(() {
        _result = result;
        _sending = false;
      });
    } on Exception {
      if (!mounted) return;
      setState(() => _sending = false);
      showAdminMessage(context, tr('admin.couldNotBroadcast'));
    }
  }
}