import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/l10n/app_localizations.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../shared/widgets/state_views.dart';
import '../../../auth/data/token_store.dart';
import '../../../auth/domain/auth_types.dart';
import '../../../auth/presentation/controllers/auth_controller.dart';
import '../../../auth/presentation/widgets/session_scope.dart';
import '../../data/appointments_repository.dart';
import 'appointment_detail_page.dart';
import 'appointment_form_page.dart';
import '../../../../core/theme/app_shapes.dart';

/// Clinic calendar (§11).
///
/// Reads `GET /appointments/`, which the server has already narrowed to the
/// patients this account may see — own, consented or assigned. No client-side
/// patient filter exists here, and nothing is booked against a guessed clinic:
/// the picker offers only verified facilities the API returned, because the
/// server rejects anything else.
class ClinicPage extends StatelessWidget {
  const ClinicPage({super.key, this.authController, this.repository});

  static const String routeName = '/clinic';

  /// Injected by widget tests; the routed instance resolves the shared session.
  final AuthController? authController;
  final AppointmentsRepository? repository;

  @override
  Widget build(BuildContext context) {
    final token = (authController ?? SessionScope.controllerOf(context)).accessToken;
    final s = AppLocalizations.of(context);
    if (token == null) {
      return Scaffold(
        appBar: AppBar(title: Text(s.tr('clinic.title'))),
        body: Center(child: Text(s.tr('clinic.empty'))),
      );
    }
    return ClinicView(
      accessToken: token,
      repository: repository ??
          AppointmentsRepository(tokenStore: EphemeralTokenStore()),
    );
  }
}

class ClinicView extends StatefulWidget {
  const ClinicView({
    super.key,
    required this.accessToken,
    required this.repository,
  });

  final String accessToken;
  final AppointmentsRepository repository;

  @override
  State<ClinicView> createState() => _ClinicViewState();
}

class _ClinicViewState extends State<ClinicView> {
  List<ClinicAppointment> _items = const [];
  Object? _error;
  bool _loading = true;
  /// `null` = upcoming, `false` = past.
  bool? _upcoming = true;

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
      final items = await widget.repository.list(
        access: widget.accessToken,
        upcoming: _upcoming,
      );
      if (!mounted) return;
      setState(() {
        _items = items;
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

  Future<void> _book() async {
    final s = AppLocalizations.of(context);
    final booked = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => AppointmentFormPage(
          accessToken: widget.accessToken,
          repository: widget.repository,
        ),
      ),
    );
    if (booked == true && mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(s.tr('clinic.booked'))));
      await _load();
    }
  }

  Future<void> _open(ClinicAppointment item) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => AppointmentDetailPage(
          accessToken: widget.accessToken,
          repository: widget.repository,
          appointmentUid: item.uid,
        ),
      ),
    );
    if (changed == true) await _load();
  }

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(s.tr('clinic.title')),
        actions: [
          IconButton(
            tooltip: s.tr('common.refresh'),
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _loading ? null : _book,
        icon: const Icon(Icons.add),
        label: Text(s.tr('clinic.book')),
      ),
      body: Column(
        children: [
          SizedBox(
            height: 52,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              children: [
                for (final entry in const [(true, 'clinic.upcoming'), (false, 'clinic.past')])
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(s.tr(entry.$2)),
                      selected: _upcoming == entry.$1,
                      onSelected: (_) {
                        setState(() => _upcoming = entry.$1);
                        _load();
                      },
                    ),
                  ),
              ],
            ),
          ),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _buildBody() {
    final s = AppLocalizations.of(context);
    if (_loading) return LoadingView(label: s.tr('clinic.loading'));
    if (_error != null) {
      return ErrorRetryView(message: _messageFor(_error!), onRetry: _load);
    }
    if (_items.isEmpty) return EmptyStateView(message: s.tr('clinic.empty'));
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: _items.length,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          final item = _items[index];
          return Card(
            child: ListTile(
              title: Text(appointmentTypeLabel(s, item.appointmentType)),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 2),
                  Text(
                    formatScheduledAt(item.scheduledAt),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  Text(
                    item.facilityName.isEmpty
                        ? item.facilityCity
                        : '${item.facilityName} · ${item.facilityCity}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  if (item.doctorName.isNotEmpty)
                    Text(item.doctorName, style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
              isThreeLine: true,
              trailing: AppointmentStatusChip(status: item.status),
              onTap: () => _open(item),
            ),
          );
        },
      ),
    );
  }
}

/// Human local date/time for a `scheduled_at` ISO string — raw ISO never
/// reaches the UI (timezone-aware, matches the other list surfaces).
String formatScheduledAt(String iso) {
  final dt = DateTime.tryParse(iso)?.toLocal();
  if (dt == null) return iso;
  final hh = dt.hour.toString().padLeft(2, '0');
  final mm = dt.minute.toString().padLeft(2, '0');
  return '${dt.day}/${dt.month}/${dt.year} $hh:$mm';
}

/// Human label for an appointment type code.
String appointmentTypeLabel(AppLocalizations s, String code) =>
    s.tr('clinic.type.${_typeKey(code)}');

String _typeKey(String code) => switch (code) {
      'NEW_PATIENT' => 'newPatient',
      'FOLLOW_UP' => 'followUp',
      'ROUTINE_REVIEW' => 'routineReview',
      'LAB_RESULTS' => 'labResults',
      'MEDICATION_REVIEW' => 'medicationReview',
      'VACCINATION' => 'vaccination',
      _ => 'other',
    };

/// Human label for an appointment status code.
String appointmentStatusLabel(AppLocalizations s, String code) =>
    s.tr('clinic.status.${_statusKey(code)}');

String _statusKey(String code) => switch (code) {
      'REQUESTED' => 'requested',
      'CONFIRMED' => 'confirmed',
      'COMPLETED' => 'completed',
      'RESCHEDULED' => 'rescheduled',
      'CANCELLED' => 'cancelled',
      'NO_SHOW' => 'noShow',
      _ => 'requested',
    };

class AppointmentStatusChip extends StatelessWidget {
  const AppointmentStatusChip({super.key, required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context);
    final (color, label) = switch (status) {
      'CONFIRMED' => (AppColors.success, s.tr('clinic.status.confirmed')),
      'COMPLETED' => (AppColors.info, s.tr('clinic.status.completed')),
      'RESCHEDULED' => (AppColors.warning, s.tr('clinic.status.rescheduled')),
      'CANCELLED' => (AppColors.textSecondary, s.tr('clinic.status.cancelled')),
      'NO_SHOW' => (AppColors.emergency, s.tr('clinic.status.noShow')),
      _ => (AppColors.info, s.tr('clinic.status.requested')),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: AppShapes.pill,
      ),
      child: Text(label, style: TextStyle(fontSize: 11, color: color)),
    );
  }
}

/// Small labelled value row used by the detail and booking screens.
class ClinicFactRow extends StatelessWidget {
  const ClinicFactRow({
    super.key,
    required this.label,
    required this.value,
    this.padding = const EdgeInsets.only(bottom: AppSpacing.xs),
  });

  final String label;
  final String value;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    if (value.trim().isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    return Padding(
      padding: padding,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 130, child: Text(label, style: theme.textTheme.bodySmall)),
          Expanded(child: Text(value, style: theme.textTheme.bodyMedium)),
        ],
      ),
    );
  }
}