import 'package:flutter/material.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../../../shared/widgets/state_views.dart';
import '../../../auth/data/token_store.dart';
import '../../../auth/presentation/widgets/session_scope.dart';
import '../../data/admin_models.dart';
import '../../data/admin_repository.dart';
import '../widgets/admin_kpi_card.dart';

/// Admin dashboard (ADMIN-3) — real KPIs from GET /api/admin/dashboard.
///
/// Every number is computed server-side from the admin KPI kernel; the client
/// only formats. Loading/error/empty follow the shared async-state views.
class AdminDashboardPage extends StatelessWidget {
  const AdminDashboardPage({super.key, this.repository, this.accessToken});

  static const String routeName = '/admin/dashboard';

  final AdminRepository? repository;
  final String? accessToken;

  @override
  Widget build(BuildContext context) {
    final session = SessionScope.controllerOf(context);
    final token = accessToken ?? session.accessToken;
    if (token == null) {
      return const Center(child: Text('Sign in as an administrator to continue.'));
    }
    return _DashboardView(
      accessToken: token,
      repository: repository ??
          AdminRepository(tokenStore: EphemeralTokenStore()),
    );
  }
}

class _DashboardView extends StatefulWidget {
  const _DashboardView({required this.accessToken, required this.repository});

  final String accessToken;
  final AdminRepository repository;

  @override
  State<_DashboardView> createState() => _DashboardViewState();
}

class _DashboardViewState extends State<_DashboardView>
    with AutomaticKeepAliveClientMixin {
  AdminDashboard? _dashboard;
  Object? _error;
  bool _loading = true;

  @override
  bool get wantKeepAlive => true;

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
      final dash = await widget.repository.dashboard(
        access: widget.accessToken,
      );
      if (!mounted) return;
      setState(() {
        _dashboard = dash;
        _loading = false;
      });
    } on Exception catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return ErrorRetryView(
        message: 'The dashboard could not be loaded.',
        onRetry: _load,
      );
    }
    final dash = _dashboard;
    if (dash == null) {
      return const EmptyStateView(
        icon: Icons.dashboard_outlined,
        title: 'No data yet',
        message: 'Dashboard aggregates will appear once activity is recorded.',
      );
    }
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.xl),
      children: [
        Text(
          dash.roleKernel.isEmpty
              ? 'Platform Dashboard'
              : 'Platform Dashboard · ${dash.roleKernel}',
          style: theme.textTheme.headlineSmall,
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          dash.generatedAt == null
              ? 'Key indicators are computed from verified ledger data.'
              : 'Computed ${dash.generatedAt}',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: AppSpacing.xl),
        _KpiGrid(dashboard: dash),
        const SizedBox(height: AppSpacing.xl),
        _PendingLine(dashboard: dash),
      ],
    );
  }
}

class _KpiGrid extends StatelessWidget {
  const _KpiGrid({required this.dashboard});

  final AdminDashboard dashboard;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final crossAxisCount = constraints.maxWidth > 1100 ? 4 : 2;
        return GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: crossAxisCount,
          mainAxisSpacing: AppSpacing.md,
          crossAxisSpacing: AppSpacing.md,
          childAspectRatio: 1.6,
          children: [
            AdminKpiCard(
              icon: Icons.people_outline,
              title: 'Total Users',
              value: '${dashboard.intKpi('users_total')}',
              description: 'Registered accounts',
            ),
            AdminKpiCard(
              icon: Icons.person_outline,
              title: 'Active Patients',
              value: '${dashboard.intKpi('users_active_patients')}',
              description: 'Currently active',
            ),
            AdminKpiCard(
              icon: Icons.medical_services_outlined,
              title: 'Verified Doctors',
              value: '${dashboard.intKpi('verified_docs')}',
              description: 'Confirmed practitioners',
            ),
            AdminKpiCard(
              icon: Icons.bloodtype_outlined,
              title: 'Active Blood Requests',
              value: '${dashboard.intKpi('active_blood_requests')}',
              description: 'Open requests',
            ),
            AdminKpiCard(
              icon: Icons.emergency_outlined,
              title: 'Critical Emergencies',
              value: '${dashboard.intKpi('emergency_requests_critical')}',
              description: 'Critical severity',
            ),
            AdminKpiCard(
              icon: Icons.campaign_outlined,
              title: 'Active Campaigns',
              value: '${dashboard.intKpi('active_campaigns')}',
              description: 'Live fundraisers',
            ),
            AdminKpiCard(
              icon: Icons.volunteer_activism_outlined,
              title: 'Confirmed Donations',
              value:
                  '${dashboard.doubleKpi('confirmed_donations_amount').toStringAsFixed(0)} TZS',
              description: 'Completed contributions',
            ),
            AdminKpiCard(
              icon: Icons.report_outlined,
              title: 'Open Reports',
              value: '${dashboard.intKpi('open_reports')}',
              description: 'Awaiting moderation',
            ),
            AdminKpiCard(
              icon: Icons.article_outlined,
              title: 'Published Content',
              value: '${dashboard.intKpi('published_content')}',
              description: 'Education articles',
            ),
            AdminKpiCard(
              icon: Icons.school_outlined,
              title: 'Verification Queue',
              value: '${dashboard.intKpi('pending_verifications')}',
              description: 'Pending verifications',
            ),
          ],
        );
      },
    );
  }
}

class _PendingLine extends StatelessWidget {
  const _PendingLine({required this.dashboard});

  final AdminDashboard dashboard;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pendingMod = dashboard.intKpi('pending_moderation');
    final alerts = dashboard.intKpi('system_alerts_24h');
    final emergencies = dashboard.intKpi('active_emergencies');
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Row(
        children: [
          const Icon(Icons.shield_outlined, size: 20),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Text(
              'Pending moderation: $pendingMod · Active emergencies: $emergencies · '
              'System alerts (24h): $alerts',
              style: theme.textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }
}