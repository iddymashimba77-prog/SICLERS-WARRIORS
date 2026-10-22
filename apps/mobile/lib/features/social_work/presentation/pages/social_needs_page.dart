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

/// Needs assessments list + create (§3): structural need codes + qualitative
/// observations — no scoring, no money, no diagnosis.
class SocialNeedsPage extends StatelessWidget {
  const SocialNeedsPage({super.key, this.authController, this.repository});

  final AuthController? authController;
  final SocialWorkRepository? repository;

  @override
  Widget build(BuildContext context) {
    final token =
        (authController ?? SessionScope.controllerOf(context)).accessToken;
    if (token == null) return const SignedOutGate();
    return _NeedsView(
      accessToken: token,
      repository: repository ??
          SocialWorkRepository(tokenStore: EphemeralTokenStore()),
    );
  }
}

class _NeedsView extends StatefulWidget {
  const _NeedsView({required this.accessToken, required this.repository});

  final String accessToken;
  final SocialWorkRepository repository;

  @override
  State<_NeedsView> createState() => _NeedsViewState();
}

class _NeedsViewState extends State<_NeedsView> {
  List<SocialNeedsAssessment> _items = const [];
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
        widget.repository.listNeeds(access: widget.accessToken),
        widget.repository.caseload(access: widget.accessToken),
      ]);
      if (!mounted) return;
      setState(() {
        _items = results[0] as List<SocialNeedsAssessment>;
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
      builder: (_) => _NeedsDialog(
        accessToken: widget.accessToken,
        repository: widget.repository,
        patients: _patients,
      ),
    );
    if (created == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppStrings.socialNeedsSaved)),
      );
      await _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(AppStrings.socialNeeds),
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
        label: Text(AppStrings.socialNewNeeds),
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
      return EmptyStateView(message: AppStrings.socialNeedsEmpty);
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
                    item.needs.map(AppStrings.needLabel).join(', '),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  if (item.observations.isNotEmpty)
                    Text(
                      item.observations,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                  if (item.assessedAt.isNotEmpty)
                    Text(
                      item.assessedAt.split('T').first,
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

class _NeedsDialog extends StatefulWidget {
  const _NeedsDialog({
    required this.accessToken,
    required this.repository,
    required this.patients,
  });

  final String accessToken;
  final SocialWorkRepository repository;
  final List<SocialCaseloadEntry> patients;

  @override
  State<_NeedsDialog> createState() => _NeedsDialogState();
}

class _NeedsDialogState extends State<_NeedsDialog> {
  SocialCaseloadEntry? _patient;
  final Set<String> _needs = {};
  final _observations = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _observations.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final patient = _patient;
    if (patient == null || _needs.isEmpty) {
      setState(() => _error = AppStrings.socialNewNeeds);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.repository.createNeeds(
        access: widget.accessToken,
        patientUid: patient.patientUid,
        needs: _needs.toList(),
        observations: _observations.text.trim(),
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
      title: Text(AppStrings.socialNewNeeds),
      content: SizedBox(
        width: double.maxFinite,
        child: ListView(
          shrinkWrap: true,
          children: [
            DropdownButtonFormField<SocialCaseloadEntry>(
              initialValue: _patient,
              decoration:
                  InputDecoration(labelText: AppStrings.socialPatient),
              items: [
                for (final p in widget.patients)
                  DropdownMenuItem(value: p, child: Text(p.patientName)),
              ],
              onChanged: (_busy) ? null : (v) => setState(() => _patient = v),
            ),
            const SizedBox(height: 12),
            Text(AppStrings.socialNeeds,
                style: Theme.of(context).textTheme.labelLarge),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                for (final code in socialNeedCodes)
                  FilterChip(
                    label: Text(
                      AppStrings.needLabel(code),
                      style: const TextStyle(fontSize: 12),
                    ),
                    selected: _needs.contains(code),
                    onSelected: _busy
                        ? null
                        : (selected) => setState(() {
                              selected
                                  ? _needs.add(code)
                                  : _needs.remove(code);
                            }),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _observations,
              maxLines: 4,
              decoration:
                  InputDecoration(labelText: AppStrings.socialObservations),
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
