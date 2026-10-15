import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_strings.dart';
import '../../../../core/l10n/app_localizations.dart';
import '../../../auth/domain/auth_types.dart';
import '../../data/medication_repository.dart';
import '../../../../core/theme/app_shapes.dart';

/// Medication detail: schedules, dose logging (status-aware), dose history
/// and the stop (soft-delete) action.
class MedicationDetailPage extends StatefulWidget {
  const MedicationDetailPage({
    super.key,
    required this.accessToken,
    required this.repository,
    required this.medication,
  });

  final String accessToken;
  final MedicationRepository repository;
  final Medication medication;

  @override
  State<MedicationDetailPage> createState() => _MedicationDetailPageState();
}

class _MedicationDetailPageState extends State<MedicationDetailPage> {
  List<MedicationSchedule> _schedules = [];
  List<MedicationEvent> _events = [];
  MedicationSchedule? _selectedSchedule;
  Object? _error;
  bool _loading = true;
  bool _logging = false;

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
        widget.repository.listSchedules(
          access: widget.accessToken,
          medicationUid: widget.medication.uid,
        ),
        widget.repository.listEvents(
          access: widget.accessToken,
          medicationUid: widget.medication.uid,
        ),
      ]);
      if (!mounted) return;
      setState(() {
        _schedules = results[0] as List<MedicationSchedule>;
        _events = results[1] as List<MedicationEvent>;
        if (_schedules.isNotEmpty &&
            (_selectedSchedule == null ||
                !_schedules.any((s) => s.uid == _selectedSchedule!.uid))) {
          _selectedSchedule = _schedules.first;
        }
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

  Future<void> _log(String status) async {
    final schedule = _selectedSchedule;
    if (schedule == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppStrings.noSchedules)),
      );
      return;
    }
    setState(() => _logging = true);
    try {
      await widget.repository.logDose(
        access: widget.accessToken,
        medicationUid: widget.medication.uid,
        scheduleUid: schedule.uid,
        status: status,
        takenAt: status == 'TAKEN' ? DateTime.now() : null,
      );
      if (!mounted) return;
      setState(() => _logging = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppStrings.doseLogged)),
      );
      _load();
    } on AuthException catch (e) {
      if (!mounted) return;
      setState(() => _logging = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      if (!mounted) return;
      setState(() => _logging = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppStrings.doseLogFailed)),
      );
    }
  }

  Future<void> _addSchedule() async {
    final created = await showDialog<_ScheduleDraft>(
      context: context,
      builder: (_) => const _ScheduleDialog(),
    );
    if (created == null || !mounted) return;
    try {
      await widget.repository.createSchedule(
        access: widget.accessToken,
        medicationUid: widget.medication.uid,
        timeOfDay: created.time,
        daysOfWeek: created.days,
        notes: created.notes,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppStrings.scheduleSaved)),
      );
      _load();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppStrings.medicationSaveFailed)),
      );
    }
  }

  Future<void> _removeSchedule(MedicationSchedule schedule) async {
    if (_selectedSchedule?.uid == schedule.uid) {
      _selectedSchedule = null;
    }
    try {
      await widget.repository.deleteSchedule(
        access: widget.accessToken,
        medicationUid: widget.medication.uid,
        scheduleUid: schedule.uid,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppStrings.scheduleRemoved)),
      );
      _load();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppStrings.medicationSaveFailed)),
      );
    }
  }

  Future<void> _stopMedication() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(AppStrings.stopMedication),
        content: Text(AppStrings.stopMedicationConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(AppStrings.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(AppStrings.stopMedication),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await widget.repository.stopMedication(
        access: widget.accessToken,
        uid: widget.medication.uid,
      );
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppStrings.medicationSaveFailed)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.medication.displayName)),
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
              Text(AppStrings.medicationLoadFailed),
              const SizedBox(height: 16),
              OutlinedButton(
                onPressed: _load,
                child: Text(AppStrings.retry),
              ),
            ],
          ),
        ),
      );
    }
    final med = widget.medication;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        med.displayName,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                    _StatusBadge(active: med.isActive),
                  ],
                ),
                if (med.genericName.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(med.genericName,
                      style: Theme.of(context).textTheme.bodySmall),
                ],
                const Divider(height: 24),
                _InfoRow(label: AppStrings.route, value: med.route),
                if (med.dosage.isNotEmpty)
                  _InfoRow(label: AppStrings.dosage, value: med.dosage),
                if (med.frequency.isNotEmpty)
                  _InfoRow(label: AppStrings.frequency, value: med.frequency),
                if (med.startDate != null)
                  _InfoRow(label: AppStrings.startDate, value: med.startDate!),
                if (med.endDate != null)
                  _InfoRow(label: AppStrings.endDate, value: med.endDate!),
              ],
            ),
          ),
        ),
        if (med.instructions.isNotEmpty) ...[
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.menu_book_outlined, size: 18),
                      const SizedBox(width: 8),
                      Text(
                        AppLocalizations.of(context).tr('meds.instructions'),
                        style: Theme.of(context).textTheme.labelLarge,
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(med.instructions),
                ],
              ),
            ),
          ),
        ],
        const SizedBox(height: 16),
        Text(
          AppStrings.schedules.toUpperCase(),
          style: Theme.of(context).textTheme.labelSmall,
        ),
        const SizedBox(height: 8),
        if (_schedules.isEmpty)
          Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Text(AppStrings.noSchedules),
          )
        else
          for (final s in _schedules)
            Card(
              child: ListTile(
                leading: const Icon(Icons.schedule),
                title: Text(s.timeLabel),
                subtitle: Text(
                  s.daysOfWeek.join(', '),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: IconButton(
                  tooltip: AppStrings.removeSchedule,
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () => _removeSchedule(s),
                ),
              ),
            ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: _addSchedule,
            icon: const Icon(Icons.add_alarm_outlined),
            label: Text(AppStrings.addSchedule),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          AppStrings.recordDose.toUpperCase(),
          style: Theme.of(context).textTheme.labelSmall,
        ),
        const SizedBox(height: 8),
        if (_schedules.isEmpty)
          Text(AppStrings.noSchedules)
        else
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DropdownButtonFormField<MedicationSchedule>(
                initialValue: _selectedSchedule?.uid != null
                    ? _schedules.firstWhere(
                        (s) => s.uid == _selectedSchedule!.uid,
                        orElse: () => _schedules.first,
                      )
                    : null,
                decoration: InputDecoration(
                  labelText: AppStrings.scheduleTime,
                  prefixIcon: const Icon(Icons.access_time),
                ),
                items: [
                  for (final s in _schedules)
                    DropdownMenuItem(
                      value: s,
                      child: Text(
                        '${s.timeLabel} · ${s.daysOfWeek.join(', ')}',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: (s) => setState(() => _selectedSchedule = s),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final status in medicationStatuses)
                    FilledButton.tonal(
                      onPressed: _logging ? null : () => _log(status),
                      child: Text(_statusLabel(status)),
                    ),
                ],
              ),
            ],
          ),
        const SizedBox(height: 24),
        Text(
          AppStrings.doseHistory.toUpperCase(),
          style: Theme.of(context).textTheme.labelSmall,
        ),
        const SizedBox(height: 8),
        if (_events.isEmpty)
          Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Text(AppStrings.noDoseHistory),
          )
        else
          for (final e in _events.take(20))
            Card(
              child: ListTile(
                dense: true,
                leading: Icon(
                  e.status == 'TAKEN' ? Icons.check_circle : Icons.cancel_outlined,
                  color: e.status == 'TAKEN'
                      ? AppColors.success
                      : AppColors.emergency,
                ),
                title: Text(_statusLabel(e.status)),
                subtitle: Text(_formatTime(e.createdAt)),
              ),
            ),
        if (med.isActive) ...[
          const SizedBox(height: 24),
          Center(
            child: TextButton.icon(
              onPressed: _stopMedication,
              icon: const Icon(Icons.stop_circle_outlined),
              label: Text(AppStrings.stopMedication),
              style: TextButton.styleFrom(foregroundColor: AppColors.emergency),
            ),
          ),
        ],
      ],
    );
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'TAKEN':
        return AppStrings.doseTaken;
      case 'MISSED':
        return AppStrings.doseMissed;
      case 'SKIPPED':
        return AppStrings.doseSkipped;
      case 'SNOOZED':
        return AppStrings.doseSnoozed;
      default:
        return status;
    }
  }

  String _formatTime(String? iso) {
    final dt = iso == null ? null : DateTime.tryParse(iso)?.toLocal();
    if (dt == null) return '';
    return '${dt.day}/${dt.month}/${dt.year} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.active});

  final bool active;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: active ? AppColors.success : AppColors.emergency,
        borderRadius: AppShapes.tile,
      ),
      child: Text(
        active ? AppStrings.active : AppStrings.stopped,
        style: const TextStyle(
          color: AppColors.onPrimary,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
            child: Text(
              label,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}

class _ScheduleDraft {
  const _ScheduleDraft({
    required this.time,
    required this.days,
    required this.notes,
  });

  final String time;
  final List<String> days;
  final String notes;
}

class _ScheduleDialog extends StatefulWidget {
  const _ScheduleDialog();

  @override
  State<_ScheduleDialog> createState() => _ScheduleDialogState();
}

class _ScheduleDialogState extends State<_ScheduleDialog> {
  TimeOfDay _time = const TimeOfDay(hour: 8, minute: 0);
  final Set<String> _days = {'MON'};
  final _notes = TextEditingController();

  static const _dayOrder = ['MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN'];

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _time,
    );
    if (picked != null) setState(() => _time = picked);
  }

  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(AppStrings.addSchedule),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.access_time),
              title: Text('${AppStrings.scheduleTime}: ${_time.format(context)}'),
              trailing: TextButton(
                onPressed: _pickTime,
                child: Text(AppStrings.scheduleTimeHint),
              ),
            ),
            const SizedBox(height: 8),
            Text(AppStrings.scheduleDays),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final day in _dayOrder)
                  FilterChip(
                    label: Text(day),
                    selected: _days.contains(day),
                    onSelected: (sel) => setState(() {
                      if (sel) {
                        _days.add(day);
                      } else {
                        _days.remove(day);
                      }
                    }),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _notes,
              decoration: InputDecoration(
                labelText: AppStrings.scheduleNotes,
              ),
              maxLines: 2,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(AppStrings.cancel),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(
            context,
            _ScheduleDraft(
              time: '${_time.hour.toString().padLeft(2, '0')}:'
                  '${_time.minute.toString().padLeft(2, '0')}:00',
              days: _days.toList(),
              notes: _notes.text.trim(),
            ),
          ),
          child: Text(AppStrings.save),
        ),
      ],
    );
  }
}