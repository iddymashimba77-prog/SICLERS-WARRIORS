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

/// Social referrals list + create + status moves (§3): escalations to other
/// services — no campaign/donation objects, no money.
class SocialReferralsPage extends StatelessWidget {
  const SocialReferralsPage({super.key, this.authController, this.repository});

  final AuthController? authController;
  final SocialWorkRepository? repository;

  @override
  Widget build(BuildContext context) {
    final token =
        (authController ?? SessionScope.controllerOf(context)).accessToken;
    if (token == null) return const SignedOutGate();
    return _ReferralsView(
      accessToken: token,
      repository: repository ??
          SocialWorkRepository(tokenStore: EphemeralTokenStore()),
    );
  }
}

const Map<String, List<String>> _socialReferralTransitions = {
  'REQUESTED': ['ACCEPTED', 'DECLINED', 'CANCELLED'],
  'ACCEPTED': ['COMPLETED', 'DECLINED', 'CANCELLED'],
  'DECLINED': <String>[],
  'COMPLETED': <String>[],
  'CANCELLED': <String>[],
};

class _ReferralsView extends StatefulWidget {
  const _ReferralsView({required this.accessToken, required this.repository});

  final String accessToken;
  final SocialWorkRepository repository;

  @override
  State<_ReferralsView> createState() => _ReferralsViewState();
}

class _ReferralsViewState extends State<_ReferralsView> {
  List<SocialReferral> _items = const [];
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
        widget.repository.listReferrals(access: widget.accessToken),
        widget.repository.caseload(access: widget.accessToken),
      ]);
      if (!mounted) return;
      setState(() {
        _items = results[0] as List<SocialReferral>;
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
      builder: (_) => _ReferralDialog(
        accessToken: widget.accessToken,
        repository: widget.repository,
        patients: _patients,
      ),
    );
    if (created == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppStrings.socialReferralSaved)),
      );
      await _load();
    }
  }

  Future<void> _advance(SocialReferral item) async {
    final allowed =
        _socialReferralTransitions[item.status] ?? const <String>[];
    if (allowed.isEmpty) return;
    final next = await showModalBottomSheet<String>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                '${item.patientName} → ${item.destination}',
                style: Theme.of(sheetContext).textTheme.titleMedium,
              ),
            ),
            for (final status in allowed)
              ListTile(
                title: Text(AppStrings.codeLabel(status)),
                onTap: () => Navigator.of(sheetContext).pop(status),
              ),
          ],
        ),
      ),
    );
    if (next == null || !mounted) return;
    try {
      await widget.repository.updateReferral(
        access: widget.accessToken,
        uid: item.uid,
        status: next,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppStrings.socialReferralUpdated)),
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              e is AuthException ? e.message : AppStrings.socialLoadFailed),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(AppStrings.socialReferrals),
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
        label: Text(AppStrings.socialNewReferral),
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
      return EmptyStateView(message: AppStrings.socialReferralsEmpty);
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: _items.length,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          final item = _items[index];
          final canAdvance =
              (_socialReferralTransitions[item.status] ?? const <String>[])
                  .isNotEmpty;
          return Card(
            child: ListTile(
              title: Text('${item.patientName} → ${item.destination}'),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    AppStrings.codeLabel(item.status),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  if (item.responsiblePerson.isNotEmpty)
                    Text(
                      '${AppStrings.socialResponsible}: ${item.responsiblePerson}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  if (item.followUpAt != null)
                    Text(
                      item.followUpAt!.split('T').first,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  Text(
                    item.reason,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
              isThreeLine: true,
              trailing: canAdvance
                  ? IconButton(
                      tooltip: AppStrings.codeLabel(item.status),
                      icon: const Icon(Icons.send_outlined),
                      onPressed: () => _advance(item),
                    )
                  : const Icon(Icons.check_circle_outline),
              onTap: canAdvance ? () => _advance(item) : null,
            ),
          );
        },
      ),
    );
  }
}

class _ReferralDialog extends StatefulWidget {
  const _ReferralDialog({
    required this.accessToken,
    required this.repository,
    required this.patients,
  });

  final String accessToken;
  final SocialWorkRepository repository;
  final List<SocialCaseloadEntry> patients;

  @override
  State<_ReferralDialog> createState() => _ReferralDialogState();
}

class _ReferralDialogState extends State<_ReferralDialog> {
  SocialCaseloadEntry? _patient;
  final _destination = TextEditingController();
  final _reason = TextEditingController();
  final _responsible = TextEditingController();
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
    _destination.dispose();
    _reason.dispose();
    _responsible.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final patient = _patient;
    if (patient == null ||
        _destination.text.trim().isEmpty ||
        _reason.text.trim().isEmpty) {
      setState(() => _error = AppStrings.socialNewReferral);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.repository.createReferral(
        access: widget.accessToken,
        patientUid: patient.patientUid,
        destination: _destination.text.trim(),
        reason: _reason.text.trim(),
        responsiblePerson: _responsible.text.trim(),
        followUpAt: _followUp?.toUtc().toIso8601String(),
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
      title: Text(AppStrings.socialNewReferral),
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
            TextField(
              controller: _destination,
              decoration:
                  InputDecoration(labelText: AppStrings.socialDestination),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _reason,
              maxLines: 3,
              decoration: InputDecoration(labelText: AppStrings.socialReason),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _responsible,
              decoration: InputDecoration(
                  labelText: AppStrings.socialResponsible),
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
                          ? AppStrings.socialFollowUpDate
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
