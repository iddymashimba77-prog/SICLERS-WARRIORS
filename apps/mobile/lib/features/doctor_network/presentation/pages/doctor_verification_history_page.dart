import 'package:flutter/material.dart';

import '../../../../core/l10n/app_localizations.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../shared/widgets/state_views.dart';
import '../../../auth/domain/auth_types.dart';
import '../../data/doctor_directory_repository.dart';

/// The verification trail for one professional (`FR-DOC-006/007`).
///
/// This is the only place a rejected-then-reapproved applicant can still read
/// the earlier refusal: the `Doctor` row keeps only the current status. The
/// server serves the trail to the applicant and to reviewers holding
/// `doctors.verify`, and answers everyone else with a 404 — so nothing here is
/// widened on the client.
class DoctorVerificationHistoryPage extends StatefulWidget {
  const DoctorVerificationHistoryPage({
    super.key,
    required this.accessToken,
    required this.repository,
    required this.doctorUid,
    this.displayName = '',
  });

  final String accessToken;
  final DoctorDirectoryRepository repository;
  final String doctorUid;
  final String displayName;

  @override
  State<DoctorVerificationHistoryPage> createState() =>
      _DoctorVerificationHistoryPageState();
}

class _DoctorVerificationHistoryPageState
    extends State<DoctorVerificationHistoryPage> {
  DoctorVerificationHistory? _history;
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
      final history = await widget.repository.verificationHistory(
        access: widget.accessToken,
        uid: widget.doctorUid,
      );
      if (!mounted) return;
      setState(() {
        _history = history;
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
    final s = AppLocalizations.of(context);
    if (error is AuthException) {
      final message = error.message.trim();
      if (message.isNotEmpty && !message.contains('Exception')) return message;
    }
    return s.tr('doctors.historyFailed');
  }

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(s.tr('doctors.verificationHistory')),
        actions: [
          IconButton(
            tooltip: s.tr('common.refresh'),
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: RefreshIndicator(onRefresh: _load, child: _buildBody()),
    );
  }

  Widget _buildBody() {
    final s = AppLocalizations.of(context);
    final theme = Theme.of(context);
    if (_loading) return LoadingView(label: s.tr('common.loading'));
    if (_error != null) {
      return ErrorRetryView(message: _messageFor(_error!), onRetry: _load);
    }
    final history = _history;
    if (history == null || history.isEmpty) {
      return EmptyStateView(
        message: s.tr('doctors.noVerificationHistory'),
        icon: Icons.history_toggle_off,
      );
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: ListTile(
            leading: const Icon(Icons.verified_user_outlined),
            title: Text(
              widget.displayName.isEmpty ? s.tr('doctors.currentStatus') : widget.displayName,
            ),
            subtitle: Text(history.verificationStatus.replaceAll('_', ' ')),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        for (final decision in history.decisions)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        decision.isRejection
                            ? Icons.cancel_outlined
                            : Icons.check_circle_outline,
                        size: 20,
                        color: decision.isRejection
                            ? theme.colorScheme.error
                            : theme.colorScheme.primary,
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: Text(
                          decision.transition.isEmpty
                              ? s.tr('doctors.decisionRecorded')
                              : decision.transition,
                          style: theme.textTheme.titleSmall,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(decision.decidedAt, style: theme.textTheme.bodySmall),
                  if (decision.actorName.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      '${s.tr('doctors.decidedBy')}: ${decision.actorName}',
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                  if (decision.reason.isNotEmpty) ...[
                    const SizedBox(height: AppSpacing.sm),
                    Text(decision.reason, style: theme.textTheme.bodyMedium),
                  ],
                ],
              ),
            ),
          ),
      ],
    );
  }
}