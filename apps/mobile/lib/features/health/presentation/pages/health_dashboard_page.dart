import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_strings.dart';
import '../../../../shared/widgets/dashboard_widgets.dart';
import '../../../auth/data/token_store.dart';
import '../../../auth/presentation/controllers/auth_controller.dart';
import '../../../auth/presentation/widgets/session_scope.dart';
import '../../../medical/presentation/pages/medical_records_page.dart';
import '../../../medication/presentation/pages/medication_page.dart';
import '../../data/health_repository.dart';
import 'symptom_form_page.dart';
import 'timeline_page.dart';

/// Health dashboard home (approved FR-MED-007 / "/health" tab).
class HealthDashboardPage extends StatelessWidget {
  const HealthDashboardPage({
    super.key,
    this.authController,
    this.healthRepository,
  });

  static const String routeName = '/health';

  final AuthController? authController;
  final HealthRepository? healthRepository;

  @override
  Widget build(BuildContext context) {
    // Real app: read the shared shell session so the Tiba tab keeps its tokens
    // after login; explicit controllers (widget tests) still win.
    final session = authController ?? SessionScope.controllerOf(context);
    final token = session.accessToken;
    if (token == null) {
      return Scaffold(
        appBar: AppBar(title: const Text(AppStrings.healthTracking)),
        body: const Center(child: Text(AppStrings.notSignedIn)),
      );
    }
    return Scaffold(
      appBar: AppBar(title: const Text(AppStrings.healthTracking)),
      body: SafeArea(
        child: HealthDashboardView(
          accessToken: token,
          repository:
              healthRepository ?? HealthRepository(tokenStore: EphemeralTokenStore()),
        ),
      ),
    );
  }
}

class HealthDashboardView extends StatefulWidget {
  const HealthDashboardView({
    super.key,
    required this.accessToken,
    required this.repository,
  });

  final String accessToken;
  final HealthRepository repository;

  @override
  State<HealthDashboardView> createState() => _HealthDashboardViewState();
}

