import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_strings.dart';
import '../../../auth/domain/auth_types.dart';
import '../../data/health_repository.dart';

/// Record a symptom (pain level, type, triggers, duration).
class SymptomFormPage extends StatefulWidget {
  const SymptomFormPage({
    super.key,
    required this.accessToken,
    required this.repository,
  });

  final String accessToken;
  final HealthRepository repository;

  @override
  State<SymptomFormPage> createState() => _SymptomFormPageState();
}

class _SymptomFormPageState extends State<SymptomFormPage> {
  final _notes = TextEditingController();
  final _duration = TextEditingController();

  List<SymptomType> _types = [];
  Object? _loadError;
  bool _loading = true;
  bool _saving = false;

  SymptomType? _selectedType;
  int _painLevel = 0;
  final Set<String> _triggers = {};

  @override
  void initState() {
    super.initState();
    _loadTypes();
  }

  Future<void> _loadTypes() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final types = await widget.repository.listSymptomTypes(
        access: widget.accessToken,
      );
      if (!mounted) return;
      setState(() {
        _types = types;
        _selectedType = types.firstWhere(
          (t) => t.isPainRelated,
          orElse: () => types.isNotEmpty ? types.first : const SymptomType(
                code: '',
                name: '',
                isPainRelated: false,
              ),
        );
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadError = e;
        _loading = false;
      });
    }
  }

  Future<void> _save() async {
    final type = _selectedType;
    if (type == null || type.code.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppStrings.symptomType)),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      final duration = int.tryParse(_duration.text.trim());
      await widget.repository.recordSymptom(
        access: widget.accessToken,
        payload: {
          if (type.code.isNotEmpty) 'symptom_type_code': type.code,
          'pain_level': _painLevel,
          'triggers': _triggers.toList(),
          if (duration != null && duration > 0) 'duration_minutes': duration,
          if (_notes.text.trim().isNotEmpty) 'notes': _notes.text.trim(),
          'recorded_at': DateTime.now().toUtc().toIso8601String(),
        },
      );
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppStrings.symptomSaved)),
      );
      Navigator.pop(context, true);
    } on AuthException catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppStrings.symptomSaveFailed)),
      );
    }
  }

  @override
  void dispose() {
    _notes.dispose();
    _duration.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(AppStrings.recordSymptom)),
      body: _buildBody(),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: FilledButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(AppStrings.save),
          ),
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_loadError != null || _types.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: EdgeInsets.all(24),
              child: Text(AppStrings.symptomSaveFailed),
            ),
            OutlinedButton(
              onPressed: _loadTypes,
              child: Text(AppStrings.retry),
            ),
          ],
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          AppStrings.symptomType,
          style: Theme.of(context).textTheme.labelLarge,
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<SymptomType>(
          initialValue: _selectedType,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            focusedBorder: OutlineInputBorder(),
          ),
          items: [
            for (final t in _types)
              DropdownMenuItem(
                value: t,
                child: Row(
                  children: [
                    Expanded(
                      child: Text(t.name.isEmpty ? t.code : t.name),
                    ),
                    if (t.isPainRelated)
                      const Padding(
                        padding: EdgeInsets.only(right: 12),
                        child: Icon(Icons.whatshot, size: 14),
                      ),
                  ],
                ),
              ),
          ],
          onChanged: (t) => setState(() => _selectedType = t),
        ),
        const SizedBox(height: 24),
        Text(
          AppStrings.painScale,
          style: Theme.of(context).textTheme.labelLarge,
        ),
        Slider(
          value: _painLevel.toDouble(),
          min: 0,
          max: 10,
          divisions: 10,
          label: '$_painLevel',
          activeColor: _painLevel >= 7
              ? AppColors.emergency
              : AppColors.primary,
          onChanged: (v) => setState(() => _painLevel = v.round()),
        ),
        Center(
          child: Text(
            '$_painLevel/10',
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
        if (_painLevel >= 7) ...[
          const SizedBox(height: 12),
          Card(
            color: AppColors.emergency.withValues(alpha: 0.08),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  const Icon(Icons.warning_amber_rounded,
                      color: AppColors.emergency),
                  const SizedBox(width: 12),
                  Expanded(child: Text(AppStrings.crisisHelp)),
                ],
              ),
            ),
          ),
        ],
        const SizedBox(height: 24),
        Text(AppStrings.triggers, style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final trigger in AppStrings.triggerOptions)
              FilterChip(
                label: Text(trigger),
                selected: _triggers.contains(trigger),
                onSelected: (sel) => setState(() {
                  if (sel) {
                    _triggers.add(trigger);
                  } else {
                    _triggers.remove(trigger);
                  }
                }),
              ),
          ],
        ),
        const SizedBox(height: 24),
        TextField(
          controller: _duration,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            labelText: AppStrings.durationMinutes,
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _notes,
          maxLines: 3,
          decoration: InputDecoration(
            labelText: AppStrings.notes,
            border: OutlineInputBorder(),
          ),
        ),
      ],
    );
  }
}