import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_strings.dart';
import '../../../../core/l10n/app_localizations.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../shared/widgets/state_views.dart';
import '../../../auth/data/token_store.dart';
import '../../../health/data/health_repository.dart';
import '../../../health/presentation/pages/symptom_form_page.dart';
import '../../data/caregiver_health_repository.dart';

/// Full consent-gated health track for a caregiver (FR-CG health / C14).
///
/// Reached through `/health`, where [HealthDashboardPage] branches to this
/// view for caregivers instead of the patient-only dashboard (the backend
/// 403s that surface for them). The backend's three honest states — no link,
/// no consent, ok — render as distinct empty/form views with per-section
/// consent gating; only a transport failure shows "load failed" + retry.
class CaregiverHealthView extends StatefulWidget {
  const CaregiverHealthView({
    super.key,
    required this.accessToken,
    this.repository,
    this.symptomRepository,
  });

  final String accessToken;
  final CaregiverHealthRepository? repository;

  /// Symptom-type vocabulary source for the observation form; defaults to the
  /// standard [HealthRepository] like every symptom-form caller.
  final HealthRepository? symptomRepository;

  @override
  State<CaregiverHealthView> createState() => _CaregiverHealthViewState();
}

class _CaregiverHealthViewState extends State<CaregiverHealthView> {
  CaregiverHealthRepository? _repoOverride;
  CaregiverHealthRepository get _repo => _repoOverride ??=
      widget.repository ?? CaregiverHealthRepository();

  CaregiverHealthSummary? _summary;
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
      final summary = await _repo.fetchHealth(access: widget.accessToken);
      if (!mounted) return;
      setState(() {
        _summary = summary;
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

  Future<void> _openObservation() async {
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => SymptomFormPage(
          accessToken: widget.accessToken,
          repository: widget.symptomRepository ??
              HealthRepository(tokenStore: EphemeralTokenStore()),
          submit: _repo.logObservation,
          title: AppStrings.recordForPatient,
        ),
      ),
    );
    if (result == true && mounted) _load();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const LoadingView();
    if (_error != null) {
      return ErrorRetryView(
        title: AppStrings.healthTracking,
        message: AppStrings.healthLoadFailed,
        onRetry: _load,
      );
    }
    final summary = _summary;
    if (summary == null) return const SizedBox.shrink();
    if (summary.reason == 'no_link') {
      return EmptyStateView(
        icon: Icons.person_add_alt_outlined,
        title: AppStrings.noLinkedPatients,
        message: AppStrings.caregiverNoLinkGuidance,
      );
    }
    if (!summary.isOk) {
      // reason == 'no_consent': the link exists, the health scope does not.
      return EmptyStateView(
        icon: Icons.lock_outline,
        title: AppStrings.caregiverHealthUpdates,
        message: AppStrings.caregiverNoConsentGuidance,
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          _linkedPatientCard(summary),
          const SizedBox(height: AppSpacing.sm),
          Text(
            AppStrings.caregiverOnlyAuthorized,
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
          if (summary.canLog) ...[
            const SizedBox(height: AppSpacing.lg),
            FilledButton.tonalIcon(
              onPressed: _openObservation,
              icon: const Icon(Icons.add_circle_outline),
              label: Text(AppStrings.recordForPatient),
            ),
          ],
          const SizedBox(height: AppSpacing.xl),
          _sectionHeader(
            AppStrings.symptoms,
            showLog: summary.canLog,
          ),
          const SizedBox(height: AppSpacing.sm),
          ..._symptomSection(summary),
          const SizedBox(height: AppSpacing.xl),
          Text(
            AppStrings.medications.toUpperCase(),
            style: Theme.of(context).textTheme.labelSmall,
          ),
          const SizedBox(height: AppSpacing.sm),
          ..._medicationSection(summary),
          const SizedBox(height: AppSpacing.xl),
        ],
      ),
    );
  }

  Widget _linkedPatientCard(CaregiverHealthSummary summary) {
    final patient = summary.linkedPatient;
    if (patient == null) return const SizedBox.shrink();
    return Card(
      child: ListTile(
        leading: const Icon(Icons.person_outline),
        title: Text(patient.displayName),
        subtitle: Text(relationshipLabel(patient.relationshipType)),
        trailing: const Icon(Icons.favorite_outline, size: 18),
      ),
    );
  }

  Widget _sectionHeader(String title, {required bool showLog}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(title.toUpperCase(), style: Theme.of(context).textTheme.labelSmall),
        if (showLog)
          TextButton.icon(
            onPressed: _openObservation,
            icon: const Icon(Icons.add_circle_outline, size: 18),
            label: Text(AppStrings.logSymptomShort),
          ),
      ],
    );
  }

  List<Widget> _symptomSection(CaregiverHealthSummary summary) {
    if (!summary.canViewSymptoms) return [_notShared()];
    if (summary.symptoms.isEmpty) return [Text(AppStrings.noSymptoms)];
    return [
      for (final s in summary.symptoms.take(10))
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
            title: Text(s.symptomTypeName ?? s.symptomTypeCode),
            subtitle: Text([
              if (s.painLevel != null) '${AppStrings.painLevel}: ${s.painLevel}/10',
              if (s.durationMinutes != null) '${s.durationMinutes} min',
            ].join(' · ')),
          ),
        ),
    ];
  }

  List<Widget> _medicationSection(CaregiverHealthSummary summary) {
    if (!summary.canViewMedications) return [_notShared()];
    if (summary.medications.isEmpty) return [Text(AppStrings.noMedications)];
    return [
      for (final m in summary.medications)
        Card(
          child: ListTile(
            dense: true,
            leading: const Icon(Icons.medication_outlined),
            title: Text(m.label),
            subtitle: m.schedule.isEmpty ? null : Text(m.schedule),
          ),
        ),
    ];
  }

  Widget _notShared() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Text(
        AppStrings.notSharedYet,
        style: Theme.of(context)
            .textTheme
            .bodySmall
            ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
      ),
    );
  }
}

/// Human label for a `CaregiverRelationship.relationship_type` code — static
/// `tr()` literals so the localization parity test covers every branch.
String relationshipLabel(String code) {
  switch (code) {
    case 'PARENT':
      return tr('caregiver.relationship.parent');
    case 'SPOUSE':
      return tr('caregiver.relationship.spouse');
    case 'CHILD':
      return tr('caregiver.relationship.child');
    case 'SIBLING':
      return tr('caregiver.relationship.sibling');
    case 'GUARDIAN':
      return tr('caregiver.relationship.guardian');
    case 'FRIEND':
      return tr('caregiver.relationship.friend');
    default:
      return tr('caregiver.relationship.other');
  }
}
