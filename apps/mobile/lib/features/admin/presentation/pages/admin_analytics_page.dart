import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../shared/widgets/state_views.dart';
import '../../../auth/data/token_store.dart';
import '../../../auth/presentation/widgets/session_scope.dart';
import '../../data/admin_models.dart';
import '../../data/admin_repository.dart';
import '../widgets/admin_widgets.dart';
import '../../../../core/theme/app_shapes.dart';

/// Platform analytics (ADMIN-3) — GET /api/admin/analytics/ for whitelisted
/// metrics at DAILY/WEEKLY/MONTHLY granularity. Values are backend aggregates;
/// the app renders them as a simple bar strip (no fabricated numbers).
class AdminAnalyticsPage extends StatelessWidget {
  const AdminAnalyticsPage({super.key, this.repository, this.accessToken});

  static const String routeName = '/admin/analytics';

  final AdminRepository? repository;
  final String? accessToken;

  @override
  Widget build(BuildContext context) {
    final session = SessionScope.controllerOf(context);
    final token = accessToken ?? session.accessToken;
    if (token == null) return const Center(child: Text('Not signed in.'));
    return _AnalyticsView(
      accessToken: token,
      repository: repository ?? AdminRepository(tokenStore: EphemeralTokenStore()),
    );
  }
}

class _AnalyticsView extends StatefulWidget {
  const _AnalyticsView({required this.accessToken, required this.repository});

  final String accessToken;
  final AdminRepository repository;

  @override
  State<_AnalyticsView> createState() => _AnalyticsViewState();
}

class _AnalyticsViewState extends State<_AnalyticsView> {
  String _metric = 'users.total';
  String _granularity = 'DAILY';
  AnalyticsResult? _result;
  Object? _error;
  bool _loading = true;

  static const _metrics = <(String, String)>[
    ('users.total', 'Total users'),
    ('users.active', 'Active users'),
    ('users.active_patients', 'Active patients'),
    ('users.new', 'New users'),
    ('donations.confirmed_amount', 'Confirmed donations (TZS)'),
    ('blood_donations.by_outcome', 'Blood donations'),
    ('blood_matches.by_status', 'Blood matches'),
    ('emergency_requests.by_status', 'Emergency requests'),
    ('community_posts.by_status', 'Community posts'),
    ('reports.by_status', 'Reports'),
    ('education.by_status', 'Education content'),
    ('symptoms.avg_pain', 'Average pain level'),
    ('security_events.non_success', 'Security events (non-success)'),
  ];

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
      final result = await widget.repository.analytics(
        access: widget.accessToken,
        metric: _metric,
        granularity: _granularity,
      );
      if (!mounted) return;
      setState(() {
        _result = result;
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
    return ListView(
      children: [
        AdminSectionHeader(
          title: 'Analytics',
          subtitle: 'Aggregated telemetry from the analytics snapshot store.',
          trailing: SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'DAILY', label: Text('Daily')),
              ButtonSegment(value: 'WEEKLY', label: Text('Weekly')),
              ButtonSegment(value: 'MONTHLY', label: Text('Monthly')),
            ],
            selected: {_granularity},
            onSelectionChanged: (set) {
              setState(() => _granularity = set.first);
              _load();
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
          child: DropdownButtonFormField<String>(
            initialValue: _metric,
            decoration: const InputDecoration(labelText: 'Metric'),
            items: [
              for (final m in _metrics)
                DropdownMenuItem(value: m.$1, child: Text(m.$2)),
            ],
            onChanged: (value) {
              if (value == null) return;
              setState(() => _metric = value);
              _load();
            },
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        if (_loading)
          const Padding(
            padding: EdgeInsets.all(AppSpacing.xl),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (_error != null)
          Padding(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: ErrorRetryView(
              message: 'The analytics series could not be loaded.',
              onRetry: _load,
            ),
          )
        else
          _BarChart(
            rows: _result?.rows ?? const [],
            metric: _metric,
            daysLabel: _granularity == 'DAILY'
                ? 'per day'
                : (_granularity == 'WEEKLY' ? 'per week' : 'per month'),
          ),
      ],
    );
  }
}

class _BarChart extends StatelessWidget {
  const _BarChart({
    required this.rows,
    required this.metric,
    required this.daysLabel,
  });

  final List<AnalyticsRow> rows;
  final String metric;
  final String daysLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (rows.isEmpty) {
      return const EmptyStateView(
        icon: Icons.insert_chart_outlined,
        title: 'No data points yet',
        message: 'Snapshots will appear once the metric has been computed.',
      );
    }
    final maxValue = rows.fold<double>(0, (m, r) => r.value > m ? r.value : m);
    final safeMax = maxValue <= 0 ? 1.0 : maxValue;
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$metric · $daysLabel',
            style: theme.textTheme.titleSmall,
          ),
          const SizedBox(height: AppSpacing.lg),
          for (final row in rows.take(30)) _BarRow(row: row, maxValue: safeMax),
        ],
      ),
    );
  }
}

class _BarRow extends StatelessWidget {
  const _BarRow({required this.row, required this.maxValue});

  final AnalyticsRow row;
  final double maxValue;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final label = row.label.isEmpty ? '—' : row.label;
    final fraction = (row.value / maxValue).clamp(0.0, 1.0);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: AppShapes.xs,
            child: SizedBox(
              height: 10,
              width: double.infinity,
              child: FractionallySizedBox(
                alignment: Alignment.centerLeft,
                widthFactor: fraction,
                child: Container(color: AppColors.blue),
              ),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            row.value.toStringAsFixed(2),
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}