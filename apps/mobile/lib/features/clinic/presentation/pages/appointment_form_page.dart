import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../../../../core/l10n/app_localizations.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../auth/data/token_store.dart';
import '../../../auth/domain/auth_types.dart';
import '../../../doctor_network/data/doctor_directory_repository.dart';
import '../../data/appointments_repository.dart';
import 'clinic_page.dart';

/// The localization key a booking form should complain about, or null when the
/// chosen slot is usable.
///
/// [now] is passed in rather than read from the clock so the guard is testable:
/// today with an early time is the case that actually reaches it, since the date
/// picker clamps the day but not the hour.
String? appointmentScheduleProblem(DateTime? scheduled, DateTime now) {
  if (scheduled == null) return 'clinic.pickDateTime';
  if (scheduled.isBefore(now)) return 'clinic.inPast';
  return null;
}

/// Book a clinic visit (§11).
///
/// The facility picker only ever lists verified clinics from
/// `GET /facilities/`, because the server rejects an unverified venue outright —
/// there is no free-text name to guess with and no hardcoded hospital list. With
/// an [existing] appointment this form reschedules instead, which the server
/// records as history rather than an in-place edit.
class AppointmentFormPage extends StatefulWidget {
  const AppointmentFormPage({
    super.key,
    required this.accessToken,
    required this.repository,
    this.existing,
    this.client,
    this.directoryRepository,
  });

  final String accessToken;
  final AppointmentsRepository repository;
  final ClinicAppointment? existing;

  /// Injected by widget tests to serve the facility directory.
  final http.Client? client;

  /// Source of the verified clinician list. Injected by tests; production builds
  /// read the same registry the care directory shows.
  final DoctorDirectoryRepository? directoryRepository;

  @override
  State<AppointmentFormPage> createState() => _AppointmentFormPageState();
}

class _AppointmentFormPageState extends State<AppointmentFormPage> {
  final _formKey = GlobalKey<FormState>();
  final _reason = TextEditingController();

  List<BookableFacility> _facilities = const [];
  Object? _facilityError;
  bool _loadingFacilities = true;

  List<VerifiedProfessional> _clinicians = const [];
  Object? _clinicianError;
  bool _loadingClinicians = true;

  String _facilityUid = '';
  String _clinicianUid = '';
  String _type = 'FOLLOW_UP';
  DateTime? _date;
  TimeOfDay? _time;
  TimeOfDay _reminderTime = const TimeOfDay(hour: 7, minute: 0);
  int _duration = 30;
  bool _reminders = true;
  bool _saving = false;

