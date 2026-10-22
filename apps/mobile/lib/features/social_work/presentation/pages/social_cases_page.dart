import 'package:flutter/material.dart';

import '../../../../core/constants/app_strings.dart';
import '../../../../core/l10n/app_localizations.dart';
import '../../../../shared/widgets/signed_out_gate.dart';
import '../../../../shared/widgets/state_views.dart';
import '../../../auth/data/token_store.dart';
import '../../../auth/domain/auth_types.dart';
import '../../../auth/presentation/controllers/auth_controller.dart';
import '../../../auth/presentation/widgets/session_scope.dart';
import '../../data/social_work_repository.dart';
import 'social_case_detail_page.dart';

/// Social-support cases list + create (§3). No money fields — `linked_workflow`
/// is a plain-text pointer to an existing campaign/donation workflow.
class SocialCasesPage extends StatelessWidget {
  const SocialCasesPage({super.key, this.authController, this.repository});

  final AuthController? authController;
  final SocialWorkRepository? repository;

  @override
  Widget build(BuildContext context) {
    final token =
        (authController ?? SessionScope.controllerOf(context)).accessToken;
    if (token == null) return const SignedOutGate();
    return _CasesView(
      accessToken: token,
      repository: repository ??
          SocialWorkRepository(tokenStore: EphemeralTokenStore()),
    );
  }
}

class _CasesView extends StatefulWidget {
  const _CasesView({required this.accessToken, required this.repository});

  final String accessToken;
  final SocialWorkRepository repository;

  @override
  State<_CasesView> createState() => _CasesViewState();
}

class _CasesViewState extends State<_CasesView> {
  List<SocialCase> _items = const [];
  List<SocialCaseloadEntry> _patients = const [];
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
        widget.repository.listCases(access: widget.accessToken),
        widget.repository.caseload(access: widget.accessToken),
      ]);
      if (!mounted) return;
      setState(() {
        _items = results[0] as List<SocialCase>;
        _patients = results[1] as List<SocialCaseloadEntry>;
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

  Future<void> _create() async {
    final created = await showDialog<bool>(
      context: context,
      builder: (_) => _CaseDialog(
        accessToken: widget.accessToken,
        repository: widget.repository,
        patients: _patients,
      ),
    );
    if (created == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppStrings.socialCaseSaved)),
      );
      await _load();
    }
  }

  Future<void> _open(SocialCase item) async {
    final updated = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => SocialCaseDetailPage(
          accessToken: widget.accessToken,
          repository: widget.repository,
          caseUid: item.uid,
        ),
      ),
    );
    if (updated == true && mounted) await _load();
  }

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(AppStrings.socialCases),
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
        label: Text(AppStrings.socialNewCase),
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
      return EmptyStateView(message: AppStrings.socialCasesEmpty);
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
              leading: const Icon(Icons.folder_special_outlined),
              title: Text(item.title),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${item.patientName} · ${AppStrings.codeLabel(item.status)}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  if (item.linkedWorkflow.isNotEmpty)
                    Text(
                      '${AppStrings.socialLinkedWorkflow}: ${item.linkedWorkflow}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                ],
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _open(item),
            ),
          );
        },
      ),
    );
  }
}

class _CaseDialog extends StatefulWidget {
  const _CaseDialog({
    required this.accessToken,
    required this.repository,
    required this.patients,
  });

  final String accessToken;
  final SocialWorkRepository repository;
  final List<SocialCaseloadEntry> patients;

  @override
  State<_CaseDialog> createState() => _CaseDialogState();
}

class _CaseDialogState extends State<_CaseDialog> {
  SocialCaseloadEntry? _patient;
  final _title = TextEditingController();
  final _linkedWorkflow = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _title.dispose();
    _linkedWorkflow.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final patient = _patient;
    if (patient == null || _title.text.trim().isEmpty) {
      setState(() => _error = AppStrings.socialCaseTitle);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.repository.createCase(
        access: widget.accessToken,
        patientUid: patient.patientUid,
        title: _title.text.trim(),
        linkedWorkflow: _linkedWorkflow.text.trim(),
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
      title: Text(AppStrings.socialNewCase),
      content: SizedBox(
        width: double.maxFinite,
        child: ListView(
          shrinkWrap: true,
          children: [
            DropdownButtonFormField<SocialCaseloadEntry>(
              initialValue: _patient,
              decoration: InputDecoration(labelText: AppStrings.socialPatient),
              items: [
                for (final p in widget.patients)
                  DropdownMenuItem(value: p, child: Text(p.patientName)),
              ],
              onChanged: (_busy) ? null : (v) => setState(() => _patient = v),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _title,
              decoration: InputDecoration(labelText: AppStrings.socialCaseTitle),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _linkedWorkflow,
              decoration: InputDecoration(
                labelText: AppStrings.socialLinkedWorkflow,
                helperText: AppStrings.socialLinkedWorkflowHint,
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!,
                  style:
                      TextStyle(color: Theme.of(context).colorScheme.error)),
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
