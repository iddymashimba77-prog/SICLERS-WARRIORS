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

/// Structured assessments list + create form (§2).
///
/// The server validates codes and consent; the client only offers the
/// supported concern/impression/risk choices — no scoring, no diagnosis.
class PsychologyAssessmentsPage extends StatelessWidget {
  const PsychologyAssessmentsPage({super.key, this.authController, this.repository});

  final AuthController? authController;
  final PsychologyRepository? repository;

  @override
  Widget build(BuildContext context) {
    final token =
        (authController ?? SessionScope.controllerOf(context)).accessToken;
    if (token == null) return const SignedOutGate();
    return _AssessmentsView(
      accessToken: token,
      repository: repository ??
          PsychologyRepository(tokenStore: EphemeralTokenStore()),
    );
  }
}

class _AssessmentsView extends StatefulWidget {
  const _AssessmentsView({required this.accessToken, required this.repository});

  final String accessToken;
  final PsychologyRepository repository;

  @override
  State<_AssessmentsView> createState() => _AssessmentsViewState();
}

class _AssessmentsViewState extends State<_AssessmentsView> {
  List<PsychologyAssessment> _items = const [];
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
        widget.repository.listAssessments(access: widget.accessToken),
        widget.repository.caseload(access: widget.accessToken),
      ]);
      if (!mounted) return;
      setState(() {
        _items = results[0] as List<PsychologyAssessment>;
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
      builder: (_) => _AssessmentDialog(
        accessToken: widget.accessToken,
        repository: widget.repository,
        patients: _patients,
      ),
    );
    if (created == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppStrings.psychAssessmentSaved)),
      );
      await _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(AppStrings.psychAssessments),
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
        label: Text(AppStrings.psychNewAssessment),
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
      return EmptyStateView(message: AppStrings.psychAssessmentsEmpty);
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
                    '${AppStrings.psychRisk}: ${AppStrings.codeLabel(item.riskLevel)}'
                    ' · ${AppStrings.psychImpression}: ${AppStrings.codeLabel(item.impression)}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  Text(
                    item.concerns.map(AppStrings.concernLabel).join(', '),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  if (item.notes.isNotEmpty)
                    Text(
                      item.notes,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
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

class _AssessmentDialog extends StatefulWidget {
  const _AssessmentDialog({
    required this.accessToken,
    required this.repository,
    required this.patients,
  });

  final String accessToken;
  final PsychologyRepository repository;
  final List<PsychologyCaseloadEntry> patients;

  @override
  State<_AssessmentDialog> createState() => _AssessmentDialogState();
}

class _AssessmentDialogState extends State<_AssessmentDialog> {
  PsychologyCaseloadEntry? _patient;
  final Set<String> _concerns = {};
  String _impression = 'NONE';
  String _risk = 'ROUTINE';
  final _notes = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final patient = _patient;
    if (patient == null || _concerns.isEmpty) {
      setState(() => _error = AppStrings.psychConcerns);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.repository.createAssessment(
        access: widget.accessToken,
        patientUid: patient.patientUid,
        concerns: _concerns.toList(),
        impression: _impression,
        riskLevel: _risk,
        notes: _notes.text.trim(),
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
      title: Text(AppStrings.psychNewAssessment),
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
            Text(AppStrings.psychConcerns,
                style: Theme.of(context).textTheme.labelLarge),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                for (final code in psychologyConcernCodes)
                  FilterChip(
                    label: Text(
                      AppStrings.concernLabel(code),
                      style: const TextStyle(fontSize: 12),
                    ),
                    selected: _concerns.contains(code),
                    onSelected: _busy
                        ? null
                        : (selected) => setState(() {
                              selected
                                  ? _concerns.add(code)
                                  : _concerns.remove(code);
                            }),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _impression,
              decoration: InputDecoration(labelText: AppStrings.psychImpression),
              items: [
                DropdownMenuItem(value: 'NONE', child: Text(AppStrings.codeLabel('NONE'))),
                DropdownMenuItem(value: 'MILD', child: Text(AppStrings.codeLabel('MILD'))),
                DropdownMenuItem(value: 'MODERATE', child: Text(AppStrings.codeLabel('MODERATE'))),
                DropdownMenuItem(value: 'SEVERE', child: Text(AppStrings.codeLabel('SEVERE'))),
              ],
              onChanged: (_busy) ? null : (v) => setState(() => _impression = v ?? 'NONE'),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _risk,
              decoration: InputDecoration(labelText: AppStrings.psychRisk),
              items: [
                DropdownMenuItem(value: 'ROUTINE', child: Text(AppStrings.codeLabel('ROUTINE'))),
                DropdownMenuItem(value: 'MONITOR', child: Text(AppStrings.codeLabel('MONITOR'))),
                DropdownMenuItem(value: 'URGENT', child: Text(AppStrings.codeLabel('URGENT'))),
              ],
              onChanged: (_busy) ? null : (v) => setState(() => _risk = v ?? 'ROUTINE'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _notes,
              maxLines: 3,
              decoration: InputDecoration(labelText: AppStrings.psychClinicalNotes),
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