  bool get _isReschedule => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    if (existing != null) {
      _facilityUid = existing.facilityUid;
      _type = existing.appointmentType;
      _reason.text = existing.reason;
      _clinicianUid = existing.doctorUid;
      _duration = existing.durationMinutes;
      _reminders = existing.reminderEnabled;
      final parsed = DateTime.tryParse(existing.scheduledAt)?.toLocal();
      _date = parsed;
      if (parsed != null) _time = TimeOfDay.fromDateTime(parsed);
      if (existing.reminderTimes.isNotEmpty) {
        final parts = existing.reminderTimes.first.split(':');
        final hour = int.tryParse(parts.first);
        final minute = parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0;
        if (hour != null) {
          _reminderTime = TimeOfDay(hour: hour % 24, minute: minute);
        }
      }
    }
    _loadFacilities();
    _loadClinicians();
  }

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  Future<void> _loadFacilities() async {
    setState(() {
      _loadingFacilities = true;
      _facilityError = null;
    });
    try {
      final facilities = await widget.repository.listFacilities(
        access: widget.accessToken,
        client: widget.client,
      );
      if (!mounted) return;
      setState(() {
        _facilities = facilities;
        // Pre-select only when there is no choice to make. With several
        // verified venues the patient has to say which one they are going to:
        // booking an appointment at the wrong hospital is worse than one extra
        // tap, and the server only ever accepts a verified uid.
        if (_facilityUid.isEmpty && facilities.length == 1) {
          _facilityUid = facilities.first.uid;
        }
        _loadingFacilities = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _facilityError = e;
        _loadingFacilities = false;
      });
    }
  }

  DateTime? get _scheduledAt {
    final date = _date;
    final time = _time;
    if (date == null || time == null) return null;
    return DateTime(date.year, date.month, date.day, time.hour, time.minute);
  }

  String _formatTime(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  void _toast(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  String _messageFor(Object error) {
    final s = AppLocalizations.of(context);
    if (error is AuthException) {
      final message = error.message.trim();
      if (message.isNotEmpty && !message.contains('Exception')) return message;
    }
    return s.tr(_isReschedule ? 'clinic.rescheduleFailed' : 'clinic.bookFailed');
  }

  /// The name for a chosen clinician.
  ///
  /// On reschedule the booked clinician may be a psychologist rather than a
  /// physician, and the booking picker only lists physicians — so fall back to
  /// the name the appointment already carries instead of showing nothing.
  String _clinicianName(String uid) {
    for (final clinician in _clinicians) {
      if (clinician.uid == uid) return clinician.subtitle;
    }
    final booked = widget.existing;
    if (booked != null && booked.doctorUid == uid) return booked.doctorName;
    return '';
  }

  /// Verified clinicians, from the same registry as the care directory.
  ///
  /// A clinician is never typed in as a bare uid: only an approved, active
  /// professional the API returned can be chosen, so a booking cannot be aimed
  /// at an unverified or suspended account.
  Future<void> _loadClinicians() async {
    setState(() {
      _loadingClinicians = true;
      _clinicianError = null;
    });
    try {
      final clinicians = await (widget.directoryRepository ??
              DoctorDirectoryRepository(tokenStore: EphemeralTokenStore()))
          .listPhysicians(access: widget.accessToken);
      if (!mounted) return;
      setState(() {
        _clinicians = clinicians;
        _loadingClinicians = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _clinicianError = e;
        _loadingClinicians = false;
      });
    }
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _date ?? now.add(const Duration(days: 1)),
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: DateTime(now.year + 2),
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(context: context, initialTime: _time ?? const TimeOfDay(hour: 9, minute: 0));
    if (picked != null) setState(() => _time = picked);
  }

  Future<void> _pickReminderTime() async {
    final picked = await showTimePicker(context: context, initialTime: _reminderTime);
    if (picked != null) setState(() => _reminderTime = picked);
  }

  Future<void> _save() async {
    final s = AppLocalizations.of(context);
    if (!_formKey.currentState!.validate()) return;
    final scheduled = _scheduledAt;
    final problem = appointmentScheduleProblem(scheduled, DateTime.now());
    if (scheduled == null || problem != null) {
      _toast(s.tr(problem ?? 'clinic.pickDateTime'));
      return;
    }
    setState(() => _saving = true);
    try {
      if (_isReschedule) {
        await widget.repository.reschedule(
          access: widget.accessToken,
          uid: widget.existing!.uid,
          scheduledAt: scheduled.toUtc().toIso8601String(),
          reason: _reason.text.trim(),
        );
      } else {
        await widget.repository.book(
          access: widget.accessToken,
          facilityUid: _facilityUid,
          scheduledAt: scheduled.toUtc().toIso8601String(),
          appointmentType: _type,
          doctorUid: _clinicianUid.isEmpty ? null : _clinicianUid,
          reason: _reason.text.trim(),
          durationMinutes: _duration,
          reminderEnabled: _reminders,
          reminderTimes: [_formatTime(_reminderTime)],
        );
      }
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      _toast(_messageFor(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(s.tr(_isReschedule ? 'clinic.reschedule' : 'clinic.book')),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (!_isReschedule) ...[
              DropdownButtonFormField<String>(
                // `DropdownButtonFormField` asserts that the value matches an
                // item, so "nothing chosen" has to be null, not an empty string.
                initialValue: (_loadingFacilities || _facilityUid.isEmpty)
                    ? null
                    : _facilityUid,
                isExpanded: true,
                decoration: InputDecoration(labelText: s.tr('clinic.facility')),
                items: [
                  for (final facility in _facilities)
                    DropdownMenuItem(
                      value: facility.uid,
                      child: Text(facility.subtitle),
                    ),
                ],
                onChanged: _loadingFacilities
                    ? null
                    : (value) => setState(() => _facilityUid = value ?? ''),
                validator: (value) => (value == null || value.isEmpty)
                    ? s.tr('clinic.facilityRequired')
                    : null,
              ),
              if ((_facilities.isEmpty && !_loadingFacilities) ||
                  _facilityError != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          _facilityError == null
                              ? s.tr('clinic.noFacilities')
                              : s.tr('clinic.loadFailed'),
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                      if (_facilityError != null)
                        TextButton(
                          onPressed: _loadFacilities,
                          child: Text(s.tr('common.retry')),
                        ),
                    ],
                  ),
                ),
              const SizedBox(height: AppSpacing.md),
              DropdownButtonFormField<String>(
                initialValue: _type,
                isExpanded: true,
                decoration: InputDecoration(labelText: s.tr('clinic.type')),
                items: [
                  for (final code in ClinicAppointment.appointmentTypes)
                    DropdownMenuItem(
                      value: code,
                      child: Text(appointmentTypeLabel(s, code)),
                    ),
                ],
                onChanged: (value) => setState(() => _type = value ?? 'FOLLOW_UP'),
              ),
              const SizedBox(height: AppSpacing.md),
            ],
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _pickDate,
                    icon: const Icon(Icons.calendar_today, size: 18),
                    label: Text(
                      _date == null
                          ? s.tr('clinic.date')
                          : '${_date!.year}-${_date!.month.toString().padLeft(2, '0')}-${_date!.day.toString().padLeft(2, '0')}',
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _pickTime,
                    icon: const Icon(Icons.schedule, size: 18),
                    label: Text(_time == null ? s.tr('clinic.time') : _time!.format(context)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            if (_isReschedule || _loadingClinicians)
              InputDecorator(
                decoration: InputDecoration(
                  labelText: s.tr('clinic.doctor'),
                  helperText: s.tr('clinic.doctorOptional'),
                ),
                child: _loadingClinicians
                    ? Text(s.tr('clinic.loadingClinicians'))
                    : Text(
                        _clinicianUid.isEmpty
                            ? s.tr('clinic.noDoctor')
                            : (_clinicianName(_clinicianUid).isEmpty
                                ? s.tr('clinic.noDoctor')
                                : _clinicianName(_clinicianUid)),
                      ),
              )
            else
              DropdownButtonFormField<String>(
                // `DropdownButtonFormField` asserts that the value matches an
                // item, so "no preference" has to be null, not an empty string.
                initialValue: _clinicianUid.isEmpty ? null : _clinicianUid,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: s.tr('clinic.doctor'),
                  helperText: s.tr('clinic.doctorOptional'),
                ),
                items: [
                  DropdownMenuItem(
                    value: '',
                    child: Text(s.tr('clinic.noPreference')),
                  ),
                  for (final clinician in _clinicians)
                    DropdownMenuItem(
                      value: clinician.uid,
                      child: Text(clinician.subtitle),
                    ),
                ],
                onChanged: (value) =>
                    setState(() => _clinicianUid = value ?? ''),
              ),
            if (_clinicianError != null)
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.sm),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        s.tr('clinic.loadFailed'),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                    TextButton(
                      onPressed: _loadClinicians,
                      child: Text(s.tr('common.retry')),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: _reason,
              maxLines: 3,
              maxLength: 500,
              decoration: InputDecoration(
                labelText: s.tr('clinic.reason'),
                helperText: s.tr('clinic.reasonHint'),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            DropdownButtonFormField<int>(
              initialValue: _duration,
              decoration: InputDecoration(labelText: s.tr('clinic.duration')),
              items: const [15, 30, 45, 60, 90]
                  .map((m) => DropdownMenuItem(value: m, child: Text('$m')))
                  .toList(),
              onChanged: (value) => setState(() => _duration = value ?? 30),
            ),
            if (!_isReschedule) ...[
              SwitchListTile(
                value: _reminders,
                onChanged: (value) => setState(() => _reminders = value),
                title: Text(s.tr('clinic.reminders')),
              ),
              if (_reminders)
                OutlinedButton.icon(
                  onPressed: _pickReminderTime,
                  icon: const Icon(Icons.notifications_active_outlined, size: 18),
                  label: Text(
                    '${s.tr('clinic.reminderTime')}: ${_formatTime(_reminderTime)}',
                  ),
                ),
            ],
            const SizedBox(height: AppSpacing.lg),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: Text(
                s.tr(
                  _saving
                      ? 'common.saving'
                      : (_isReschedule ? 'clinic.reschedule' : 'clinic.book'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}