class _HealthDashboardViewState extends State<HealthDashboardView> {
  HealthDashboard? _dashboard;
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
      final dash = await widget.repository.fetchDashboard(
        access: widget.accessToken,
      );
      if (!mounted) return;
      setState(() {
        _dashboard = dash;
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

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(24),
              child: Text(AppStrings.dashboardLoadFailed),
            ),
            OutlinedButton(
              onPressed: _load,
              child: const Text(AppStrings.retry),
            ),
          ],
        ),
      );
    }
    final dash = _dashboard;
    if (dash == null) return const SizedBox.shrink();
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            AppStrings.tibaSubtitle,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 16),
          QuickActionsGrid(
            actions: [
              QuickAction(
                icon: Icons.medication_outlined,
                label: AppStrings.manageMedications,
                onTap: () => Navigator.pushNamed(
                  context,
                  MedicationPage.routeName,
                ),
              ),
              QuickAction(
                icon: Icons.health_and_safety_outlined,
                label: AppStrings.logSymptomShort,
                onTap: () => _openLogSymptom(context),
              ),
              QuickAction(
                icon: Icons.timeline_outlined,
                label: AppStrings.viewTimelineShort,
                onTap: () => _openTimeline(context),
              ),
              QuickAction(
                icon: Icons.folder_shared_outlined,
                label: AppStrings.healthRecords,
                onTap: () => Navigator.pushNamed(
                  context,
                  MedicalRecordsPage.routeName,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (dash.activeMedCount > 0) ...[
            _SectionCard(
              title: AppStrings.today,
              child: Row(
                children: [
                  _Metric(
                    value: dash.dosesToday['expected'] ?? 0,
                    label: AppStrings.expectedDoses,
                  ),
                  _Metric(
                    value: dash.dosesToday['taken'] ?? 0,
                    label: AppStrings.takenDoses,
                  ),
                  _Metric(
                    value: dash.dosesToday['pending'] ?? 0,
                    label: AppStrings.pendingDoses,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            _SectionCard(
              title: AppStrings.adherenceLastSeven,
              child: _AdherenceBar(
                pct: dash.adherenceLast7.adherencePct,
              ),
            ),
          ],
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                AppStrings.medications.toUpperCase(),
                style: Theme.of(context).textTheme.labelSmall,
              ),
              TextButton(
                onPressed: () => Navigator.pushNamed(
                  context,
                  MedicationPage.routeName,
                ),
                child: const Text(AppStrings.medications),
              ),
            ],
          ),
          if (dash.activeMedCount == 0)
            const Text(AppStrings.noMedications)
          else
            for (final m in dash.medicalList)
              Card(
                child: ListTile(
                  dense: true,
                  leading: const Icon(Icons.medication_outlined),
                  title: Text([m.name, m.strength].where((s) => s.isNotEmpty).join(' ')),
                  trailing: Text('${m.dosesTodayPending} ${AppStrings.pendingDoses.toLowerCase()}'),
                ),
              ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                AppStrings.symptoms.toUpperCase(),
                style: Theme.of(context).textTheme.labelSmall,
              ),
              TextButton.icon(
                onPressed: () => _openLogSymptom(context),
                icon: const Icon(Icons.add_circle_outline),
                label: const Text(AppStrings.logSymptom),
              ),
            ],
          ),
          if (dash.recentSymptoms.isEmpty)
            const Text(AppStrings.noSymptoms)
          else
            for (final s in dash.recentSymptoms.take(5))
              Card(
                child: ListTile(
                  dense: true,
                  leading: Icon(
                    s.painLevel != null && s.painLevel! >= 7
                        ? Icons.warning_amber_rounded
                        : Icons.health_and_safety_outlined,
                    color: s.painLevel != null && s.painLevel! >= 7
                        ? AppColors.emergency
                        : AppColors.primary,
                  ),
                  title: Text(
                    s.symptomTypeName ?? s.symptomTypeCode,
                  ),
                  subtitle: Text([
                    if (s.painLevel != null) '${AppStrings.painLevel}: ${s.painLevel}/10',
                    if (s.durationMinutes != null)
                      '${s.durationMinutes} min',
                  ].join(' · ')),
                ),
              ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                AppStrings.timeline.toUpperCase(),
                style: Theme.of(context).textTheme.labelSmall,
              ),
              TextButton(
                onPressed: () => _openTimeline(context),
                child: const Text(AppStrings.viewTimeline),
              ),
            ],
          ),
          if (dash.recentTimeline.isEmpty)
            const Text(AppStrings.noTimelineEdits)
          else
            for (final t in dash.recentTimeline.take(10))
              Card(
                child: ListTile(
                  dense: true,
                  leading: const Icon(Icons.bolt_outlined),
                  title: Text(t.summary),
                  subtitle: Text(_formatTime(t.occurredAt)),
                ),
              ),
          const SizedBox(height: 16),
          // Health Records — honest section: records arrive from the care team.
          _SectionCard(
            title: AppStrings.healthRecords,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(AppStrings.noHealthRecords),
                const SizedBox(height: 8),
                Text(
                  AppStrings.recordsSharedWithYou,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: () => Navigator.pushNamed(
                    context,
                    MedicalRecordsPage.routeName,
                  ),
                  icon: const Icon(Icons.folder_shared_outlined),
                  label: const Text(AppStrings.recordsEmptyTitle),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          // Care plan — not fabricated; care-team managed.
          _SectionCard(
            title: AppStrings.carePlan,
            child: const Text(AppStrings.carePlanUnavailable),
          ),
          const SizedBox(height: 24),
          const Text(
            AppStrings.adherenceHelp,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }

  void _openLogSymptom(BuildContext context) async {
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => SymptomFormPage(
          accessToken: widget.accessToken,
          repository: widget.repository,
        ),
      ),
    );
    if (result == true && mounted) _load();
  }

  void _openTimeline(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => TimelinePage(
          accessToken: widget.accessToken,
          repository: widget.repository,
        ),
      ),
    );
  }

  String _formatTime(String? iso) {
    final dt = iso == null ? null : DateTime.tryParse(iso)?.toLocal();
    if (dt == null) return '';
    return '${dt.day}/${dt.month}/${dt.year} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title.toUpperCase(),
                style: Theme.of(context).textTheme.labelSmall),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.value, required this.label});

  final int value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Text('$value',
              style: Theme.of(context).textTheme.headlineMedium),
          Text(label, style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
}

class _AdherenceBar extends StatelessWidget {
  const _AdherenceBar({required this.pct});

  final double? pct;

  @override
  Widget build(BuildContext context) {
    final value = pct == null ? 0.0 : (pct! / 100).clamp(0.0, 1.0);
    final text = pct == null ? '--' : '${pct!.toStringAsFixed(0)}%';
    return Row(
      children: [
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: value,
              minHeight: 10,
              backgroundColor: AppColors.surface,
              color: pct != null && pct! >= 80
                  ? AppColors.success
                  : AppColors.secondary,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Text(text, style: Theme.of(context).textTheme.titleMedium),
      ],
    );
  }
}