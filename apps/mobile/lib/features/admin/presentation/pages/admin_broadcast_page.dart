import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
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
    if (token == null) return const Center(child: Text('Not signed in.'));
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
            title: 'Broadcast',
            subtitle: 'Send a system notification to a chosen audience.',
          ),
          const SizedBox(height: AppSpacing.sm),
          DropdownButtonFormField<String>(
            initialValue: _audience,
            decoration: const InputDecoration(labelText: 'Audience'),
            items: const [
              DropdownMenuItem(value: 'ALL', child: Text('All users')),
              DropdownMenuItem(value: 'ROLE', child: Text('A role')),
              DropdownMenuItem(value: 'USERS', child: Text('Specific users (by uid)')),
            ],
            onChanged: (value) => setState(() => _audience = value ?? 'ALL'),
          ),
          const SizedBox(height: AppSpacing.md),
          TextFormField(
            controller: _title,
            decoration: const InputDecoration(labelText: 'Title'),
            textInputAction: TextInputAction.next,
            validator: (v) =>
                (v == null || v.trim().isEmpty) ? 'Title is required.' : null,
          ),
          const SizedBox(height: AppSpacing.md),
          if (_audience == 'ROLE') ...[
            TextFormField(
              controller: _roleCode,
              decoration: const InputDecoration(
                labelText: 'Role code',
                hintText: 'e.g. PATIENT',
              ),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Role code is required.' : null,
            ),
            const SizedBox(height: AppSpacing.md),
          ],
          if (_audience == 'USERS') ...[
            TextFormField(
              controller: _userUids,
              decoration: const InputDecoration(
                labelText: 'User uids',
                hintText: 'Comma-separated user uids',
              ),
              validator: (v) => (v == null || v.trim().isEmpty)
                  ? 'At least one user uid is required.'
                  : null,
            ),
            const SizedBox(height: AppSpacing.md),
          ],
          TextFormField(
            controller: _body,
            decoration: const InputDecoration(labelText: 'Message'),
            maxLines: 6,
            validator: (v) =>
                (v == null || v.trim().isEmpty) ? 'Message is required.' : null,
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
                'Sent to ${_result!.recipientCount} recipient(s)'
                '${_result!.audience.isEmpty ? '' : ' (${_result!.audience})'}.',
                style: const TextStyle(color: AppColors.success),
              ),
            ),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.icon(
              onPressed: _sending ? null : _send,
              icon: const Icon(Icons.send_outlined, size: 18),
              label: const Text('Send broadcast'),
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
      showAdminMessage(context, 'Could not send the broadcast.');
    }
  }
}