import 'package:flutter/material.dart';

import '../../../../core/constants/app_strings.dart';
import '../../../../core/l10n/app_localizations.dart';
import '../../../../shared/widgets/state_views.dart';
import '../../../auth/domain/auth_types.dart';
import '../../data/social_work_repository.dart';

/// One case: header, allowed status moves (mirrors backend `TRANSITIONS`,
/// which has the final word), and its chronological notes.
class SocialCaseDetailPage extends StatefulWidget {
  const SocialCaseDetailPage({
    super.key,
    required this.accessToken,
    required this.repository,
    required this.caseUid,
  });

  final String accessToken;
  final SocialWorkRepository repository;
  final String caseUid;

  @override
  State<SocialCaseDetailPage> createState() => _SocialCaseDetailPageState();
}

const Map<String, List<String>> _caseTransitions = {
  'NEW': ['IN_PROGRESS', 'AWAITING_REFERRAL', 'RESOLVED'],
  'IN_PROGRESS': ['AWAITING_REFERRAL', 'RESOLVED'],
  'AWAITING_REFERRAL': ['IN_PROGRESS', 'RESOLVED'],
  'RESOLVED': ['IN_PROGRESS'],
};

class _SocialCaseDetailPageState extends State<SocialCaseDetailPage> {
  SocialCase? _case;
  List<SocialCaseNote> _notes = const [];
  Object? _error;
  bool _loading = true;
  bool _busy = false;

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
      final results = await Future.wait([
        widget.repository.getCase(
            access: widget.accessToken, uid: widget.caseUid),
        widget.repository.listCaseNotes(
            access: widget.accessToken, caseUid: widget.caseUid),
      ]);
      if (!mounted) return;
      setState(() {
        _case = results[0] as SocialCase;
        _notes = results[1] as List<SocialCaseNote>;
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

  String _messageFor(Object error) {
    if (error is AuthException) {
      final message = error.message.trim();
      if (message.isNotEmpty && !message.contains('Exception')) return message;
    }
    return AppStrings.socialLoadFailed;
  }

  String _when(String iso) =>
      DateTime.tryParse(iso)?.toLocal().toString().split('.').first ?? iso;

  Future<void> _moveTo(String status) async {
    final item = _case;
    if (item == null || _busy) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(AppStrings.socialCaseStatus),
        content: Text('${item.title} → ${AppStrings.codeLabel(status)}'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(AppStrings.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(AppStrings.save),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await widget.repository.updateCaseStatus(
        access: widget.accessToken,
        uid: item.uid,
        status: status,
      );
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppStrings.socialCaseUpdated)),
      );
      await _load();
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content:
              Text(e is AuthException ? e.message : AppStrings.socialLoadFailed),
        ),
      );
    }
  }

  Future<void> _addNote() async {
    final item = _case;
    if (item == null) return;
    final created = await showDialog<bool>(
      context: context,
      builder: (_) => _NoteDialog(
        accessToken: widget.accessToken,
        repository: widget.repository,
        caseUid: item.uid,
      ),
    );
    if (created == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppStrings.socialNoteSaved)),
      );
      await _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context);
    final item = _case;
    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: Text(AppStrings.socialCases)),
        body: LoadingView(label: s.tr('common.loading')),
      );
    }
    if (_error != null || item == null) {
      return Scaffold(
        appBar: AppBar(title: Text(AppStrings.socialCases)),
        body: ErrorRetryView(
            message: _messageFor(_error ?? Exception('')), onRetry: _load),
      );
    }
    final allowed = _caseTransitions[item.status] ?? const <String>[];
    return Scaffold(
      appBar: AppBar(title: Text(item.title)),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addNote,
        icon: const Icon(Icons.add),
        label: Text(AppStrings.socialAddNote),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(item.patientName,
                        style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        Chip(
                          label: Text(AppStrings.codeLabel(item.status)),
                          visualDensity: VisualDensity.compact,
                        ),
                        Chip(
                          label: Text(_when(item.openedAt)),
                          visualDensity: VisualDensity.compact,
                        ),
                        if (item.closedAt != null)
                          Chip(
                            label: Text(_when(item.closedAt!)),
                            visualDensity: VisualDensity.compact,
                          ),
                      ],
                    ),
                    if (item.linkedWorkflow.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        '${AppStrings.socialLinkedWorkflow}: ${item.linkedWorkflow}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                    if (allowed.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final status in allowed)
                            FilledButton.tonal(
                              onPressed:
                                  _busy ? null : () => _moveTo(status),
                              child: Text(AppStrings.codeLabel(status)),
                            ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            if (_notes.isEmpty)
              EmptyStateView(message: AppStrings.socialNotesEmpty)
            else ...[
              Text(AppStrings.socialNotes,
                  style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 8),
              for (final note in _notes)
                Card(
                  child: ListTile(
                    title: Text(note.authorName),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_when(note.createdAt),
                            style: Theme.of(context).textTheme.bodySmall),
                        Text(note.note),
                      ],
                    ),
                    isThreeLine: true,
                  ),
                ),
            ],
            const SizedBox(height: 72),
          ],
        ),
      ),
    );
  }
}

class _NoteDialog extends StatefulWidget {
  const _NoteDialog({
    required this.accessToken,
    required this.repository,
    required this.caseUid,
  });

  final String accessToken;
  final SocialWorkRepository repository;
  final String caseUid;

  @override
  State<_NoteDialog> createState() => _NoteDialogState();
}

class _NoteDialogState extends State<_NoteDialog> {
  final _note = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_note.text.trim().isEmpty) {
      setState(() => _error = AppStrings.socialAddNote);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.repository.addCaseNote(
        access: widget.accessToken,
        caseUid: widget.caseUid,
        note: _note.text.trim(),
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e is AuthException ? e.message : AppStrings.socialLoadFailed;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(AppStrings.socialAddNote),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _note,
            maxLines: 5,
            decoration: InputDecoration(labelText: AppStrings.socialAddNote),
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!,
                style:
                    TextStyle(color: Theme.of(context).colorScheme.error)),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(false),
          child: Text(AppStrings.cancel),
        ),
        FilledButton(
          onPressed: _busy ? null : _submit,
          child: Text(_busy ? '…' : AppStrings.save),
        ),
      ],
    );
  }
}
