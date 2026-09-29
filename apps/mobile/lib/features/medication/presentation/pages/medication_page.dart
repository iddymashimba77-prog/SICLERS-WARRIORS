import 'package:flutter/material.dart';

import '../../../../core/constants/app_strings.dart';
import '../../../auth/data/token_store.dart';
import '../../../auth/domain/auth_types.dart';
import '../../../auth/presentation/controllers/auth_controller.dart';
import '../../../auth/presentation/widgets/session_scope.dart';
import '../../../health/data/health_repository.dart';
import '../../data/medication_repository.dart';
import '../pages/medication_form_page.dart';
import '../pages/medication_detail_page.dart';

/// Medication list home (approved FR-MED-001/003/006).
///
/// Accepts an optional [AuthController] for token/role injection; tests
/// and future shell-wiring can supply a real controller. Without a token the
/// page shows a standard "sign in" guard.
class MedicationPage extends StatelessWidget {
  const MedicationPage({
    super.key,
    this.authController,
    this.medicationRepository,
    this.healthRepository,
  });

  static const String routeName = '/medication';

  final AuthController? authController;
  final MedicationRepository? medicationRepository;
  final HealthRepository? healthRepository;

  @override
  Widget build(BuildContext context) {
    final token = (authController ?? SessionScope.controllerOf(context))
        .accessToken;
    if (token == null) {
      return Scaffold(
        appBar: AppBar(title: const Text(AppStrings.medications)),
        body: const Center(child: Text(AppStrings.notSignedIn)),
      );
    }
    return MedicationHomeView(
      accessToken: token,
      repository: medicationRepository ??
          MedicationRepository(tokenStore: EphemeralTokenStore()),
    );
  }
}

/// Full list view with a stats overview card.
class MedicationHomeView extends StatefulWidget {
  const MedicationHomeView({
    super.key,
    required this.accessToken,
    required this.repository,
  });

  final String accessToken;
  final MedicationRepository repository;

  @override
  State<MedicationHomeView> createState() => _MedicationHomeViewState();
}

class _MedicationHomeViewState extends State<MedicationHomeView> {
  List<Medication>? _medications;
  MedicationStats? _stats;
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
        widget.repository.listMedications(access: widget.accessToken),
        widget.repository.fetchStats(access: widget.accessToken),
      ]);
      if (!mounted) return;
      setState(() {
        _medications = results[0] as List<Medication>;
        _stats = results[1] as MedicationStats;
        _loading = false;
      });
    } on AuthException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
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
    return Scaffold(
      appBar: AppBar(title: const Text(AppStrings.medications)),
      floatingActionButton: FloatingActionButton(
        heroTag: 'add-medication',
        tooltip: AppStrings.addMedication,
        onPressed: () => _navigateToAdd(context),
        child: const Icon(Icons.add),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 48),
              const SizedBox(height: 12),
              const Text(AppStrings.medicationLoadFailed),
              const SizedBox(height: 16),
              OutlinedButton(
                onPressed: _load,
                child: const Text(AppStrings.retry),
              ),
            ],
          ),
        ),
      );
    }
    final meds = _medications ?? const [];
    final stats = _stats;
    if (meds.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.medication_outlined, size: 48),
              const SizedBox(height: 12),
              const Text(AppStrings.noMedications),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () => _navigateToAdd(context),
                icon: const Icon(Icons.add),
                label: const Text(AppStrings.addMedication),
              ),
            ],
          ),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          if (stats != null) _StatsSummaryCard(stats: stats),
          for (final med in meds)
            _MedicationListTile(
              medication: med,
              onTap: () => _navigateToDetail(context, med),
            ),
          const SizedBox(height: 80), // space behind FAB
        ],
      ),
    );
  }

  void _navigateToAdd(BuildContext context) async {
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => MedicationFormPage(
          accessToken: widget.accessToken,
          repository: widget.repository,
        ),
      ),
    );
    if (result == true && mounted) _load();
  }

  void _navigateToDetail(BuildContext context, Medication med) async {
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => MedicationDetailPage(
          accessToken: widget.accessToken,
          repository: widget.repository,
          medication: med,
        ),
      ),
    );
    if (result == true && mounted) _load();
  }
}

class _StatsSummaryCard extends StatelessWidget {
  const _StatsSummaryCard({required this.stats});

  final MedicationStats stats;

  @override
  Widget build(BuildContext context) {
    final overall = stats.overall;
    final pct = overall.adherencePct;
    final pctText =
        pct == null ? '--' : '${pct.toStringAsFixed(0)}%';
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              AppStrings.adherence.toUpperCase(),
              style: Theme.of(context).textTheme.labelSmall,
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Text(
                  pctText,
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Text(
                    '${AppStrings.expectedDoses}: ${overall.expected} · '
                    '${AppStrings.takenDoses}: ${overall.taken}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _MedicationListTile extends StatelessWidget {
  const _MedicationListTile({required this.medication, required this.onTap});

  final Medication medication;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isActive = medication.isActive;
    final scheduleCount = medication.schedules.length;
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: ListTile(
        title: Text(
          medication.displayName.isEmpty ? medication.name : medication.displayName,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          [
            if (medication.frequency.isNotEmpty) medication.frequency,
            if (scheduleCount > 0)
              '$scheduleCount ${scheduleCount == 1 ? 'schedule' : 'schedules'}',
          ].join(' · '),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: isActive
            ? Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  AppStrings.active,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onPrimaryContainer,
                    fontSize: 12,
                  ),
                ),
              )
            : null,
        onTap: onTap,
      ),
    );
  }
}