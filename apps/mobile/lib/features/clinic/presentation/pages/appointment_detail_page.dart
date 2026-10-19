import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../../../../core/l10n/app_localizations.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../shared/widgets/state_views.dart';
import '../../../auth/domain/auth_types.dart';
import '../../data/appointments_repository.dart';
import 'appointment_form_page.dart';
import 'clinic_page.dart';

/// One clinic visit, with the two changes a patient may actually make.
///
/// Cancelling and rescheduling both go through the audited status endpoint and
/// both ask for a reason first: the server stores it against the appointment,
/// so a silent cancel would lose the only explanation of why it happened. A
/// visit that is cancelled, completed or a no-show is closed — the server keeps
/// its history and this screen offers nothing further.
class AppointmentDetailPage extends StatefulWidget {
  const AppointmentDetailPage({
    super.key,
    required this.accessToken,
    required this.repository,
    required this.appointmentUid,
    this.client,
  });

  final String accessToken;
  final AppointmentsRepository repository;
  final String appointmentUid;
  final http.Client? client;

  @override
  State<AppointmentDetailPage> createState() => _AppointmentDetailPageState();
}

class _AppointmentDetailPageState extends State<AppointmentDetailPage> {
  ClinicAppointment? _appointment;
  Object? _error;
  bool _loading = true;
  bool _working = false;

  /// Set after a cancel/reschedule actually changed the appointment; the
  /// back path pops `true` so the clinic list refreshes exactly when needed
  /// (and not on a plain look-around).
  bool _dirty = false;

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
      final appointment = await widget.repository.get(
        access: widget.accessToken,
        uid: widget.appointmentUid,
      );
      if (!mounted) return;
      setState(() {
        _appointment = appointment;
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

  String _messageFor(Object error) {
    final s = AppLocalizations.of(context);
    if (error is AuthException) {
      final message = error.message.trim();
      if (message.isNotEmpty && !message.contains('Exception')) return message;
    }
    return s.tr('clinic.loadFailed');
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  /// Cancellation requires a reason; the server records it on the appointment.
  Future<void> _cancel() async {
    final s = AppLocalizations.of(context);
    final reason = await showDialog<String>(
      context: context,
      builder: (dialogContext) => _ReasonDialog(
        title: s.tr('clinic.cancelTitle'),
        label: s.tr('clinic.cancelReason'),
        required: true,
      ),
    );
    if (reason == null || reason.trim().isEmpty) return;
    // The success toast must stay visible on THIS page; `_run` already set
    // `_dirty`, so leaving via back (PopScope) hands `true` to the clinic
    // list and it reloads its upcoming/past split.
    await _run(
      () => widget.repository.setStatus(
        access: widget.accessToken,
        uid: widget.appointmentUid,
        status: 'CANCELLED',
        reason: reason.trim(),
      ),
      s.tr('clinic.cancelled'),
      'clinic.cancelFailed',
    );
  }

  Future<void> _reschedule() async {
    final appointment = _appointment;
    if (appointment == null) return;
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => AppointmentFormPage(
          accessToken: widget.accessToken,
          repository: widget.repository,
          existing: appointment,
          client: widget.client,
        ),
      ),
    );
    if (changed == true && mounted) {
      _dirty = true;
      _toast(AppLocalizations.of(context).tr('clinic.rescheduled'));
      await _load();
    }
  }

  Future<bool> _run(
    Future<ClinicAppointment> Function() action,
    String successKey,
    String failureKey,
  ) async {
    setState(() => _working = true);
    try {
      final updated = await action();
      if (!mounted) return false;
      setState(() {
        _appointment = updated;
        _working = false;
        _dirty = true;
      });
      _toast(AppLocalizations.of(context).tr(successKey));
      return true;
    } catch (e) {
      if (!mounted) return false;
      setState(() => _working = false);
      final s = AppLocalizations.of(context);
      _toast(
        e is AuthException && e.message.trim().isNotEmpty
            ? e.message.trim()
            : s.tr(failureKey),
      );
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context);
    final appointment = _appointment;
    return Scaffold(
      appBar: AppBar(
        title: Text(s.tr('clinic.detail')),
        actions: [
          IconButton(
            tooltip: s.tr('common.refresh'),
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: PopScope(
        // Back (system, gesture or AppBar) must carry the dirty flag so the
        // clinic list reloads after a cancel/reschedule — and only then.
        canPop: false,
        onPopInvokedWithResult: (didPop, result) {
          if (didPop) return;
          Navigator.of(context).pop(_dirty);
        },
        child: _buildBody(),
      ),
      bottomNavigationBar: appointment == null || !appointment.isOpen || _loading
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _working ? null : _reschedule,
                        icon: const Icon(Icons.edit_calendar_outlined, size: 18),
                        label: Text(s.tr('clinic.reschedule')),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: Theme.of(context).colorScheme.error,
                        ),
                        onPressed: _working ? null : _cancel,
                        icon: const Icon(Icons.close, size: 18),
                        label: Text(s.tr('clinic.cancel')),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildBody() {
    final s = AppLocalizations.of(context);
    if (_loading) return LoadingView(label: s.tr('clinic.loading'));
    if (_error != null) {
      return ErrorRetryView(message: _messageFor(_error!), onRetry: _load);
    }
    final appointment = _appointment;
    if (appointment == null) return EmptyStateView(message: s.tr('clinic.empty'));

    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        appointmentTypeLabel(s, appointment.appointmentType),
                        style: theme.textTheme.titleSmall,
                      ),
                    ),
                    AppointmentStatusChip(status: appointment.status),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                ClinicFactRow(
                  label: s.tr('clinic.date'),
                  value: formatScheduledAt(appointment.scheduledAt),
                ),
                ClinicFactRow(
                  label: s.tr('clinic.duration'),
                  value: '${appointment.durationMinutes}',
                ),
                ClinicFactRow(label: s.tr('clinic.facility'), value: appointment.facilityName),
                ClinicFactRow(label: s.tr('clinic.doctor'), value: appointment.doctorName),
                if (appointment.cancellationReason.isNotEmpty)
                  ClinicFactRow(
                    label: s.tr('clinic.cancellationReason'),
                    value: appointment.cancellationReason,
                  ),
              ],
            ),
          ),
        ),
        if (appointment.reason.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.md),
          Text(appointment.reason, style: theme.textTheme.bodyMedium),
        ],
        if (!appointment.isOpen) ...[
          const SizedBox(height: AppSpacing.lg),
          Text(s.tr('clinic.locked'), style: theme.textTheme.bodySmall),
        ],
      ],
    );
  }
}

class _ReasonDialog extends StatefulWidget {
  const _ReasonDialog({
    required this.title,
    required this.label,
    this.required = false,
  });

  final String title;
  final String label;
  final bool required;

  @override
  State<_ReasonDialog> createState() => _ReasonDialogState();
}

class _ReasonDialogState extends State<_ReasonDialog> {
  final _controller = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final value = _controller.text.trim();
    if (widget.required && value.isEmpty) {
      setState(() => _error = AppLocalizations.of(context).tr('clinic.cancelReasonRequired'));
      return;
    }
    Navigator.of(context).pop(value);
  }

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _controller,
        autofocus: true,
        maxLength: 1000,
        decoration: InputDecoration(
          labelText: widget.label,
          errorText: _error,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(s.tr('common.cancel')),
        ),
        FilledButton(onPressed: _submit, child: Text(s.tr('common.save'))),
      ],
    );
  }
}