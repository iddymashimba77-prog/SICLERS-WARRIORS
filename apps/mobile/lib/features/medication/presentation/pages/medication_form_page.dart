import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_strings.dart';
import '../../../auth/domain/auth_types.dart';
import '../../data/medication_repository.dart';

/// Create / edit a medication (approved FR-MED-002 create, update via [medication]).
///
/// Pushed via `MaterialPageRoute`; pops `true` when a record was saved so the
/// list view can refresh. All validation mirrors the server-side rules
/// (route vocabulary, end >= start).
class MedicationFormPage extends StatefulWidget {
  const MedicationFormPage({
    super.key,
    required this.accessToken,
    required this.repository,
    this.medication,
  });

  final String accessToken;
  final MedicationRepository repository;
  final Medication? medication;

  @override
  State<MedicationFormPage> createState() => _MedicationFormPageState();
}

class _MedicationFormPageState extends State<MedicationFormPage> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _name;
  late final TextEditingController _generic;
  late final TextEditingController _strength;
  late final TextEditingController _dosage;
  late final TextEditingController _frequency;
  String _route = 'ORAL';
  DateTime? _startDate;
  DateTime? _endDate;
  bool _saving = false;

  bool get _isEdit => widget.medication != null;

  @override
  void initState() {
    super.initState();
    final med = widget.medication;
    _name = TextEditingController(text: med?.name ?? '');
    _generic = TextEditingController(text: med?.genericName ?? '');
    _strength = TextEditingController(text: med?.strength ?? '');
    _dosage = TextEditingController(text: med?.dosage ?? '');
    _frequency = TextEditingController(text: med?.frequency ?? '');
    _route = med?.route ?? 'ORAL';
    _startDate = med?.startDate != null ? DateTime.tryParse(med!.startDate!) : null;
    _endDate = med?.endDate != null ? DateTime.tryParse(med!.endDate!) : null;
  }

  @override
  void dispose() {
    _name.dispose();
    _generic.dispose();
    _strength.dispose();
    _dosage.dispose();
    _frequency.dispose();
    super.dispose();
  }

  String _dateLabel(DateTime? d) {
    if (d == null) return AppStrings.startDate;
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  Future<void> _pickStart() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _startDate ?? now,
      firstDate: DateTime(now.year - 5),
      lastDate: DateTime(now.year + 5),
    );
    if (picked != null) setState(() => _startDate = picked);
  }

  Future<void> _pickEnd() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _endDate ?? (_startDate ?? now),
      firstDate: DateTime(now.year - 5),
      lastDate: DateTime(now.year + 10),
    );
    if (picked != null) setState(() => _endDate = picked);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final start = _startDate;
    final end = _endDate;
    if (start != null && end != null && end.isBefore(start)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text(AppStrings.startDateAfterEnd)),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      final med = Medication(
        uid: widget.medication?.uid ?? '',
        name: _name.text.trim(),
        genericName: _generic.text.trim(),
        strength: _strength.text.trim(),
        dosage: _dosage.text.trim(),
        route: _route,
        frequency: _frequency.text.trim(),
        startDate: _startDate?.toIso8601String().split('T').first,
        endDate: _endDate?.toIso8601String().split('T').first,
        isActive: widget.medication?.isActive ?? true,
        schedules: widget.medication?.schedules ?? const [],
        createdAt: widget.medication?.createdAt,
      );
      if (_isEdit) {
        await widget.repository.updateMedication(
          access: widget.accessToken,
          medication: med,
        );
      } else {
        await widget.repository.createMedication(
          access: widget.accessToken,
          medication: med,
        );
      }
      if (!mounted) return;
      Navigator.pop(context, true);
    } on AuthException catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            e.fieldErrors.isNotEmpty ? e.fieldErrors.values.first.first : e.message,
          ),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text(AppStrings.medicationSaveFailed)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEdit ? AppStrings.editMedication : AppStrings.addMedication),
      ),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              TextFormField(
                controller: _name,
                decoration: const InputDecoration(
                  labelText: AppStrings.medicationName,
                  hintText: AppStrings.medicationNameHint,
                  prefixIcon: Icon(Icons.medication_outlined),
                ),
                textInputAction: TextInputAction.next,
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Required' : null,
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _generic,
                      decoration: const InputDecoration(
                        labelText: AppStrings.genericName,
                        prefixIcon: Icon(Icons.science_outlined),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  SizedBox(
                    width: 130,
                    child: TextFormField(
                      controller: _strength,
                      decoration: const InputDecoration(
                        labelText: AppStrings.strength,
                        hintText: AppStrings.strengthHint,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _dosage,
                decoration: const InputDecoration(
                  labelText: AppStrings.dosage,
                  hintText: AppStrings.dosageHint,
                  prefixIcon: Icon(Icons.local_pharmacy_outlined),
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _frequency,
                decoration: const InputDecoration(
                  labelText: AppStrings.frequency,
                  hintText: AppStrings.frequencyHint,
                  prefixIcon: Icon(Icons.repeat),
                ),
                textInputAction: TextInputAction.next,
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Required' : null,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _route,
                decoration: const InputDecoration(
                  labelText: AppStrings.route,
                  prefixIcon: Icon(Icons.route_outlined),
                ),
                items: [
                  for (final r in medicationRoutes)
                    DropdownMenuItem(value: r, child: Text(r)),
                ],
                onChanged: (v) => setState(() => _route = v ?? 'ORAL'),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _pickStart,
                      child: Text(_dateLabel(_startDate)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _pickEnd,
                      child: Text(
                        _endDate == null
                            ? AppStrings.endDate
                            : '${AppStrings.endDate}: ${_dateLabel(_endDate)}',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: _saving ? null : _save,
                icon: _saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.check),
                label: Text(_isEdit ? AppStrings.save : AppStrings.addMedication),
              ),
              const SizedBox(height: 8),
              const Text(
                AppStrings.adherenceHelp,
                style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
              ),
            ],
          ),
        ),
      ),
    );
  }
}