import 'package:flutter/material.dart';

import '../../../../core/l10n/app_localizations.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../shared/widgets/state_views.dart';
import '../../../auth/domain/auth_types.dart';
import '../../data/blood_repository.dart';

/// The decision trail for one blood request (`FR-BLD-011/012`).
///
/// A `BloodRequest` row only remembers its *latest* status, so this screen is
/// the answer to "why was my request rejected?" — it is append-only on the
/// server, and the actor's own reason is shown verbatim rather than summarised,
/// because the patient is entitled to read and contest it.
class BloodDecisionHistoryPage extends StatefulWidget {
  const BloodDecisionHistoryPage({
    super.key,
    required this.accessToken,
    required this.repository,
    required this.requestUid,
  });

  final String accessToken;
  final BloodRepository repository;
  final String requestUid;

  @override
  State<BloodDecisionHistoryPage> createState() =>
      _BloodDecisionHistoryPageState();
}

class _BloodDecisionHistoryPageState extends State<BloodDecisionHistoryPage> {
  List<BloodRequestDecision> _decisions = const [];
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
      final decisions = await widget.repository.listDecisions(
        access: widget.accessToken,
        requestUid: widget.requestUid,
      );
      if (!mounted) return;
      setState(() {
        _decisions = decisions;
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
    return s.tr('blood.decisionsFailed');
  }

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(s.tr('blood.decisionHistory')),
        actions: [
          IconButton(
            tooltip: s.tr('common.refresh'),
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    final s = AppLocalizations.of(context);
    if (_loading) return LoadingView(label: s.tr('common.loading'));
    if (_error != null) {
      return ErrorRetryView(message: _messageFor(_error!), onRetry: _load);
    }
    if (_decisions.isEmpty) {
      return EmptyStateView(
        message: s.tr('blood.noDecisions'),
        icon: Icons.history_toggle_off,
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: _decisions.length,
      separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.sm),
      itemBuilder: (context, index) => _DecisionCard(decision: _decisions[index]),
    );
  }
}

class _DecisionCard extends StatelessWidget {
  const _DecisionCard({required this.decision});

  final BloodRequestDecision decision;

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  decision.isRejection ? Icons.cancel_outlined : Icons.check_circle_outline,
                  size: 20,
                  color: decision.isRejection ? theme.colorScheme.error : theme.colorScheme.primary,
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    decision.transition.isEmpty
                        ? s.tr('blood.decision')
                        : decision.transition,
                    style: theme.textTheme.titleSmall,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              decision.decidedAt,
              style: theme.textTheme.bodySmall,
            ),
            if (decision.actorName.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                '${s.tr('blood.decidedBy')}: ${decision.actorName}',
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
    );
  }
}