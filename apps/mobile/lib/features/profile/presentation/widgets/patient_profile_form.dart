import 'package:flutter/material.dart';

import '../../../../core/constants/app_strings.dart';
import '../../data/profile_repository.dart';

class PatientProfileForm extends StatefulWidget {
  const PatientProfileForm({
    super.key,
    required this.initial,
    required this.onSubmit,
    this.onCancel,
    this.readOnly = false,
    this.facilityLoader,
  });

  final PatientProfile initial;
  final Future<void> Function(PatientProfile updated) onSubmit;
  final VoidCallback? onCancel;
  final bool readOnly;

  /// Loads the public facility directory. Injected so widget tests do not need
  /// a live backend; omit it to hide the picker (read-only summary).
  final Future<List<FacilityOption>> Function()? facilityLoader;

  @override
  State<PatientProfileForm> createState() => _PatientProfileFormState();
}

class _PatientProfileFormState extends State<PatientProfileForm> {
  late final TextEditingController _dob;
  late final TextEditingController _gender;
  late final TextEditingController _genotype;
  late final TextEditingController _diagnosisDate;
  late final TextEditingController _primaryDiagnosis;
  late final TextEditingController _contactName;
  late final TextEditingController _contactPhone;
  late final TextEditingController _contactRelation;
  late final TextEditingController _region;
  late final TextEditingController _city;
  late final TextEditingController _notes;
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  bool _saving = false;
  List<FacilityOption> _facilities = const [];
  String? _facilityUid;

