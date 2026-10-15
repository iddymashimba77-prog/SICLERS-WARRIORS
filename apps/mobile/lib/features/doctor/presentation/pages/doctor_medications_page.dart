import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_strings.dart';
import '../../../../shared/widgets/signed_out_gate.dart';
import '../../../auth/data/token_store.dart';
import '../../../auth/presentation/controllers/auth_controller.dart';
import '../../../auth/presentation/widgets/session_scope.dart';
import '../../../health/data/health_repository.dart';
import '../../../medication/data/medication_repository.dart';
import '../../../medication/presentation/pages/medication_form_page.dart';

/// Doctor-facing prescriptions surface (Stage 4.6 doctor cycle).
///
/// A verified prescriber picks a patient from the doctor patient directory,
/// then authors that patient's medication profile (create / edit). The patient
/// then sees those medications in their own account.
class DoctorMedicationsPage extends StatelessWidget {
  const DoctorMedicationsPage({
    super.key,
    this.authController,
    this.repository,
    this.healthRepository,
  });

  static const String routeName = '/doctor-medications';

  final AuthController? authController;
  final MedicationRepository? repository;
  final HealthRepository? healthRepository;

  @override
  Widget build(BuildContext context) {
    final session = authController ?? SessionScope.controllerOf(context);
    final token = session.accessToken;
    if (token == null) {
      return const SignedOutGate();
    }
    return Scaffold(
      appBar: AppBar(title: Text(AppStrings.manageMedications)),
      body: SafeArea(
        child: DoctorMedicationsView(
          accessToken: token,
          repository:
              repository ?? MedicationRepository(tokenStore: EphemeralTokenStore()),
          healthRepository:
              healthRepository ?? HealthRepository(tokenStore: EphemeralTokenStore()),
        ),
      ),
    );
  }
}

/// Driver of the doctor page: directory + per-patient medication rows.
class DoctorMedicationsView extends StatefulWidget {
  const DoctorMedicationsView({
    super.key,
    required this.accessToken,
    required this.repository,
    required this.healthRepository,
  });

  final String accessToken;
  final MedicationRepository repository;
  final HealthRepository healthRepository;

  @override
  State<DoctorMedicationsView> createState() => _DoctorMedicationsViewState();
}

class _DoctorMedicationsViewState extends State<DoctorMedicationsView> {
  List<PatientDirectoryEntry> _patients = [];
  List<Medication> _medications = [];
  List<Symptom> _symptoms = [];
  PatientDirectoryEntry? _selected;
  Object? _error;
  bool _loading = true;
  bool _loadingMeds = false;

  @override
  void initState() {
    super.initState();
    _loadDirectory();
  }

  Future<void> _loadDirectory() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final patients = await widget.repository
          .fetchPatientDirectory(access: widget.accessToken);
      if (!mounted) return;
      setState(() {
        _patients = patients;
        _selected = patients.isNotEmpty ? patients.first : null;
        _loading = false;
      });
      if (_selected != null) _loadMedications();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  Future<void> _loadMedications() async {
    final patient = _selected;
    if (patient == null) return;
    setState(() {
      _loadingMeds = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        widget.repository.listMedicationsForPatient(
          access: widget.accessToken,
          patientUid: patient.uid,
        ),
        widget.healthRepository.listSymptomsForPatient(
          access: widget.accessToken,
          patientUid: patient.uid,
        ),
      ]);
      if (!mounted) return;
      setState(() {
        _medications = results[0] as List<Medication>;
        _symptoms = results[1] as List<Symptom>;
        _loadingMeds = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loadingMeds = false;
      });
    }
  }

  Future<void> _openForm({Medication? medication}) async {
    final patient = _selected;
    if (patient == null) return;
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => MedicationFormPage(
          accessToken: widget.accessToken,
          repository: widget.repository,
          medication: medication,
          patientUid: medication == null ? patient.uid : null,
        ),
      ),
    );
    if (result == true && mounted) _loadMedications();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _patients.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 48),
              const SizedBox(height: 12),
              Text(AppStrings.medicationLoadFailed),
              const SizedBox(height: 16),
              OutlinedButton(
                onPressed: _loadDirectory,
                child: Text(AppStrings.retry),
              ),
            ],
          ),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _selected == null ? _loadDirectory : _loadMedications,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_patients.isEmpty)
            Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Text(AppStrings.noPatientsFound),
            )
          else ...[
            DropdownButtonFormField<PatientDirectoryEntry>(
              initialValue: _selected,
              decoration: InputDecoration(
                labelText: AppStrings.patient,
                prefixIcon: Icon(Icons.person_outline),
              ),
              items: [
                for (final p in _patients)
                  DropdownMenuItem(
                    value: p,
                    child: Text(
                      p.fullName.isEmpty ? p.email : p.fullName,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: (p) {
                if (p == null) return;
setState(() {
                  _selected = p;
                  _medications = const [];
                  _symptoms = const [];
                });
                _loadMedications();
              },
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${AppStrings.medications.toUpperCase()} · ${_selected?.fullName ?? _selected?.email ?? ''}',
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                ),
                TextButton.icon(
                  onPressed: _openForm,
                  icon: const Icon(Icons.add, size: 18),
                  label: Text(AppStrings.addMedication),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (_loadingMeds)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_medications.isEmpty)
              Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Text(AppStrings.noMedications),
              )
            else
              for (final med in _medications)
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.medication_outlined),
                    title: Text(med.displayName),
                    subtitle: Text(
                      [
                        if (med.frequency.isNotEmpty) med.frequency,
                        if (med.dosage.isNotEmpty) med.dosage,
                      ].join(' · '),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: const Icon(Icons.edit_outlined),
                    onTap: () => _openForm(medication: med),
                  ),
                ),
            const SizedBox(height: 24),
            Text(
              '${AppStrings.symptoms.toUpperCase()} · ${_selected?.fullName ?? _selected?.email ?? ''}',
              style: Theme.of(context).textTheme.labelSmall,
            ),
            const SizedBox(height: 8),
            if (_loadingMeds)
              const SizedBox.shrink()
            else if (_symptoms.isEmpty)
              Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Text(AppStrings.noSymptoms),
              )
            else
              for (final symptom in _symptoms.take(10))
                Card(
                  child: ListTile(
                    dense: true,
                    leading: Icon(
                      symptom.painLevel != null && symptom.painLevel! >= 7
                          ? Icons.warning_amber_rounded
                          : Icons.health_and_safety_outlined,
                      color: symptom.painLevel != null && symptom.painLevel! >= 7
                          ? AppColors.emergency
                          : AppColors.primary,
                    ),
                    title: Text(
                      symptom.symptomTypeName ?? symptom.symptomTypeCode,
                    ),
                    subtitle: Text([
                      if (symptom.painLevel != null)
                        '${AppStrings.painLevel}: ${symptom.painLevel}/10',
                      if (symptom.durationMinutes != null)
                        '${symptom.durationMinutes} min',
                      if (symptom.recordedAt != null)
                        _formatTime(symptom.recordedAt),
                    ].join(' · ')),
                  ),
                ),
            ],
          ],
        ),
      );
  }

  String _formatTime(String? iso) {
    final dt = iso == null ? null : DateTime.tryParse(iso)?.toLocal();
    if (dt == null) return '';
    return '${dt.day}/${dt.month}/${dt.year} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }
}