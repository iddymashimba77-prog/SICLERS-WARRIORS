import 'package:flutter/material.dart';

import '../../../../core/constants/app_strings.dart';
import '../../../../core/l10n/app_localizations.dart';
import '../../../../shared/widgets/signed_out_gate.dart';
import '../../../../shared/widgets/state_views.dart';
import '../../../auth/data/token_store.dart';
import '../../../auth/domain/auth_types.dart';
import '../../../auth/presentation/controllers/auth_controller.dart';
import '../../../auth/presentation/widgets/session_scope.dart';
import '../../data/psychology_repository.dart';

/// Counselling session notes list + create (§2).
class PsychologyNotesPage extends StatelessWidget {
  const PsychologyNotesPage({super.key, this.authController, this.repository});

  final AuthController? authController;
  final PsychologyRepository? repository;

  @override
  Widget build(BuildContext context) {
    final token =
        (authController ?? SessionScope.controllerOf(context)).accessToken;
    if (token == null) return const SignedOutGate();
    return _NotesView(
      accessToken: token,
      repository: repository ??
          PsychologyRepository(tokenStore: EphemeralTokenStore()),
    );
  }
}

class _NotesView extends StatefulWidget {
  const _NotesView({required this.accessToken, required this.repository});

  final String accessToken;
  final PsychologyRepository repository;

  @override
  State<_NotesView> createState() => _NotesViewState();
}

class _NotesViewState extends State<_NotesView> {
  List<PsychologyProgressNote> _items = const [];
  List<PsychologyCaseloadEntry> _patients = const [];
  Object? _error;
  bool _loading = true;

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
        widget.repository.listNotes(access: widget.accessToken),
        widget.repository.caseload(access: widget.accessToken),
      ]);
      if (!mounted) return;
      setState(() {
        _items = results[0] as List<PsychologyProgressNote>;
        _patients = results[1] as List<PsychologyCaseloadEntry>;
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
    return AppStrings.psychLoadFailed;
  }

  Future<void> _create() async {
    final created = await showDialog<bool>(
      context: context,
      builder: (_) => _NoteDialog(
        accessToken: widget.accessToken,
        repository: widget.repository,
        patients: _patients,
      ),
    );
    if (created == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppStrings.psychNoteSaved)),
      );
      await _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(AppStrings.psychNotes),
        actions: [
          IconButton(
            tooltip: s.tr('common.refresh'),
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _loading || _patients.isEmpty ? null : _create,
        icon: const Icon(Icons.add),
        label: Text(AppStrings.psychNewNote),
      ),
      body: _buildBody(s),
    );
  }

  Widget _buildBody(AppLocalizations s) {
    if (_loading) return LoadingView(label: s.tr('common.loading'));
    if (_error != null) {
      return ErrorRetryView(message: _messageFor(_error!), onRetry: _load);
    }
    if (_items.isEmpty) {
      return EmptyStateView(message: AppStrings.psychNotesEmpty);
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: _items.length,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          final item = _items[index];
          return Card(
            child: ListTile(
              title: Text(item.patientName),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${item.authorName} · ${item.sessionAt.split('T').first}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  if (item.followUpAt != null)
                    Text(
                      '${AppStrings.psychFollowUpDate}: ${item.followUpAt!.split('T').first}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  Text(
                    item.note,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
              isThreeLine: true,
            ),
          );
        },
      ),
    );
  }
}

class _NoteDialog extends StatefulWidget {
  const _NoteDialog({
    required this.accessToken,
    required this.repository,
    required this.patients,
  });

  final String accessToken;
  final PsychologyRepository repository;
  final List<PsychologyCaseloadEntry> patients;

  @override
  State<_NoteDialog> createState() => _NoteDialogState();
}

class _NoteDialogState extends State<_NoteDialog> {
  PsychologyCaseloadEntry? _patient;
  final _note = TextEditingController();
  DateTime? _followUp;
  bool _busy = false;
  String? _error;

  Future<void> _pickFollowUp() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _followUp ?? DateTime.now(),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) setState(() => _followUp = picked);
  }

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final patient = _patient;
    if (patient == null || _note.text.trim().isEmpty) {
      setState(() => _error = AppStrings.psychNewNote);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.repository.createNote(
        access: widget.accessToken,
        patientUid: patient.patientUid,
        note: _note.text.trim(),
        followUpAt: _followUp?.toUtc().toIso8601String(),
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e is AuthException ? e.message : AppStrings.psychLoadFailed;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(AppStrings.psychNewNote),
      content: SizedBox(
        width: double.maxFinite,
        child: ListView(
          shrinkWrap: true,
          children: [
            DropdownButtonFormField<PsychologyCaseloadEntry>(
              initialValue: _patient,
              decoration: InputDecoration(labelText: AppStrings.psychPatient),
              items: [
                for (final p in widget.patients)
                  DropdownMenuItem(value: p, child: Text(p.patientName)),
              ],
              onChanged: (_busy) ? null : (v) => setState(() => _patient = v),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _note,
              maxLines: 5,
              decoration: InputDecoration(labelText: AppStrings.psychNewNote),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _busy ? null : _pickFollowUp,
                    icon: const Icon(Icons.event_outlined),
                    label: Text(
                      _followUp == null
                          ? AppStrings.psychFollowUpDate
                          : _followUp!.toLocal().toString().split(' ').first,
                    ),
                  ),
                ),
                if (_followUp != null)
                  IconButton(
                    tooltip: AppStrings.cancel,
                    onPressed:
                        _busy ? null : () => setState(() => _followUp = null),
                    icon: const Icon(Icons.clear),
                  ),
              ],
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
          ],
        ),
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