  @override
  void initState() {
    super.initState();
    final p = widget.initial;
    _dob = TextEditingController(text: p.dateOfBirth ?? '');
    _gender = TextEditingController(text: p.gender ?? '');
    _genotype = TextEditingController(text: p.genotype ?? '');
    _diagnosisDate = TextEditingController(text: p.diagnosisDate ?? '');
    _primaryDiagnosis =
        TextEditingController(text: p.primaryDiagnosis ?? '');
    _contactName = TextEditingController(text: p.emergencyContactName ?? '');
    _contactPhone = TextEditingController(text: p.emergencyContactPhone ?? '');
    _contactRelation =
        TextEditingController(text: p.emergencyContactRelation ?? '');
    _region = TextEditingController(text: p.addressRegion ?? '');
    _city = TextEditingController(text: p.addressCity ?? '');
    _notes = TextEditingController(text: p.notes);
    _facilityUid = p.facilityUid;
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadFacilities());
  }

  /// Treats the server directory as the only source of truth for facilities —
  /// the client never invents a clinic name (§6).
  Future<void> _loadFacilities() async {
    if (_facilities.isNotEmpty || widget.facilityLoader == null) return;
    final rows = await widget.facilityLoader!();
    if (!mounted || rows.isEmpty) return;
    setState(() => _facilities = rows);
  }

  @override
  void dispose() {
    for (final c in [
      _dob, _gender, _genotype, _diagnosisDate, _primaryDiagnosis,
      _contactName, _contactPhone, _contactRelation, _region, _city, _notes,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  static final List<String> _genotypes = [
    'SS', 'SC', 'SBetaThal', 'SBetaC', 'unknown',
  ];
  static final List<String> _genders = [
    'FEMALE', 'MALE', 'OTHER', 'UNSPECIFIED',
  ];

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    // The API rejects a profile with no treating facility; say so here rather
    // than letting the request fail with a raw validation error.
    if (!widget.readOnly && _facilityUid == null) {
      setState(() => _saving = true);
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(AppStrings.facilityRequired)));
      setState(() => _saving = false);
      return;
    }
    setState(() => _saving = true);
    try {
      await widget.onSubmit(
        PatientProfile(
          dateOfBirth: _dob.text.isEmpty ? null : _dob.text,
          gender: _gender.text.isEmpty ? null : _gender.text,
          genotype: _genotype.text.isEmpty ? null : _genotype.text,
          diagnosisDate: _diagnosisDate.text.isEmpty ? null : _diagnosisDate.text,
          primaryDiagnosis: _primaryDiagnosis.text,
          emergencyContactName: _contactName.text,
          emergencyContactPhone: _contactPhone.text,
          emergencyContactRelation: _contactRelation.text,
          addressRegion: _region.text,
          addressCity: _city.text,
          facilityUid: _facilityUid,
          notes: _notes.text,
        ),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(AppStrings.saved)));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _dropdownField({
    required String label,
    required TextEditingController controller,
    required List<String> values,
  }) {
    return DropdownButtonFormField<String>(
      initialValue:
          values.contains(controller.text) ? controller.text : null,
      decoration: InputDecoration(labelText: label),
      items: [
        for (final v in values)
          DropdownMenuItem(value: v, child: Text(v)),
      ],
      onChanged: widget.readOnly
          ? null
          : (v) => controller.value = TextEditingValue(text: v ?? ''),
    );
  }

  /// Treating-facility picker (§6). Read-only mode shows the saved facility as
  /// text; edit mode lists the server directory with no free-typing.
  Widget _facilityField(bool readOnly) {
    if (readOnly) {
      final name = widget.initial.facilityName ?? _facilityUid;
      return InputDecorator(
        decoration: InputDecoration(
          labelText: AppStrings.treatingFacility,
          prefixIcon: Icon(Icons.local_hospital_outlined),
        ),
        child: Text(
          (name == null || name.isEmpty) ? AppStrings.facilityNotSet : name,
          style: TextStyle(
            color: (name == null || name.isEmpty)
                ? Theme.of(context).disabledColor
                : null,
          ),
        ),
      );
    }
    return DropdownButtonFormField<String>(
      initialValue: _facilityUid,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: AppStrings.treatingFacility,
        prefixIcon: const Icon(Icons.local_hospital_outlined),
        helperText: _facilities.isEmpty
            ? AppStrings.facilityDirectoryUnavailable
            : AppStrings.facilityRequired,
      ),
      items: [
        for (final f in _facilities)
          DropdownMenuItem(value: f.uid, child: Text(f.label, overflow: TextOverflow.ellipsis)),
      ],
      onChanged: (v) => setState(() => _facilityUid = v),
    );
  }

  @override
  Widget build(BuildContext context) {
    final readOnly = widget.readOnly;
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            AppStrings.medicalIdentity,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _dob,
            readOnly: readOnly,
            decoration: InputDecoration(
              labelText: AppStrings.dateOfBirth,
              prefixIcon: Icon(Icons.cake_outlined),
            ),
            keyboardType: TextInputType.datetime,
            validator: readOnly
                ? null
                : (v) {
                    if (v == null || v.isEmpty) return null;
                    final digits = v.replaceAll(RegExp(r'\D'), '');
                    if (digits.length != 8) {
                      return 'Use YYYY-MM-DD';
                    }
                    return null;
                  },
          ),
          const SizedBox(height: 12),
          _dropdownField(
            label: AppStrings.gender,
            controller: _gender,
            values: _genders,
          ),
          const SizedBox(height: 12),
          _dropdownField(
            label: AppStrings.genotype,
            controller: _genotype,
            values: _genotypes,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _diagnosisDate,
            readOnly: readOnly,
            decoration: InputDecoration(
              labelText: AppStrings.diagnosisDate,
              prefixIcon: Icon(Icons.calendar_today_outlined),
            ),
            keyboardType: TextInputType.datetime,
            validator: readOnly
                ? null
                : (v) {
                    if (v == null || v.isEmpty) return null;
                    return v.replaceAll(RegExp(r'\D'), '').length == 8
                        ? null
                        : 'Use YYYY-MM-DD';
                  },
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _primaryDiagnosis,
            readOnly: readOnly,
            decoration: InputDecoration(
              labelText: AppStrings.primaryDiagnosis,
              prefixIcon: Icon(Icons.biotech_outlined),
            ),
          ),
          const SizedBox(height: 24),
          Text(AppStrings.emergencyContactName.toUpperCase(),
              style: Theme.of(context).textTheme.labelSmall),
          const SizedBox(height: 8),
          TextFormField(
            controller: _contactName,
            readOnly: readOnly,
            textCapitalization: TextCapitalization.words,
            decoration: InputDecoration(
              labelText: AppStrings.emergencyContactName,
              prefixIcon: Icon(Icons.person_outline),
            ),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _contactPhone,
            readOnly: readOnly,
            keyboardType: TextInputType.phone,
            decoration: InputDecoration(
              labelText: AppStrings.emergencyContactPhone,
              prefixIcon: Icon(Icons.phone_outlined),
            ),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _contactRelation,
            readOnly: readOnly,
            textCapitalization: TextCapitalization.words,
            decoration: InputDecoration(
              labelText: AppStrings.emergencyContactRelation,
              prefixIcon: Icon(Icons.family_restroom),
            ),
          ),
          const SizedBox(height: 24),
          Text(AppStrings.addressRegion.toUpperCase(),
              style: Theme.of(context).textTheme.labelSmall),
          const SizedBox(height: 8),
          TextFormField(
            controller: _region,
            readOnly: readOnly,
            decoration: InputDecoration(
              labelText: AppStrings.addressRegion,
              prefixIcon: Icon(Icons.place_outlined),
            ),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _city,
            readOnly: readOnly,
            decoration: InputDecoration(
              labelText: AppStrings.addressCity,
              prefixIcon: Icon(Icons.location_city_outlined),
            ),
          ),
          const SizedBox(height: 24),
          Text(AppStrings.treatingFacility.toUpperCase(),
              style: Theme.of(context).textTheme.labelSmall),
          const SizedBox(height: 8),
          _facilityField(readOnly),
          const SizedBox(height: 24),
          TextFormField(
            controller: _notes,
            readOnly: readOnly,
            maxLines: 3,
            decoration: InputDecoration(
              labelText: AppStrings.notes,
              alignLabelWithHint: true,
              helperText: AppStrings.privateNote,
              prefixIcon: const Icon(Icons.lock_outline),
            ),
          ),
          const SizedBox(height: 24),
          if (!readOnly) ...[
            FilledButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(AppStrings.save),
            ),
            if (widget.onCancel != null) ...[
              const SizedBox(height: 8),
              TextButton(
                onPressed: widget.onCancel,
                child: Text(AppStrings.cancel),
              ),
            ],
          ],
        ],
      ),
    );
  }
}