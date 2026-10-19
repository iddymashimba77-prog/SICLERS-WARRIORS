import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../core/constants/app_strings.dart';
import '../../../../core/l10n/app_localizations.dart';
import '../../../../shared/widgets/state_views.dart';
import '../../data/chat_repository.dart';

/// Recipient picker for a new private conversation (FR-DOC-005 / UR-01).
///
/// Replaces the old "type a verified professional UID" dialog: rows come from
/// `GET /api/chat/recipients/`, which the server builds with the same rules
/// `POST /chat/conversations/` enforces — patients are only ever offered
/// APPROVED professionals (C13b stays a server-side gate), professionals are
/// only offered patients, and roles without `chat.start` never see compose at
/// all. Nobody pastes identifiers by hand, and verification is still not
/// something the client can bypass.
///
/// Returns the chosen recipient's uid, or `null` when dismissed.
Future<String?> showRecipientPicker({
  required BuildContext context,
  required ChatRepository repository,
  required String accessToken,
}) {
  return showDialog<String>(
    context: context,
    builder: (_) => RecipientPickerDialog(
      repository: repository,
      accessToken: accessToken,
    ),
  );
}

class RecipientPickerDialog extends StatefulWidget {
  const RecipientPickerDialog({
    super.key,
    required this.repository,
    required this.accessToken,
  });

  final ChatRepository repository;
  final String accessToken;

  @override
  State<RecipientPickerDialog> createState() => _RecipientPickerDialogState();
}

class _RecipientPickerDialogState extends State<RecipientPickerDialog> {
  final TextEditingController _query = TextEditingController();
  List<ChatRecipient>? _rows;
  Object? _error;
  bool _loading = true;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _query.dispose();
    super.dispose();
  }

  Future<void> _load({String query = ''}) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rows = await widget.repository.listRecipients(
        access: widget.accessToken,
        query: query,
      );
      if (!mounted) return;
      setState(() {
        _rows = rows;
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

  void _onQueryChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      if (!mounted) return;
      _load(query: value);
    });
  }

  IconData _roleIcon(String role) {
    switch (role) {
      case 'DOCTOR':
        return Icons.medical_services_outlined;
      case 'PSYCHOLOGIST':
        return Icons.psychology_outlined;
      case 'SOCIAL_SUPPORT':
        return Icons.handshake_outlined;
      case 'HEALTHCARE_STAFF':
        return Icons.health_and_safety_outlined;
      default:
        return Icons.person_outline;
    }
  }

  String _roleLabel(AppLocalizations s, String role) {
    switch (role) {
      case 'DOCTOR':
        return s.tr('role.doctor');
      case 'PSYCHOLOGIST':
        return s.tr('role.psychologist');
      case 'SOCIAL_SUPPORT':
        return s.tr('role.socialSupport');
      case 'HEALTHCARE_STAFF':
        return s.tr('role.healthcareStaff');
      case 'PATIENT':
        return s.tr('role.patient');
      default:
        return role;
    }
  }

  Widget _buildList(AppLocalizations s) {
    final rows = _rows;
    if (rows == null) {
      if (_error != null) {
        return ErrorRetryView(
          message: AppStrings.conversationsLoadFailed,
          onRetry: () => _load(query: _query.text),
        );
      }
      return const LoadingView();
    }
    if (rows.isEmpty && _error == null) {
      return EmptyStateView(
        message: s.tr('chat.noRecipients'),
        icon: Icons.people_outline,
      );
    }
    if (rows.isEmpty) {
      return ErrorRetryView(
        message: AppStrings.conversationsLoadFailed,
        onRetry: () => _load(query: _query.text),
      );
    }
    return ListView.separated(
      itemCount: rows.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (_, i) {
        final row = rows[i];
        final roleLabel = _roleLabel(s, row.role);
        final subtitle =
            row.detail.isEmpty ? roleLabel : '$roleLabel · ${row.detail}';
        return ListTile(
          leading: CircleAvatar(child: Icon(_roleIcon(row.role))),
          title: Text(row.displayName),
          subtitle: Text(subtitle),
          onTap: () => Navigator.pop(context, row.uid),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(s.tr('chat.newConversation')),
      content: SizedBox(
        width: double.maxFinite,
        height: 360,
        child: Column(
          children: [
            TextField(
              controller: _query,
              onChanged: _onQueryChanged,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                labelText: s.tr('chat.searchPeople'),
                prefixIcon: const Icon(Icons.search),
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            if (_loading && _rows != null) const LinearProgressIndicator(),
            Expanded(child: _buildList(s)),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(AppStrings.cancel),
        ),
      ],
    );
  }
}
