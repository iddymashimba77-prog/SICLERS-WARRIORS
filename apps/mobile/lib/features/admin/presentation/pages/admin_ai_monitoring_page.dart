import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../shared/widgets/state_views.dart';
import '../../../auth/data/token_store.dart';
import '../../../auth/presentation/widgets/session_scope.dart';
import '../../data/admin_models.dart';
import '../../data/admin_repository.dart';
import '../widgets/admin_kpi_card.dart';
import '../widgets/admin_widgets.dart';

/// AI assistant usage monitoring (ADMIN-3) — GET /api/admin/ai/monitoring/
/// aggregates real AI audit-log events (admin.audit.read). No fabricated
/// graphics; numbers are the definitive counts from the AI audit trail.
class AdminAiMonitoringPage extends StatelessWidget {
  const AdminAiMonitoringPage({super.key, this.repository, this.accessToken});

  static const String routeName = '/admin/ai-monitoring';

  final AdminRepository? repository;
  final String? accessToken;

  @override
  Widget build(BuildContext context) {
    final session = SessionScope.controllerOf(context);
    final token = accessToken ?? session.accessToken;
    if (token == null) return const Center(child: Text('Not signed in.'));
    return _AiMonitoringView(
      accessToken: token,
      repository: repository ?? AdminRepository(tokenStore: EphemeralTokenStore()),
    );
  }
}

class _AiMonitoringView extends StatefulWidget {
  const _AiMonitoringView({required this.accessToken, required this.repository});

  final String accessToken;
  final AdminRepository repository;

  @override
  State<_AiMonitoringView> createState() => _AiMonitoringViewState();
}

class _AiMonitoringViewState extends State<_AiMonitoringView> {
  AiMonitoring? _monitoring;
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
      final monitoring =
          await widget.repository.aiMonitoring(access: widget.accessToken);
      if (!mounted) return;
      setState(() {
        _monitoring = monitoring;
        _loading = false;
      });
    } on Exception {
      if (!mounted) return;
      setState(() {
        _error = true as Object?;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      children: [
        AdminSectionHeader(
          title: 'AI Monitoring',
          subtitle: 'AI assistant usage from the audit trail (last ${_monitoring?.windowDays ?? 30} days).',
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
          child: _error == true
              ? ErrorRetryView(
                  message: 'AI usage telemetry could not be loaded.',
                  onRetry: _load,
                )
              : (_loading || _monitoring == null)
                  ? const Padding(
                      padding: EdgeInsets.all(AppSpacing.xl),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  : _content(theme),
        ),
      ],
    );
  }

  Widget _content(ThemeData theme) {
    final m = _monitoring!;
    return LayoutBuilder(
      builder: (context, constraints) {
        final cols = constraints.maxWidth > 1000 ? 4 : 2;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: cols,
              mainAxisSpacing: AppSpacing.md,
              crossAxisSpacing: AppSpacing.md,
              childAspectRatio: 1.8,
              children: [
                AdminKpiCard(
                  icon: Icons.smart_toy_outlined,
                  title: 'Total Events',
                  value: '${m.totalEvents}',
                ),
                AdminKpiCard(
                  icon: Icons.check_circle_outline,
                  title: 'Successful',
                  value: '${m.successes}',
                  color: AppColors.success,
                ),
                AdminKpiCard(
                  icon: Icons.error_outline,
                  title: 'Failures',
                  value: '${m.failures}',
                  color: AppColors.emergency,
                ),
                AdminKpiCard(
                  icon: Icons.gpp_bad_outlined,
                  title: 'Denied',
                  value: '${m.denied}',
                  color: AppColors.emergency,
                ),
                AdminKpiCard(
                  icon: Icons.shield_outlined,
                  title: 'Safety Blocks',
                  value: '${m.safetyBlocks}',
                ),
                AdminKpiCard(
                  icon: Icons.cloud_off_outlined,
                  title: 'Provider Failures',
                  value: '${m.providerFailures}',
                ),
                AdminKpiCard(
                  icon: Icons.block_outlined,
                  title: 'Usage Denied',
                  value: '${m.usageDenied}',
                ),
                AdminKpiCard(
                  icon: Icons.people_outline,
                  title: 'Unique Users',
                  value: '${m.uniqueUsers}',
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xl),
            Text('By action', style: theme.textTheme.titleSmall),
            const SizedBox(height: AppSpacing.sm),
            if (m.byAction.isEmpty)
              const Text('No action breakdown yet.')
            else
              for (final action in m.byAction)
                Card(
                  margin: EdgeInsets.zero,
                  child: ListTile(
                    dense: true,
                    title: Text(action.actionCode),
                    trailing: Text('${action.count}'),
                  ),
                ),
          ],
        );
      },
    );
  }
}